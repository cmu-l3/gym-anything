#!/bin/bash
echo "=== Setting up Inbox Zero Workflow Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Thunderbird is closed before modifying prefs
close_thunderbird
sleep 2

# Profile path
PROFILE_DIR="/home/ga/.thunderbird/default-release"
PREFS_FILE="$PROFILE_DIR/prefs.js"

# We want to ensure defaults are explicitly set to the opposite of what the user is asked to do
# Remove any existing settings of these keys
sed -i '/mailnews.mark_message_read.auto/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mail.openMessageBehavior/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mail.close_message_window.on_delete/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mail.biff.show_alert/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mail.biff.play_sound/d' "$PREFS_FILE" 2>/dev/null || true
sed -i '/mail.server.server1.empty_trash_on_exit/d' "$PREFS_FILE" 2>/dev/null || true

# Append opposing defaults
cat >> "$PREFS_FILE" << 'EOF'
user_pref("mailnews.mark_message_read.auto", true);
user_pref("mail.openMessageBehavior", 2);
user_pref("mail.close_message_window.on_delete", false);
user_pref("mail.biff.show_alert", true);
user_pref("mail.biff.play_sound", true);
user_pref("mail.server.server1.empty_trash_on_exit", false);
EOF

# Make sure ownership is correct
chown -R ga:ga "$PROFILE_DIR"

# Record mtime of prefs.js before agent starts
stat -c %Y "$PREFS_FILE" > /tmp/initial_prefs_mtime.txt 2>/dev/null || echo "0" > /tmp/initial_prefs_mtime.txt

# Start Thunderbird
start_thunderbird
wait_for_thunderbird_window 30
sleep 3
maximize_thunderbird

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="