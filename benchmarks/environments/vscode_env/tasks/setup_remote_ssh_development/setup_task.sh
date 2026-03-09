#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Remote SSH Development Task ==="

# Install SSH server if not present
if ! command -v sshd &> /dev/null; then
    echo "Installing OpenSSH server..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server > /dev/null 2>&1
fi

# Create developer user (simulates remote server user)
if ! id -u developer &> /dev/null; then
    echo "Creating developer user..."
    useradd -m -s /bin/bash developer
    echo "developer:devpassword" | chpasswd
fi

# Install Node.js on "remote" if not present (as developer user)
if ! su - developer -c "command -v node" &> /dev/null; then
    echo "Installing Node.js for developer user..."
    # Node.js should already be installed system-wide from env setup
    # Just verify it's accessible
    if ! command -v node &> /dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
        apt-get install -y nodejs > /dev/null 2>&1
    fi
fi

# Create SSH directory for developer
mkdir -p /home/developer/.ssh
chmod 700 /home/developer/.ssh
touch /home/developer/.ssh/authorized_keys
chmod 600 /home/developer/.ssh/authorized_keys

# Generate SSH keypair for ga user if not exists
if [ ! -f /home/ga/.ssh/id_rsa_devserver ]; then
    echo "Generating SSH keypair..."
    sudo -u ga mkdir -p /home/ga/.ssh
    sudo -u ga ssh-keygen -t rsa -b 4096 -f /home/ga/.ssh/id_rsa_devserver -N "" -C "vscode-remote-dev" > /dev/null 2>&1
    chmod 600 /home/ga/.ssh/id_rsa_devserver
    chmod 644 /home/ga/.ssh/id_rsa_devserver.pub
fi

# Add public key to developer's authorized_keys
cat /home/ga/.ssh/id_rsa_devserver.pub > /home/developer/.ssh/authorized_keys
chown -R developer:developer /home/developer/.ssh

# Configure SSH server to listen on port 2222 (avoid conflicts)
mkdir -p /run/sshd
cat > /etc/ssh/sshd_config.d/vscode_remote.conf << 'EOF'
Port 2222
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication yes
AllowUsers developer ga
EOF

# Start SSH server
echo "Starting SSH server..."
/usr/sbin/sshd -D &
SSHD_PID=$!

# Wait for SSH to be ready
for i in {1..10}; do
    if netstat -tuln 2>/dev/null | grep -q ':2222 ' || ss -tuln 2>/dev/null | grep -q ':2222 '; then
        echo "SSH server ready on port 2222"
        break
    fi
    sleep 1
done

# Test SSH connection
echo "Testing SSH connection..."
sudo -u ga ssh -i /home/ga/.ssh/id_rsa_devserver -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -p 2222 developer@127.0.0.1 "echo SSH connection successful" || {
    echo "⚠️ SSH test failed, but continuing..."
}

# Ensure Remote-SSH extension is installed locally
echo "Checking Remote-SSH extension..."
if ! sudo -u ga code --list-extensions 2>/dev/null | grep -q "ms-vscode-remote.remote-ssh"; then
    echo "Installing Remote-SSH extension..."
    sudo -u ga DISPLAY=:1 code --install-extension ms-vscode-remote.remote-ssh --force > /dev/null 2>&1 || {
        echo "⚠️ Remote-SSH installation may have failed, continuing..."
    }
    sleep 3
fi

# Clean up any existing SSH config to start fresh
sudo -u ga rm -f /home/ga/.ssh/config

# Ensure VSCode is running
if ! pgrep -u ga -f "code" > /dev/null; then
    echo "Starting VSCode..."
    su - ga -c "DISPLAY=:1 code --new-window" &
    wait_for_vscode 20
fi

wait_for_window "Visual Studio Code" 30

# Click center to focus
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" 2>/dev/null || true
sleep 1

focus_vscode_window
sleep 2

# Close any existing welcome tabs
su - ga -c "DISPLAY=:1 xdotool key --delay 100 ctrl+w" 2>/dev/null || true
sleep 1

echo "=== Remote SSH Development Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "REMOTE SERVER INFO:"
echo "  • Host: 127.0.0.1"
echo "  • Port: 2222"
echo "  • User: developer"
echo "  • SSH Key: /home/ga/.ssh/id_rsa_devserver (already created)"
echo ""
echo "STEP 1: Configure SSH"
echo "  Create ~/.ssh/config with connection details"
echo ""
echo "STEP 2: Connect to Remote"
echo "  Use Command Palette → 'Remote-SSH: Connect to Host'"
echo "  Select 'devserver' (or add as new host)"
echo "  Wait for VSCode Server to install remotely"
echo ""
echo "STEP 3: Install ESLint Extension REMOTELY"
echo "  Extensions view → Search 'ESLint'"
echo "  Install on 'SSH: DEVSERVER' (not locally!)"
echo ""
echo "STEP 4: Open Remote Workspace"
echo "  File → Open Folder → /home/developer/projects/"
echo ""
echo "STEP 5: Create and Run Node.js Server"
echo "  Create: /home/developer/projects/hello-server.js"
echo "  Run in integrated terminal: node hello-server.js &"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⏰ Time limit: 7 minutes"
echo "✅ Verify remote connection indicator in bottom-left corner"
echo ""