#!/bin/bash
# Setup script for Configure Email Settings task

echo "=== Setting up Configure Email Settings Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# List of options to track
OPTIONS=(
    "woocommerce_email_from_name"
    "woocommerce_email_from_address"
    "woocommerce_email_header_image"
    "woocommerce_email_footer_text"
    "woocommerce_email_base_color"
    "woocommerce_email_background_color"
    "woocommerce_email_body_background_color"
    "woocommerce_email_text_color"
)

# Record initial state of these options to detect changes later
echo "Recording initial email settings..."
JSON_CONTENT="{"
FIRST=true

for opt in "${OPTIONS[@]}"; do
    # Get current value from database
    VAL=$(wc_query "SELECT option_value FROM wp_options WHERE option_name='$opt' LIMIT 1" 2>/dev/null)
    
    # Escape for JSON
    VAL_ESC=$(json_escape "$VAL")
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        JSON_CONTENT="$JSON_CONTENT,"
    fi
    JSON_CONTENT="$JSON_CONTENT \"$opt\": \"$VAL_ESC\""
done
JSON_CONTENT="$JSON_CONTENT}"

echo "$JSON_CONTENT" > /tmp/initial_email_settings.json
echo "Initial settings recorded to /tmp/initial_email_settings.json"

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Navigate explicitly to the main Dashboard to ensure a clean start, 
# relying on the agent to navigate to Settings > Emails
# (We don't put them directly on the email page to test navigation)

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="