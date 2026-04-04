#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Setting up Shared Custody Volume Task ==="

# 1. Cleanup previous runs
rm -f /home/ga/Volumes/root_ca_storage.hc 2>/dev/null || true
veracrypt --text --dismount --non-interactive 2>/dev/null || true

# 2. Prepare the Token Files
TOKEN_DIR="/home/ga/Documents/OfficerTokens"
mkdir -p "$TOKEN_DIR"

# Source real data from assets if available, otherwise create realistic dummies
ASSETS_DIR="/workspace/assets/sample_data"

# CEO Token (SSH Key style)
if [ -f "$ASSETS_DIR/backup_authorized_keys" ]; then
    cp "$ASSETS_DIR/backup_authorized_keys" "$TOKEN_DIR/CEO_Token_Keys.pub"
else
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC+..." > "$TOKEN_DIR/CEO_Token_Keys.pub"
fi

# CFO Token (CSV Data)
if [ -f "$ASSETS_DIR/FY2024_Revenue_Budget.csv" ]; then
    cp "$ASSETS_DIR/FY2024_Revenue_Budget.csv" "$TOKEN_DIR/CFO_Token_Budget.csv"
else
    echo "Date,Revenue,Department" > "$TOKEN_DIR/CFO_Token_Budget.csv"
    echo "2024-01-01,50000,Finance" >> "$TOKEN_DIR/CFO_Token_Budget.csv"
fi

# Legal Token (Text document)
if [ -f "$ASSETS_DIR/SF312_Nondisclosure_Agreement.txt" ]; then
    cp "$ASSETS_DIR/SF312_Nondisclosure_Agreement.txt" "$TOKEN_DIR/Legal_Token_NDA.txt"
else
    echo "NON-DISCLOSURE AGREEMENT" > "$TOKEN_DIR/Legal_Token_NDA.txt"
    echo "This agreement is made between..." >> "$TOKEN_DIR/Legal_Token_NDA.txt"
fi

# Set permissions
chown -R ga:ga "$TOKEN_DIR"
chmod 644 "$TOKEN_DIR"/*

# 3. Start VeraCrypt
if ! is_veracrypt_running; then
    echo "Starting VeraCrypt..."
    su - ga -c "DISPLAY=:1 veracrypt &"
    sleep 3
fi

if ! wait_for_window "VeraCrypt" 15; then
    echo "WARNING: VeraCrypt window may not be visible"
fi

# 4. Focus Window
wid=$(get_veracrypt_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
fi

# 5. Record start time
date +%s > /tmp/task_start_time.txt
ls -la "$TOKEN_DIR" > /tmp/initial_tokens.txt

take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="