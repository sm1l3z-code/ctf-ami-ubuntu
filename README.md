# ami-baker-repo

Builds a private EC2 AMI for the current AWS account from end to end using Packer.

The baked image moves the heavy parts of your old `user_data` into image creation time:
- system packages
- SecLists
- Node/NVM and global CLIs
- Ruby gems
- Foundry tools
- Miniforge + Sage env
- Python packages
- Rust toolchain
- `jadx`
- the `htb-mcp` binary and systemd unit

The resulting AMI is explicitly locked down to the AWS account that built it. It is not made public and is not shared with any other AWS accounts.

## What stays out of the AMI

Do **not** bake secrets into the image. Keep these at runtime:
- API keys
- environment-specific URLs
- per-launch config
- short-lived archives or challenge data that change often

## Repo layout

```text
.
├── README.md
├── .gitignore
├── artifacts/
│   ├── .gitkeep
│   └── src_archive.tar.gz      # optional local source archive to bake in
├── files/
│   ├── ctf-tooling.sh
│   └── htb-mcp.service
├── packer/
│   ├── base.auto.pkrvars.hcl.example
│   ├── template.pkr.hcl
│   └── versions.pkr.hcl
└── scripts/
    ├── build_ami.sh
    ├── ensure_private_ami.sh
    └── provision.sh
```

## Prerequisites

Install locally:
- AWS CLI v2
- Packer 1.10+
- bash
- jq

Configure AWS credentials in the normal way, for example with a named profile.

The caller needs permissions for:
- `ec2:*` actions related to images, snapshots, instances, security groups, key pairs, subnets, VPC lookups, and tags
- `sts:GetCallerIdentity`

In practice, a role with sufficient EC2 image build permissions is enough.

## Quick start

1. Copy the example variables file.

```bash
cp packer/base.auto.pkrvars.hcl.example packer/base.auto.pkrvars.hcl
```

2. Edit `packer/base.auto.pkrvars.hcl`.

3. Optionally place a local source archive at:

```text
artifacts/src_archive.tar.gz
```

That archive is extracted to `/opt/infra` during the bake.

4. Run the build.

```bash
./scripts/build_ami.sh
```

By default the script uses the AWS profile `default`. To override:

```bash
AWS_PROFILE=my-profile AWS_REGION=eu-central-1 ./scripts/build_ami.sh
```

## Inputs

### Required variables

Set these in `packer/base.auto.pkrvars.hcl`:

- `ami_name_prefix`
- `region`
- `instance_type`
- `vpc_id`
- `subnet_id`

### Optional variables

- `source_archive_path` — local path to a tar.gz archive to upload and extract to `/opt/infra`
- `extra_tags` — additional tags to add to the AMI and temporary builder instance
- `ubuntu_series` — defaults to `22.04`

## Output

At the end, the script prints:
- the AMI ID
- the AWS account ID
- the region

It also writes the AMI ID to:

```text
build/last_ami_id
```

## Runtime pattern after baking

Use tiny `user_data` only for runtime config, for example:

```bash
#!/bin/bash
set -euo pipefail
exec > /var/log/user-data.log 2>&1

mkdir -p /sherlock/{evidence,analysis,truths,timeline}
mkdir -p /challenge

cat > /opt/infra/.env <<EOF2
API_GATEWAY_KEY=${api_gateway_key}
API_GATEWAY_URL=${api_gateway_url}
EOF2
chmod 600 /opt/infra/.env

systemctl daemon-reload
systemctl enable htb-mcp
systemctl restart htb-mcp
```

## How privacy is enforced

The AMI remains private in two ways:

1. The Packer template does not set any public or shared launch permissions.
2. After the build, `scripts/ensure_private_ami.sh` removes any `launchPermission` entries it finds and removes the public group if present.

That leaves the AMI usable only by the account that owns it.

## Notes

- This repo assumes Ubuntu and internet access during the build.
- Some installs are large and can still take a while, but that happens at AMI build time, not on every instance launch.
- If your app code changes frequently, keep the toolchain in the AMI and ship only the changing app bundle at runtime.
