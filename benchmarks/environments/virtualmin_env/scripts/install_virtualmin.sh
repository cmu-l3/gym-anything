#!/bin/bash
# NOTE: Do NOT use set -e here - we run installer in background and need careful exit control

echo "=== Installing Virtualmin GPL ==="

export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------
# IDEMPOTENCY CHECK: Skip installer if Virtualmin already installed.
# This handles the case where the gym_anything framework loads a
# savevm checkpoint (which already has Virtualmin) and re-runs hooks.
# ---------------------------------------------------------------
if which virtualmin > /dev/null 2>&1 && [ -f /home/ga/virtualmin-install-done ]; then
    echo "=== Virtualmin already installed (idempotency check). Skipping installer. ==="
    # Still ensure root password and hostname are set correctly
    echo "root:GymAnything123!" | chpasswd
    hostnamectl set-hostname virtualmin.gym-anything.local 2>/dev/null || true
    # Install GUI tools if not present
    which xdotool > /dev/null 2>&1 || apt-get install -y xdotool wmctrl scrot imagemagick x11-utils xclip python3-pip 2>/dev/null
    echo "=== install_virtualmin.sh (idempotent skip) complete ==="
    exit 0
fi

# ---------------------------------------------------------------
# 1. Set root password (Virtualmin admin uses the root Unix account)
# ---------------------------------------------------------------
echo "root:GymAnything123!" | chpasswd
echo "--- Root password set ---"

# ---------------------------------------------------------------
# 2. Set FQDN hostname (REQUIRED by Virtualmin installer)
# ---------------------------------------------------------------
hostnamectl set-hostname virtualmin.gym-anything.local

if ! grep -q "virtualmin.gym-anything.local" /etc/hosts; then
    echo "127.0.1.1 virtualmin.gym-anything.local virtualmin" >> /etc/hosts
fi

FQDN=$(hostname -f 2>/dev/null || echo "unknown")
echo "--- Hostname set to: $FQDN ---"

# ---------------------------------------------------------------
# 3. Update packages and install prerequisites
# ---------------------------------------------------------------
apt-get update
apt-get install -y curl wget ca-certificates perl

# ---------------------------------------------------------------
# 4. Download Virtualmin installer
#    Primary: software.virtualmin.com
#    Fallback: download.virtualmin.com
# ---------------------------------------------------------------
echo "=== Downloading Virtualmin installer ==="

if ! curl -fsSL https://software.virtualmin.com/gpl/scripts/virtualmin-install.sh \
        -o /tmp/virtualmin-install.sh 2>/dev/null; then
    echo "Primary URL failed, trying fallback..."
    curl -fsSL https://download.virtualmin.com/virtualmin-install.sh \
        -o /tmp/virtualmin-install.sh
fi

chmod +x /tmp/virtualmin-install.sh
echo "--- Installer downloaded, size: $(wc -c < /tmp/virtualmin-install.sh) bytes ---"

# ---------------------------------------------------------------
# 5. Run Virtualmin installer in BACKGROUND to avoid SSH timeout
#    The installer asks "Continue? (y/n)" — we answer via printf.
#    Running with nohup & detaches from the SSH session so the
#    installation continues even after this SSH command returns.
#    NOTE: Cold installation takes 30-60 minutes. The post_start
#    hook polls for completion. Use savevm caching for fast boots.
# ---------------------------------------------------------------
echo "=== Starting Virtualmin installation in background ==="

# Mark start time
date > /home/ga/virtualmin-install-start
chmod 644 /home/ga/virtualmin-install-start

# Run installer in background with "y" piped to answer the prompt
nohup bash -c '
    printf "y\n" | bash /tmp/virtualmin-install.sh \
        --bundle LAMP \
        --hostname virtualmin.gym-anything.local \
        > /home/ga/virtualmin-install.log 2>&1
    echo "Virtualmin installer exit code: $?" >> /home/ga/virtualmin-install.log
    touch /home/ga/virtualmin-install-done
' &

INSTALL_PID=$!
echo "--- Virtualmin installation started in background (PID: $INSTALL_PID) ---"
echo "$INSTALL_PID" > /home/ga/virtualmin-install.pid
chmod 644 /home/ga/virtualmin-install.pid

# Wait briefly to check installer started OK
sleep 15
if kill -0 "$INSTALL_PID" 2>/dev/null; then
    echo "--- Installer is running ---"
else
    echo "--- WARNING: Installer may have exited early, check /home/ga/virtualmin-install.log ---"
    # Even if it exited, it might have completed quickly
fi

# ---------------------------------------------------------------
# 6. Install GUI automation tools while installer runs in background
# ---------------------------------------------------------------
echo "--- Installing GUI automation tools ---"
apt-get install -y \
    xdotool \
    wmctrl \
    scrot \
    imagemagick \
    x11-utils \
    xclip \
    python3-pip

echo "=== install_virtualmin.sh complete ==="
echo "NOTE: Virtualmin installer is running in background at /home/ga/virtualmin-install.log"
echo "      setup_virtualmin.sh (post_start) will wait for installation to complete."
