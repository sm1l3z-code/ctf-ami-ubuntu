#!/bin/bash

set -xeu pipefail

npm install -g @openai/codex 

mkdir -p /root/.codex/skills

cat > /root/.codex/config.toml <<'EOCFG'
model = "gpt-5.4"
model_provider = "openai"
model_reasoning_effort = "xhigh"

# optional
personality = "pragmatic"

[mcp_servers.htb-mcp]
url = "http://127.0.0.1:3000/mcp"
enabled = true

EOCFG
