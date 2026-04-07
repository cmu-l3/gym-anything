#!/bin/bash
set -e

echo "=== Installing Anaconda Distribution ==="

# Non-interactive apt
export DEBIAN_FRONTEND=noninteractive

# Fix potential apt_pkg issues
if [ -f /usr/lib/cnf-update-db ]; then
    chmod -x /usr/lib/cnf-update-db 2>/dev/null || true
fi

# Update package lists
apt-get update || {
    echo "Warning: apt-get update had some errors, continuing anyway..."
}

# Install base dependencies
echo "Installing base dependencies..."
apt-get install -y \
    wget \
    curl \
    ca-certificates \
    bzip2 \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libxext6 \
    libsm6 \
    libxrender1 \
    libfontconfig1 \
    libxi6 \
    libxkbcommon0 \
    libxkbcommon-x11-0 \
    libdbus-1-3 \
    libxcb-xinerama0 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-randr0 \
    libxcb-render-util0 \
    libxcb-shape0 \
    libxcb-cursor0 \
    libegl1 \
    libxdamage1 \
    libxcomposite1 \
    libxrandr2 \
    libxtst6 \
    libxss1 \
    libnss3 \
    libasound2

# Install GUI automation tools
echo "Installing GUI automation tools..."
apt-get install -y \
    xdotool \
    wmctrl \
    scrot \
    imagemagick \
    x11-utils \
    xclip \
    python3-pip \
    jq

# Install Firefox for Jupyter Notebook access
echo "Installing Firefox..."
apt-get install -y firefox || {
    echo "Warning: Firefox install had issues, trying snap fallback..."
    snap install firefox 2>/dev/null || true
}

# Download Anaconda installer
echo "Downloading Anaconda Distribution..."
ANACONDA_VERSION="2024.10-1"
ANACONDA_URL="https://repo.anaconda.com/archive/Anaconda3-${ANACONDA_VERSION}-Linux-x86_64.sh"

echo "Downloading from: $ANACONDA_URL"
if ! wget -q --show-progress "$ANACONDA_URL" -O /tmp/anaconda_installer.sh; then
    echo "Trying alternate version..."
    ANACONDA_VERSION="2024.06-1"
    ANACONDA_URL="https://repo.anaconda.com/archive/Anaconda3-${ANACONDA_VERSION}-Linux-x86_64.sh"
    if ! wget -q --show-progress "$ANACONDA_URL" -O /tmp/anaconda_installer.sh; then
        echo "ERROR: Failed to download Anaconda!"
        exit 1
    fi
fi

echo "Download completed ($(du -h /tmp/anaconda_installer.sh | cut -f1))"

# Install Anaconda silently for user 'ga'
echo "Installing Anaconda for user ga..."
# Run the installer as root but install into ga's home directory
bash /tmp/anaconda_installer.sh -b -p /home/ga/anaconda3

# Set ownership
chown -R ga:ga /home/ga/anaconda3

# Remove installer
rm -f /tmp/anaconda_installer.sh

# Verify installation
if [ -f /home/ga/anaconda3/bin/conda ]; then
    echo "Anaconda installed at /home/ga/anaconda3"
    /home/ga/anaconda3/bin/conda --version
else
    echo "ERROR: Anaconda installation failed!"
    exit 1
fi

# Initialize conda for user ga
su - ga -c "/home/ga/anaconda3/bin/conda init bash"

# Configure conda settings
su - ga -c "/home/ga/anaconda3/bin/conda config --set auto_activate_base true"
su - ga -c "/home/ga/anaconda3/bin/conda config --set report_errors false"

# Update Navigator to latest (if needed)
echo "Checking Anaconda Navigator..."
su - ga -c "/home/ga/anaconda3/bin/conda list anaconda-navigator" || true

# Copy real-world datasets to ga's home directory
echo "Setting up data directory..."
mkdir -p /home/ga/datasets
cp /workspace/data/winequality-red.csv /home/ga/datasets/
cp /workspace/data/iris.csv /home/ga/datasets/
chown -R ga:ga /home/ga/datasets

# Fix conda_token import compatibility issue
# Navigator 2.6.x expects 'conda_token' as top-level module but conda-token 0.7.x
# moved it to 'anaconda_auth._conda.conda_token'. Create a compatibility shim.
echo "Fixing conda_token import compatibility..."
SITE_PKGS="/home/ga/anaconda3/lib/python3.12/site-packages"
if [ ! -d "$SITE_PKGS/conda_token" ] && [ -f "$SITE_PKGS/anaconda_auth/_conda/conda_token.py" ]; then
    mkdir -p "$SITE_PKGS/conda_token"
    cat > "$SITE_PKGS/conda_token/__init__.py" << 'SHIMEOF'
# Compatibility shim: conda-token 0.7.x moved to anaconda_auth._conda.conda_token
from anaconda_auth._conda.conda_token import *
from anaconda_auth._conda.conda_token import repo_config
SHIMEOF
    # Create repo_config submodule shim that re-exports ALL attributes
    cat > "$SITE_PKGS/conda_token/repo_config.py" << 'SHIMEOF'
# Compatibility shim - dynamically re-export all from real repo_config
from anaconda_auth._conda.conda_token import repo_config as _real
_g = globals()
for _name in dir(_real):
    if not _name.startswith("__"):
        _g[_name] = getattr(_real, _name)
SHIMEOF
    chown -R ga:ga "$SITE_PKGS/conda_token"
    echo "conda_token shim created"
else
    echo "conda_token shim not needed or already exists"
fi

# Fix Mesa OpenGL driver path for Qt Quick rendering
mkdir -p /usr/lib/dri
ln -sf /usr/lib/x86_64-linux-gnu/dri/swrast_dri.so /usr/lib/dri/swrast_dri.so 2>/dev/null || true

# Fix libstdc++ conflict: Anaconda bundles an old libstdc++ that lacks GLIBCXX_3.4.30
# required by system Mesa. Replace with system version.
if [ -f /home/ga/anaconda3/lib/libstdc++.so.6 ] && [ -f /usr/lib/x86_64-linux-gnu/libstdc++.so.6 ]; then
    rm -f /home/ga/anaconda3/lib/libstdc++.so.6
    ln -s /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /home/ga/anaconda3/lib/libstdc++.so.6
    echo "Fixed libstdc++ symlink for Mesa compatibility"
fi

# Launch Navigator once briefly to create config files, then kill it
echo "Creating Navigator config..."
su - ga -c "DISPLAY=:1 timeout 30 /home/ga/anaconda3/bin/anaconda-navigator" 2>/dev/null &
sleep 20
pkill -f anaconda-navigator 2>/dev/null || true
sleep 2

# Suppress update/first-run dialogs
if [ -f /home/ga/.anaconda/navigator/anaconda-navigator.ini ]; then
    sed -i 's/hide_update_dialog = False/hide_update_dialog = True/' /home/ga/.anaconda/navigator/anaconda-navigator.ini
    sed -i 's/hide_whats_new_dialog = False/hide_whats_new_dialog = True/' /home/ga/.anaconda/navigator/anaconda-navigator.ini
    echo "Navigator dialog suppression configured"
fi

# Patch Navigator to support GA_NAV_DEFAULT_TAB environment variable
# This allows setup scripts to set the initial tab via env var
echo "Patching Navigator for tab switching support..."
NAVIGATOR_MAIN="/home/ga/anaconda3/lib/python3.12/site-packages/anaconda_navigator/widgets/main_window/__init__.py"
if [ -f "$NAVIGATOR_MAIN" ]; then
    # Add env var check after all_tab_widgets.extend() in setup_tabs()
    python3 -c "
import re
with open('$NAVIGATOR_MAIN', 'r') as f:
    content = f.read()

# Find the insertion point: after 'self.all_tab_widgets.extend' block
marker = '''        self.all_tab_widgets.extend((
            self.tab_home,
            self.tab_community,
            self.tab_learning,
        ))'''

patch = '''

        # GA Patch: switch tab on startup (env var) and monitor file trigger
        import os as _os
        _default_tab = _os.environ.get('GA_NAV_DEFAULT_TAB', '').lower()
        if _default_tab:
            for _i, _btn in enumerate(self.tab_stack.tabbar.buttons):
                if _btn.text().lower() == _default_tab:
                    self.tab_stack.setCurrentIndex(_i)
                    break

        # File trigger: check /tmp/ga_switch_tab periodically
        from qtpy.QtCore import QTimer as _QTimer
        def _ga_check_tab_switch():
            try:
                if _os.path.exists('/tmp/ga_switch_tab'):
                    with open('/tmp/ga_switch_tab') as _f:
                        _tab = _f.read().strip().lower()
                    _os.remove('/tmp/ga_switch_tab')
                    for _i, _btn in enumerate(self.tab_stack.tabbar.buttons):
                        if _btn.text().lower() == _tab:
                            self.tab_stack.setCurrentIndex(_i)
                            break
            except Exception:
                pass
        self._ga_timer = _QTimer(self)
        self._ga_timer.timeout.connect(_ga_check_tab_switch)
        self._ga_timer.start(1000)'''

if marker in content and 'GA_NAV_DEFAULT_TAB' not in content:
    content = content.replace(marker, marker + patch)
    with open('$NAVIGATOR_MAIN', 'w') as f:
        f.write(content)
    print('Navigator patched successfully')
else:
    if 'GA_NAV_DEFAULT_TAB' in content:
        print('Navigator already patched')
    else:
        print('WARNING: Could not find insertion point for Navigator patch')
"
    # Remove compiled bytecode so patch takes effect
    find /home/ga/anaconda3/lib/python3.12/site-packages/anaconda_navigator/widgets/main_window/ -name '*.pyc' -delete 2>/dev/null || true
fi

# Clean up apt cache
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Anaconda installation complete ==="
