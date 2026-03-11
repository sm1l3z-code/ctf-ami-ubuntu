#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <region> <ami-id>" >&2
  exit 1
fi

REGION=$1
AMI_ID=$2
AWS_PROFILE=${AWS_PROFILE:-default}

ACCOUNT_ID=$(aws sts get-caller-identity \
  --profile "$AWS_PROFILE" \
  --query Account \
  --output text)

ATTR_JSON=$(aws ec2 describe-image-attribute \
  --region "$REGION" \
  --profile "$AWS_PROFILE" \
  --image-id "$AMI_ID" \
  --attribute launchPermission \
  --output json)

REMOVE_USERS=$(jq -c '[.LaunchPermissions[]? | select(.UserId != null) | {UserId: .UserId}]' <<<"$ATTR_JSON")
HAS_PUBLIC=$(jq -r 'any(.LaunchPermissions[]?; .Group == "all")' <<<"$ATTR_JSON")

if [[ "$REMOVE_USERS" != "[]" ]]; then
  aws ec2 modify-image-attribute \
    --region "$REGION" \
    --profile "$AWS_PROFILE" \
    --image-id "$AMI_ID" \
    --launch-permission "Remove=${REMOVE_USERS}"
fi

if [[ "$HAS_PUBLIC" == "true" ]]; then
  aws ec2 modify-image-attribute \
    --region "$REGION" \
    --profile "$AWS_PROFILE" \
    --image-id "$AMI_ID" \
    --launch-permission 'Remove=[{Group=all}]'
fi

PUBLIC=$(aws ec2 describe-images \
  --region "$REGION" \
  --profile "$AWS_PROFILE" \
  --image-ids "$AMI_ID" \
  --query 'Images[0].Public' \
  --output text)

if [[ "$PUBLIC" != "False" ]]; then
  echo "AMI is still public, refusing to continue" >&2
  exit 1
fi

LEFTOVER=$(aws ec2 describe-image-attribute \
  --region "$REGION" \
  --profile "$AWS_PROFILE" \
  --image-id "$AMI_ID" \
  --attribute launchPermission \
  --query 'LaunchPermissions[?UserId!=null || Group==`all`]' \
  --output json)

if [[ "$LEFTOVER" != "[]" ]]; then
  echo "AMI still has external launch permissions: $LEFTOVER" >&2
  exit 1
fi

echo "AMI $AMI_ID in $REGION is private to account $ACCOUNT_ID"
