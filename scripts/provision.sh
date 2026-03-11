#!/usr/bin/env bash
set -euo pipefail

exec > >(tee /var/log/ami-baker/provision.log) 2>&1
export DEBIAN_FRONTEND=noninteractive
export HOME=/root
export NVM_DIR=/root/.nvm

retry() {
  local attempts=$1
  shift
  local n=1
  until "$@"; do
    if [[ $n -ge $attempts ]]; then
      echo "command failed after ${attempts} attempts: $*" >&2
      return 1
    fi
    n=$((n + 1))
    sleep 5
  done
}

log() {
  echo
  echo "==== $* ===="
}

ensure_path() {
  local line='export PATH="/opt/jadx/bin:/root/.cargo/bin:/root/.foundry/bin:/opt/miniforge3/bin:/opt/miniforge3/envs/sage/bin:$PATH"'
  grep -qxF "$line" /root/.bashrc || echo "$line" >> /root/.bashrc
}

log "preseed tshark/wireshark"
echo 'wireshark-common wireshark-common/install-setuid boolean true' | debconf-set-selections


apt-get clean
rm -rf /var/lib/apt/lists/*


log "apt packages"
retry 5 apt-get update -y
retry 3 apt-get install -y \
  ca-certificates \
  curl \
  docker.io \
  git \
  gnupg \
  jq \
  npm \
  procps \
  software-properties-common \
  tmux \
  unzip \
  wget \
  build-essential \
  cpio \
  exiftool \
  ffmpeg \
  file \
  gdb \
  hashcat \
  imagemagick \
  jq \
  kmod \
  libffi-dev \
  libgmp-dev \
  libssl-dev \
  libxml2-dev \
  libxslt1-dev \
  libzbar0 \
  nasm \
  neovim \
  nmap \
  p7zip-full \
  php \
  pkg-config \
  poppler-utils \
  python3 \
  python3-dev \
  python3-lxml \
  python3-pip \
  python3-venv \
  ripgrep \
  ruby-full \
  sigrok-cli \
  sqlite3 \
  smbclient \
  strace \
  tesseract-ocr \
  tshark \
  util-linux \
  xxd \
  binwalk \
  default-jdk \
  golang-go \
  ncat \
  python3-websocket \
  gcc-avr \
  mosquitto-clients \
  ruby-full

systemctl enable docker || true

# Install radare2
cd /tmp
git clone https://github.com/radareorg/radare2
cd radare2
./configure --prefix=/usr
make -j8
make install
cd - 2>/dev/null

log "directories"
mkdir -p /opt/infra /opt/jadx /sherlock/{evidence,analysis,truths,timeline} /challenge

if [[ -f /tmp/ami-baker/src_archive.tar.gz ]]; then
  log "extracting local source archive"
  tar xzf /tmp/ami-baker/src_archive.tar.gz -C /opt/infra
fi

log "SecLists"
if [[ ! -d /opt/SecLists ]]; then
  git clone https://github.com/danielmiessler/SecLists /opt/SecLists
fi

if [[ -d /opt/infra/brain/notes ]]; then
  cp -r /opt/infra/brain/notes /challenge/
fi

log "install nvm/node/global npm tools"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
fi
# shellcheck disable=SC1090
source "$NVM_DIR/nvm.sh"
nvm install node
npm install -g @google/gemini-cli @openai/codex localtunnel

mkdir -p /root/.gemini /root/.codex/skills
if [[ -f /opt/infra/brain/AGENT.md ]]; then
  cp /opt/infra/brain/AGENT.md /root/.gemini/GEMINI.md
  cp /opt/infra/brain/AGENT.md /root/.codex/AGENTS.md
fi
if [[ -d /opt/infra/brain/skills ]]; then
  rm -rf /root/.gemini/skills /root/.codex/skills
  cp -R /opt/infra/brain/skills /root/.gemini/skills
  cp -R /opt/infra/brain/skills /root/.codex/skills
fi
mkdir -p /root/.codex
cat > /root/.codex/config.toml <<'EOCFG'
[mcp_servers.htb-mcp]
url = "http://127.0.0.1:3000/mcp"
enabled = true
EOCFG

log "ruby gems"
gem install one_gadget seccomp-tools

log "foundry"
if [[ ! -x /root/.foundry/bin/foundryup ]]; then
  curl -fsSL https://foundry.paradigm.xyz | bash
fi
/root/.foundry/bin/foundryup
install -m 0755 /root/.foundry/bin/forge /usr/local/bin/forge
install -m 0755 /root/.foundry/bin/cast /usr/local/bin/cast
install -m 0755 /root/.foundry/bin/anvil /usr/local/bin/anvil
install -m 0755 /root/.foundry/bin/chisel /usr/local/bin/chisel

log "miniforge and sage"
if [[ ! -d /opt/miniforge3 ]]; then
  curl -fsSL -o /tmp/miniforge.sh "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
  bash /tmp/miniforge.sh -b -p /opt/miniforge3
  rm -f /tmp/miniforge.sh
fi
/opt/miniforge3/bin/conda config --system --set always_yes yes --set changeps1 no
if [[ ! -d /opt/miniforge3/envs/sage ]]; then
  /opt/miniforge3/bin/mamba create -n sage sage python=3.11
fi
/opt/miniforge3/envs/sage/bin/pip install --upgrade pip
/opt/miniforge3/envs/sage/bin/pip install pwntools pycryptodome

log "profile"
install -m 0644 /tmp/ami-baker/ctf-tooling.sh /etc/profile.d/ctf-tooling.sh
ensure_path
install -m 0755 /opt/miniforge3/envs/sage/bin/sage /usr/local/bin/sage

if [[ -x /tmp/ami-baker/install_ez_tools.sh ]]; then
  log "running install_ez_tools.sh"
  chmod +x /tmp/ami-baker/install_ez_tools.sh
  /tmp/ami-baker/install_ez_tools.sh
fi

if command -v dotnet >/dev/null 2>&1; then
  log "dotnet tool ilspycmd"
  dotnet tool install --global ilspycmd || dotnet tool update --global ilspycmd
  if [[ -x /root/.dotnet/tools/ilspycmd ]]; then
    install -m 0755 /root/.dotnet/tools/ilspycmd /usr/local/bin/ilspycmd
  fi
fi

log "python packages"
python3 -m pip install --upgrade pip setuptools wheel 
python3 -m pip install --ignore-installed typing_extensions \
  uv \
  z3-solver \
  PyJWT \
  rlp \
  scapy \
  torchvision \
  pymodbus \
  scikit-learn \
  qiskit \
  pycryptodome \
  numpy \
  pwntools \
  tensorflow \
  pefile \
  r2pipe \
  gmpy2 \
  python-snap7 \
  asyncua \
  pygerber \
  Flask \
  Pillow \
  numpy \
  scipy \
  opencv-python \
  androguard

log "jadx"
if [[ ! -x /opt/jadx/bin/jadx ]]; then
  cd /opt/jadx
  wget -q https://github.com/skylot/jadx/releases/download/v1.5.5/jadx-1.5.5.zip
  unzip -q jadx-1.5.5.zip
  chmod +x /opt/jadx/bin/jadx
fi

log "rust and htb-mcp"
if [[ ! -x /root/.cargo/bin/rustc ]]; then
  curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal
fi
# shellcheck disable=SC1091
source /root/.cargo/env
if [[ -f /opt/infra/htb-mcp/Cargo.toml ]]; then
  cargo build --release --manifest-path /opt/infra/htb-mcp/Cargo.toml
fi

log "systemd service"
install -m 0644 /tmp/ami-baker/htb-mcp.service /etc/systemd/system/htb-mcp.service
systemctl daemon-reload
systemctl enable htb-mcp || true

log "cleanup"
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/ami-baker /tmp/*

log "done"
