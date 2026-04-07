#!/bin/bash
set -e

echo "=== Setting up Activity Browser environment ==="

# Wait for desktop to be ready
sleep 5

export PATH="/opt/miniconda3/bin:$PATH"

# ============================================================
# Set up Brightway2 project with Energy_and_Materials database
# ============================================================
echo "=== Setting up Brightway2 project with Energy_and_Materials database ==="

# Fix Brightway3 data directory permissions (may have been created by root during install)
# Brightway3 uses both .local/share/Brightway3 and .cache/Brightway3
echo "Fixing home directory permissions for ga user..."
for dir in /home/ga/.local /home/ga/.cache /home/ga/.config; do
    mkdir -p "$dir"
    chown -R ga:ga "$dir"
done
# Ensure the entire home directory is owned by ga
chown ga:ga /home/ga

# Run the Python setup script to create project and set up database
# This must run as ga user since Brightway stores data per-user
su - ga -c "export PATH='/opt/miniconda3/bin:$PATH' && /opt/miniconda3/envs/ab/bin/python /workspace/scripts/setup_brightway_project.py" 2>&1 | tee /tmp/brightway_setup.log

# Verify the setup succeeded
if su - ga -c "export PATH='/opt/miniconda3/bin:$PATH' && /opt/miniconda3/envs/ab/bin/python -c \"
import brightway2 as bw
bw.projects.set_current('default')
print('Databases:', list(bw.databases))
print('Methods:', len(bw.methods))
\"" 2>/dev/null; then
    echo "Brightway2 project setup verified successfully"
else
    echo "WARNING: Brightway2 project verification returned non-zero"
fi

# ============================================================
# Create user workspace directories
# ============================================================
mkdir -p /home/ga/Documents/ActivityBrowser
mkdir -p /home/ga/Documents/ActivityBrowser/exports
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Documents/ActivityBrowser

# ============================================================
# Create Activity Browser launcher script
# ============================================================
cat > /usr/local/bin/launch-activity-browser << 'EOF'
#!/bin/bash
export DISPLAY=:1
export PATH="/opt/miniconda3/envs/ab/bin:/opt/miniconda3/bin:$PATH"
export QT_QPA_PLATFORM=xcb
export LIBGL_ALWAYS_SOFTWARE=1
export XDG_SESSION_TYPE=x11
# Ensure conda env libraries are found before system libs (fixes lxml/libxslt conflict)
export LD_LIBRARY_PATH="/opt/miniconda3/envs/ab/lib:${LD_LIBRARY_PATH}"
# Set XDG_RUNTIME_DIR to suppress warning
export XDG_RUNTIME_DIR="/tmp/runtime-$(whoami)"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

# Activate conda environment and launch
source /opt/miniconda3/etc/profile.d/conda.sh
conda activate ab
activity-browser "$@"
EOF
chmod +x /usr/local/bin/launch-activity-browser

# Create desktop shortcut
cat > /home/ga/Desktop/activity-browser.desktop << 'DESKTOP'
[Desktop Entry]
Type=Application
Name=Activity Browser
Comment=Life Cycle Assessment GUI for Brightway2
Exec=/usr/local/bin/launch-activity-browser
Terminal=false
Categories=Science;Engineering;
DESKTOP
chmod +x /home/ga/Desktop/activity-browser.desktop
chown ga:ga /home/ga/Desktop/activity-browser.desktop

# ============================================================
# Configure Activity Browser settings to suppress first-run dialogs
# ============================================================
AB_CONFIG_DIR="/home/ga/.config/ActivityBrowser"
mkdir -p "$AB_CONFIG_DIR"

# Pre-create AB settings to set default project and suppress update checks
cat > "$AB_CONFIG_DIR/ABsettings.json" << 'SETTINGS'
{
    "custom_bw_dir": "",
    "startup_project": "default",
    "theme": "default"
}
SETTINGS

chown -R ga:ga "$AB_CONFIG_DIR"

# ============================================================
# Warm-up launch to clear first-run state
# ============================================================
echo "=== Performing warm-up launch of Activity Browser ==="
su - ga -c "setsid /usr/local/bin/launch-activity-browser > /tmp/ab_warmup.log 2>&1 &"

# Wait for Activity Browser window to appear (Qt app, ~10-20s)
for i in $(seq 1 40); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -i -E "activity.browser|brightway" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Activity Browser window detected after ${i}s: ${WID}"
        break
    fi
    sleep 1
done

# Give it time for any first-run dialogs
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
sleep 2

# Close after warm-up
pkill -f "activity-browser" 2>/dev/null || true
pkill -f "activity.browser" 2>/dev/null || true
sleep 3

# Re-set the current project to default after warm-up
# (warm-up may have switched to "default" project)
echo "Re-setting current project to default..."
su - ga -c "export PATH='/opt/miniconda3/bin:\$PATH' && export LD_LIBRARY_PATH='/opt/miniconda3/envs/ab/lib:\$LD_LIBRARY_PATH' && /opt/miniconda3/envs/ab/bin/python -c \"
import brightway2 as bw
bw.projects.set_current('default')
print('Current project set to:', bw.projects.current)
print('Databases:', list(bw.databases))
\"" 2>&1 || echo "WARNING: Failed to set project"

echo "=== Activity Browser warm-up complete ==="
echo "=== Activity Browser environment setup complete ==="
