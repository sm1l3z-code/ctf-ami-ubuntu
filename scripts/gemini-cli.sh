#!/bin/bash

set -xeu pipefil

npm install -g @google/gemini-cli

mkdir -p /root/.gemini/skills

cat << EOF > /root/.gemini/settings.json
{
  "security": {
    "auth": {
      "selectedType": "oauth-personal"
    }
  },
  "context": {
    "fileName": ["AGENTS.md", "CONTEXT.md", "GEMINI.md"]
  },
  "mcpServers": {
    "htb-mcp": {
      "url": "http://127.0.0.1:3000/mcp",
      "type": "http"
    }
  }
}
EOF
