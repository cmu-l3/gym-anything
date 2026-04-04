#!/bin/bash
echo "=== Setting up generate_adaptive_icons task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Prepare Project
# We'll use the SunflowerApp as a base but rename it to SummitApp for the scenario
DATA_SOURCE="/workspace/data/SunflowerApp"
PROJECT_DIR="/home/ga/AndroidStudioProjects/SummitApp"

echo "Cleaning up previous run..."
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -rf /home/ga/Documents/branding 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

echo "Creating SummitApp project..."
mkdir -p /home/ga/AndroidStudioProjects
if [ -d "$DATA_SOURCE" ]; then
    cp -r "$DATA_SOURCE" "$PROJECT_DIR"
else
    # Fallback if data source missing (should not happen in this env, but good for robustness)
    echo "WARNING: Data source not found, creating empty structure"
    mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26"
    mkdir -p "$PROJECT_DIR/app/src/main/res/values"
fi

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# 2. Create Branding Assets
echo "Creating branding assets..."
mkdir -p /home/ga/Documents/branding
cat > /home/ga/Documents/branding/summit_logo.svg << 'EOF'
<svg width="512" height="512" viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg">
  <circle cx="256" cy="256" r="256" fill="none"/>
  <path d="M256 50 L50 462 H462 Z" fill="#FFC107" stroke="#333" stroke-width="10"/>
  <path d="M256 150 L120 420 H392 Z" fill="#FF5722"/>
  <rect x="230" y="300" width="52" height="120" fill="#795548"/>
</svg>
EOF
chown -R ga:ga /home/ga/Documents/branding

# 3. Record initial state of icon files (to detect updates)
# We track the modification time of the primary adaptive icon file
ICON_XML="$PROJECT_DIR/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"
if [ -f "$ICON_XML" ]; then
    stat -c %Y "$ICON_XML" > /tmp/initial_icon_mtime.txt
else
    echo "0" > /tmp/initial_icon_mtime.txt
fi

# 4. Open Android Studio
setup_android_studio_project "$PROJECT_DIR" "SummitApp" 180

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="