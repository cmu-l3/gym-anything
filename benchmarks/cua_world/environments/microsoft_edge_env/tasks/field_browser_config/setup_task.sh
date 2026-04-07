#!/bin/bash
# setup_task.sh - Setup for Field Browser Config task
set -e

echo "=== Setting up Field Browser Config Task ==="

# 1. Record start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Clean up any previous run artifacts
echo "Cleaning up previous artifacts..."
rm -rf "/home/ga/Documents/FieldData"
rm -f "/home/ga/Desktop/field_config_summary.txt"

# 3. Reset Edge to a known base state
# We kill any running instances first
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
sleep 1

# Ensure the config directory exists
CONFIG_DIR="/home/ga/.config/microsoft-edge/Default"
mkdir -p "$CONFIG_DIR"

# Reset Preferences to a clean state (ensuring we don't start with the target config)
# We use a minimal valid Preferences JSON
cat > "$CONFIG_DIR/Preferences" << 'EOF'
{
  "browser": {
    "show_home_button": false,
    "check_default_browser": false
  },
  "session": {
    "restore_on_startup": 5
  },
  "download": {
    "default_directory": "/home/ga/Downloads",
    "prompt_for_download": false
  },
  "bookmark_bar": {
    "show_on_all_tabs": true
  },
  "distribution": {
    "skip_first_run_ui": true,
    "suppress_first_run_bubble": true
  }
}
EOF
chown -R ga:ga "/home/ga/.config/microsoft-edge"

# Reset Bookmarks to default (empty)
cat > "$CONFIG_DIR/Bookmarks" << 'EOF'
{
   "roots": {
      "bookmark_bar": {
         "children": [],
         "date_added": "0",
         "date_modified": "0",
         "id": "1",
         "name": "Favorites bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "0",
         "date_modified": "0",
         "id": "2",
         "name": "Other favorites",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "0",
         "date_modified": "0",
         "id": "3",
         "name": "Mobile favorites",
         "type": "folder"
      }
   },
   "version": 1
}
EOF
chown ga:ga "$CONFIG_DIR/Bookmarks"

# 4. Launch Microsoft Edge
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge_launch.log 2>&1 &"

# Wait for Edge window
echo "Waiting for Edge window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -iE "edge|microsoft"; then
        echo "Edge window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="