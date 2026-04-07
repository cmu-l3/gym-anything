#!/bin/bash
echo "=== Exporting tls_certificate_chain_extraction results ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CERT_PATH="/home/ga/Documents/target_cert_chain.pem"
SCREENSHOT_PATH="/home/ga/Documents/cert_viewer_screenshot.png"

# Take final environment screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# Check Cert File
CERT_EXISTS="false"
CERT_IS_NEW="false"
CERT_SIZE=0

if [ -f "$CERT_PATH" ]; then
    CERT_EXISTS="true"
    CERT_MTIME=$(stat -c %Y "$CERT_PATH" 2>/dev/null || echo "0")
    if [ "$CERT_MTIME" -gt "$TASK_START" ]; then
        CERT_IS_NEW="true"
    fi
    CERT_SIZE=$(stat -c %s "$CERT_PATH" 2>/dev/null || echo "0")
    
    # Copy to tmp so copy_from_env can access it without permission issues
    cp "$CERT_PATH" /tmp/target_cert_chain.pem 2>/dev/null || true
    chmod 666 /tmp/target_cert_chain.pem 2>/dev/null || true
fi

# Check Screenshot File
SCREENSHOT_EXISTS="false"
SCREENSHOT_IS_NEW="false"
SCREENSHOT_SIZE=0

if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_IS_NEW="true"
    fi
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    # Copy to tmp so copy_from_env can access it without permission issues
    cp "$SCREENSHOT_PATH" /tmp/cert_viewer_screenshot.png 2>/dev/null || true
    chmod 666 /tmp/cert_viewer_screenshot.png 2>/dev/null || true
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "cert_exists": $CERT_EXISTS,
    "cert_is_new": $CERT_IS_NEW,
    "cert_size": $CERT_SIZE,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_is_new": $SCREENSHOT_IS_NEW,
    "screenshot_size": $SCREENSHOT_SIZE,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="