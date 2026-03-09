#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Stream to TV Result ==="

# Get local IP
LOCAL_IP=$(hostname -I | awk '{print $1}' || echo "unknown")
echo "Local IP: $LOCAL_IP"

# Check if stream_url.txt exists
STREAM_URL_FILE="/home/ga/stream_url.txt"
if [ -f "$STREAM_URL_FILE" ]; then
    echo "✅ Stream URL file found"
    cp "$STREAM_URL_FILE" /tmp/vlc_stream_url.txt
    cat "$STREAM_URL_FILE"
else
    echo "⚠️ Stream URL file not found"
    # Create empty file so verifier doesn't fail on copy
    echo "" > /tmp/vlc_stream_url.txt
fi

# Capture VLC process information
echo "Capturing VLC process information..."
ps aux | grep -E "[v]lc|[c]vlc" > /tmp/vlc_stream_process.txt || echo "No VLC process" > /tmp/vlc_stream_process.txt
cat /tmp/vlc_stream_process.txt

# Capture network port information
echo "Capturing port 8080 status..."
ss -tlnp 2>/dev/null | grep -E ":8080|State" > /tmp/vlc_stream_port.txt || echo "Port 8080 not listening" > /tmp/vlc_stream_port.txt
netstat -tlnp 2>/dev/null | grep ":8080" >> /tmp/vlc_stream_port.txt || true
lsof -i :8080 2>/dev/null >> /tmp/vlc_stream_port.txt || true
cat /tmp/vlc_stream_port.txt

# Test if stream is accessible
STREAM_ACCESSIBLE="false"
STREAM_CONTENT_SIZE=0

if [ -n "$LOCAL_IP" ] && [ "$LOCAL_IP" != "unknown" ]; then
    STREAM_URL="http://${LOCAL_IP}:8080/"
    echo "Testing stream accessibility: $STREAM_URL"
    
    # Try to download first 100KB with timeout
    if timeout 10 curl -s -r 0-102400 "$STREAM_URL" -o /tmp/vlc_stream_test_chunk.bin 2>/dev/null; then
        if [ -f /tmp/vlc_stream_test_chunk.bin ]; then
            STREAM_CONTENT_SIZE=$(stat -c%s /tmp/vlc_stream_test_chunk.bin 2>/dev/null || echo 0)
            if [ "$STREAM_CONTENT_SIZE" -gt 1000 ]; then
                STREAM_ACCESSIBLE="true"
                echo "✅ Stream accessible, downloaded ${STREAM_CONTENT_SIZE} bytes"
                
                # Save the chunk for verification
                cp /tmp/vlc_stream_test_chunk.bin /tmp/vlc_stream_content_sample.bin
            else
                echo "⚠️ Stream responded but content too small: ${STREAM_CONTENT_SIZE} bytes"
            fi
        fi
    else
        echo "⚠️ Stream not accessible or timeout"
    fi
    
    # Also try HEAD request to get headers
    timeout 5 curl -I "$STREAM_URL" > /tmp/vlc_stream_headers.txt 2>&1 || echo "Could not get headers" > /tmp/vlc_stream_headers.txt
    cat /tmp/vlc_stream_headers.txt
else
    echo "⚠️ Could not determine local IP"
    echo "Could not determine IP" > /tmp/vlc_stream_headers.txt
fi

# Create result JSON
cat > /tmp/vlc_stream_result.json <<EOF
{
    "stream_url_file_exists": $([ -f "$STREAM_URL_FILE" ] && echo "true" || echo "false"),
    "stream_accessible": $STREAM_ACCESSIBLE,
    "stream_content_size": $STREAM_CONTENT_SIZE,
    "local_ip": "$LOCAL_IP",
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "✅ Stream result saved"
cat /tmp/vlc_stream_result.json

# Create completion marker
echo "$(date)" > /tmp/vlc_stream_completed.txt
echo "Stream to TV task export completed" >> /tmp/vlc_stream_completed.txt
echo "Stream accessible: $STREAM_ACCESSIBLE" >> /tmp/vlc_stream_completed.txt

# Don't kill VLC yet - let verifier check it's running
# The verifier will handle cleanup if needed

echo "=== Export Complete ==="
echo "Note: VLC left running for verification. Will be cleaned up by environment."