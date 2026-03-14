#!/bin/bash
set -xeu pipefail

curl -fsSL https://claude.ai/install.sh | bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
/root/.local/bin/claude mcp add htb-mcp --transport http http://127.0.0.1:3000/mcp --scope user
mkdir -p /root/.claude/skills
