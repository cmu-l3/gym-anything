#!/bin/bash
# export_result.sh for tor_support_diagnostics_bundle task
# Analyzes the created zip archive and extracts results for verification

echo "=== Exporting tor_support_diagnostics_bundle results ==="

TASK_NAME="tor_support_diagnostics_bundle"
ZIP_PATH="/home/ga/Documents/tor_diagnostics.zip"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Initialize variables
ZIP_EXISTS="false"
ZIP_IS_NEW="false"
ABOUT_EXISTS="false"
ABOUT_SIZE=0
ABOUT_VALID="false"
LOGS_EXISTS="false"
LOGS_SIZE=0
LOGS_VALID="false"
BOOT_EXISTS="false"
BOOT_LINES=0
BOOT_VALID="false"

# Check the zip archive
if [ -f "$ZIP_PATH" ]; then
    ZIP_EXISTS="true"
    MTIME=$(stat -c %Y "$ZIP_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        ZIP_IS_NEW="true"
    fi
    
    # Extract to a temporary directory for analysis
    EVAL_DIR="/tmp/diag_eval_$$"
    mkdir -p "$EVAL_DIR"
    
    # Safely extract
    if unzip -q "$ZIP_PATH" -d "$EVAL_DIR" 2>/dev/null; then
        echo "Zip successfully extracted to $EVAL_DIR"
        
        # Check about_support.txt
        # (Using find to handle potential nested directories inside the zip)
        ABOUT_FILE=$(find "$EVAL_DIR" -name "about_support.txt" | head -1)
        if [ -n "$ABOUT_FILE" ] && [ -f "$ABOUT_FILE" ]; then
            ABOUT_EXISTS="true"
            ABOUT_SIZE=$(stat -c %s "$ABOUT_FILE")
            if grep -qi "Application Basics\|Profile Folder\|Tor Browser" "$ABOUT_FILE" 2>/dev/null; then
                ABOUT_VALID="true"
            fi
        fi
        
        # Check tor_logs.txt
        LOGS_FILE=$(find "$EVAL_DIR" -name "tor_logs.txt" | head -1)
        if [ -n "$LOGS_FILE" ] && [ -f "$LOGS_FILE" ]; then
            LOGS_EXISTS="true"
            LOGS_SIZE=$(stat -c %s "$LOGS_FILE")
            if grep -q "\[NOTICE\]" "$LOGS_FILE" 2>/dev/null; then
                LOGS_VALID="true"
            fi
        fi
        
        # Check bootstrap_phases.txt
        BOOT_FILE=$(find "$EVAL_DIR" -name "bootstrap_phases.txt" | head -1)
        if [ -n "$BOOT_FILE" ] && [ -f "$BOOT_FILE" ]; then
            BOOT_EXISTS="true"
            BOOT_LINES=$(grep -c '[^[:space:]]' "$BOOT_FILE" 2>/dev/null || echo "0")
            
            # Count lines that DO NOT contain "Bootstrapped"
            NON_MATCHING=$(grep -v "Bootstrapped" "$BOOT_FILE" | grep -c '[^[:space:]]' 2>/dev/null || echo "0")
            
            if [ "$BOOT_LINES" -ge 2 ] && [ "$NON_MATCHING" -eq 0 ]; then
                BOOT_VALID="true"
            fi
        fi
    else
        echo "Failed to extract zip file. It may be corrupt or not a valid zip."
    fi
    
    # Cleanup
    rm -rf "$EVAL_DIR"
fi

# Create result JSON
cat > /tmp/${TASK_NAME}_result.json << EOF
{
    "zip_exists": $ZIP_EXISTS,
    "zip_is_new": $ZIP_IS_NEW,
    "about_exists": $ABOUT_EXISTS,
    "about_size": $ABOUT_SIZE,
    "about_valid": $ABOUT_VALID,
    "logs_exists": $LOGS_EXISTS,
    "logs_size": $LOGS_SIZE,
    "logs_valid": $LOGS_VALID,
    "boot_exists": $BOOT_EXISTS,
    "boot_lines": $BOOT_LINES,
    "boot_valid": $BOOT_VALID,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/${TASK_NAME}_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json