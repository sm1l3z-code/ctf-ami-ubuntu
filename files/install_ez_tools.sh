#!/bin/bash

set -euo pipefail

# Install .NET 9 from Microsoft's Ubuntu 24.04 feed.

curl -fsSL https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb -o packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm -f packages-microsoft-prod.deb
sudo add-apt-repository ppa:dotnet/backports -y
apt-get update && apt-get install -y dotnet-sdk-9.0

# Array of Eric Zimmerman tools to install
# Based on the net9 download structure
tools=(
    "AmcacheParser"
    "AppCompatCacheParser"
    "bstrings"
    "EvtxECmd"
    "JLECmd"
    "LECmd"
    "MFTECmd"
    "PECmd"
    "RBCmd"
    "RECmd"
    "SBECmd"
    "SQLECmd"
    "SrumECmd"
    "SumECmd"
    "WxTCmd"
)

BASE_URL='https://download.ericzimmermanstools.com/net9'

for tool in "${tools[@]}"; do
    echo "----------------------------------------------------"
    echo "Installing $tool..."
    echo "----------------------------------------------------"

    # 1. Download the tool
    wget "${BASE_URL}/${tool}.zip" -O "/tmp/${tool}.zip"

    # 2. Create the destination directory
    mkdir -p "/opt/$tool"

    # 3. Unzip the tool
    unzip -o "/tmp/${tool}.zip" -d "/opt/$tool"

    # 4. Create the /usr/bin wrapper script
    # Lowercase the command name for easier typing (e.g., 'mftecmd')
    cmd_name=$(echo "$tool" | tr '[:upper:]' '[:lower:]')
    
    # Note: Some tools like RECmd have nested folders (RECmd/RECmd.dll)
    # We use find to locate the correct .dll regardless of nesting
    dll_path=$(find "/opt/$tool" -name "${tool}.dll" | head -n 1)

    if [ -z "$dll_path" ]; then
        echo "Error: Could not find ${tool}.dll in /opt/$tool"
    else
        cat <<EOF > "/usr/bin/$cmd_name"
#!/bin/bash
dotnet "$dll_path" "\$@"
EOF
        chmod +x "/usr/bin/$cmd_name"
        echo "Created command: $cmd_name"
    fi

    # 5. Cleanup
    rm -f "/tmp/${tool}.zip"
done

echo "----------------------------------------------------"
echo "Installation complete. You can now run tools by name (e.g., 'mftecmd')."
