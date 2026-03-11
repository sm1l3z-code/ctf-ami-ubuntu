#!/usr/bin/env bash
set -euo pipefail

./scripts/gen_artifacts.sh

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PACKER_DIR="$ROOT_DIR/packer"
BUILD_DIR="$ROOT_DIR/build"
mkdir -p "$BUILD_DIR"

export AWS_PROFILE=ctf-terraform
export AWS_SDK_LOAD_CONFIG=1

VAR_FILE=${VAR_FILE:-$PACKER_DIR/base.auto.pkrvars.hcl}
AWS_REGION=${AWS_REGION:-}

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

need aws
need packer
need jq

if [[ ! -f "$VAR_FILE" ]]; then
  echo "missing var file: $VAR_FILE" >&2
  echo "copy packer/base.auto.pkrvars.hcl.example to packer/base.auto.pkrvars.hcl and edit it" >&2
  exit 1
fi

if [[ -n "$AWS_REGION" ]]; then
  TMP_VARS="$BUILD_DIR/runtime.auto.pkrvars.hcl"
  cp "$VAR_FILE" "$TMP_VARS"
  if grep -q '^region\s*=' "$TMP_VARS"; then
    sed -i.bak -E "s|^region\s*=.*$|region = \"$AWS_REGION\"|" "$TMP_VARS"
    rm -f "$TMP_VARS.bak"
  else
    echo "region = \"$AWS_REGION\"" >> "$TMP_VARS"
  fi
  EFFECTIVE_VAR_FILE="$TMP_VARS"
else
  EFFECTIVE_VAR_FILE="$VAR_FILE"
fi

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
REGION=$(awk -F'=' '/^region[[:space:]]*=/{gsub(/[ "\r]/,"",$2); print $2}' "$EFFECTIVE_VAR_FILE" | tail -1)

if [[ -z "$REGION" ]]; then
  echo "could not determine region from $EFFECTIVE_VAR_FILE" >&2
  exit 1
fi

export PACKER_LOG=${PACKER_LOG:-1}
export PACKER_LOG_PATH=${PACKER_LOG_PATH:-$BUILD_DIR/packer.log}

echo "AWS profile: $AWS_PROFILE"
echo "AWS account: $ACCOUNT_ID"
echo "AWS region:  $REGION"
echo


(
  cd "$PACKER_DIR"
  packer init .
  packer validate -var-file="$EFFECTIVE_VAR_FILE" .
  packer build -color=false -var-file="$EFFECTIVE_VAR_FILE" . | tee "$BUILD_DIR/packer-build.out"
)

cd - >/dev/null

MANIFEST="$BUILD_DIR/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "manifest not found at $MANIFEST" >&2
  exit 1
fi

AMI_ID=$(jq -r '.builds[-1].artifact_id' "$MANIFEST" | awk -F: '{print $2}')
if [[ -z "$AMI_ID" || "$AMI_ID" == "null" ]]; then
  echo "could not parse AMI ID from manifest" >&2
  exit 1
fi

"$ROOT_DIR/scripts/ensure_private_ami.sh" "$REGION" "$AMI_ID"

echo "$AMI_ID" > "$BUILD_DIR/last_ami_id"

echo
echo "Build complete"
echo "AMI ID:      $AMI_ID"
echo "Account ID:  $ACCOUNT_ID"
echo "Region:      $REGION"
echo "Manifest:    $MANIFEST"
echo "Packer log:  $PACKER_LOG_PATH"
