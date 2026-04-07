#!/bin/bash
# Setup script for configure_library_site task
echo "=== Setting up library site configuration task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt
chmod 666 /tmp/task_start_time.txt

WP_DIR="/var/www/html/wordpress"
cd "$WP_DIR"

# Ensure wp-cli is available
source /workspace/scripts/task_utils.sh

# ============================================================
# 1. Prepare clean environment
# ============================================================
echo "Activating Twenty Twenty-One theme..."
wp theme install twentytwentyone --activate --allow-root 2>&1 || \
wp theme activate twentytwentyone --allow-root 2>&1 || true

echo "Resetting reading settings..."
wp option update show_on_front "posts" --allow-root 2>&1
wp option update page_on_front "0" --allow-root 2>&1
wp option update page_for_posts "0" --allow-root 2>&1

echo "Cleaning up existing menus..."
MENU_IDS=$(wp menu list --format=ids --allow-root 2>/dev/null || echo "")
if [ -n "$MENU_IDS" ]; then
    for mid in $MENU_IDS; do
        wp menu delete "$mid" --allow-root 2>&1 || true
    done
fi

echo "Removing any conflicting pages..."
for title in "Welcome to Greenfield Library" "Library News" "Catalog" "Digital Collections" "Events & Programs" "Events and Programs" "About Us"; do
    PAGE_IDS=$(wp post list --post_type=page --title="$title" --format=ids --allow-root 2>/dev/null || echo "")
    if [ -n "$PAGE_IDS" ]; then
        for pid in $PAGE_IDS; do
            wp post delete "$pid" --force --allow-root 2>&1 || true
        done
    fi
done

# ============================================================
# 2. Record initial baseline using Python/WP-CLI
# ============================================================
echo "Recording baseline state..."
python3 << 'EOF'
import subprocess
import json
import os

def run_wp(cmd):
    try:
        return subprocess.check_output(f"wp {cmd} --allow-root", shell=True, cwd="/var/www/html/wordpress").decode('utf-8').strip()
    except Exception as e:
        return ""

state = {}
try:
    pages = run_wp("post list --post_type=page --post_status=publish --format=json")
    state['pages'] = json.loads(pages) if pages else []
except:
    state['pages'] = []

state['show_on_front'] = run_wp("option get show_on_front")

with open('/tmp/initial_state.json', 'w') as f:
    json.dump(state, f)
EOF
chmod 666 /tmp/initial_state.json

# ============================================================
# 3. Launch UI
# ============================================================
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 8
fi

# Focus and maximize Firefox window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="