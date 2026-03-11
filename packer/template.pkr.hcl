variable "ami_name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "ubuntu_series" {
  type    = string
  default = "22.04"
}

variable "source_archive_path" {
  type    = string
  default = ""
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  ami_name  = "${var.ami_name_prefix}-${local.timestamp}"

  common_tags = merge({
    Name       = local.ami_name
    ManagedBy  = "packer"
    BuildType  = "ami"
    SourceRepo = "ami-baker-repo"
  }, var.extra_tags)

  archive_enabled = length(trimspace(var.source_archive_path)) > 0
}

data "amazon-ami" "ubuntu" {
  filters = {
    name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }

  most_recent = true
  owners      = ["099720109477"]
  region      = var.region
}

source "amazon-ebs" "ubuntu" {
  region                      = var.region
  instance_type               = var.instance_type
  ssh_username                = "ubuntu"
  ami_name                    = local.ami_name
  ami_description             = "CTF/tooling image baked by Packer"
  source_ami                  = data.amazon-ami.ubuntu.id
  associate_public_ip_address = true
  communicator                = "ssh"
  ssh_keypair_name            = "packer"
  ssh_private_key_file        = "~/.ssh/packer.pem"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 80
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags     = local.common_tags
  run_tags = local.common_tags

  # Keep the image private. The post-build script enforces this again.
  ami_groups = []
  ami_users  = []

  temporary_security_group_source_public_ip = true

  aws_polling {
    delay_seconds = 30
    max_attempts  = 420
  }

}

build {
  name    = "ctf-tooling-ami"
  sources = ["source.amazon-ebs.ubuntu"]

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /tmp/ami-baker /opt/infra /opt/jadx /etc/profile.d /var/log/ami-baker",
      "sudo chown -R ubuntu:ubuntu /tmp/ami-baker /opt/infra /var/log/ami-baker"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../scripts/provision.sh"
    destination = "/tmp/ami-baker/provision.sh"
  }

  provisioner "file" {
    source      = "${path.root}/../files/ctf-tooling.sh"
    destination = "/tmp/ami-baker/ctf-tooling.sh"
  }

  provisioner "file" {
    source      = "${path.root}/../files/htb-mcp.service"
    destination = "/tmp/ami-baker/htb-mcp.service"
  }

  provisioner "file" {
    source      = "${path.root}/../files/install_ez_tools.sh"
    destination = "/tmp/ami-baker/install_ez_tools.sh"
  }


  dynamic "provisioner" {
    for_each = local.archive_enabled ? [1] : []
    labels   = ["file"]
    content {
      source      = var.source_archive_path
      destination = "/tmp/ami-baker/src_archive.tar.gz"
    }
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/ami-baker/provision.sh",
      "sudo /tmp/ami-baker/provision.sh"
    ]
  }

  post-processor "manifest" {
    output = "${path.root}/../build/manifest.json"
  }
}
