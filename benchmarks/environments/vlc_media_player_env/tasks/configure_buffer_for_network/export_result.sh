#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Buffer Configuration Result ==="

OUTPUT_DIR="/tmp/task_output_buffer_config"
mkdir -p "$OUTPUT_DIR"

VLC_RC="/home/ga/.config/vlc/vlcrc"
LOG_FILE="/tmp/vlc_buffer_export.log"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting export process..."

# Close VLC to ensure config is written
if is_vlc_running; then
    log "VLC is running, closing to flush configuration..."
    wid=$(get_vlc_window_id)
    if [ -n "$wid" ]; then
        focus_window "$wid" || true
    fi
    
    # Close gracefully
    safe_xdotool ga :1 key --delay 200 ctrl+q || true
    sleep 2
    
    # Force kill if still running
    if is_vlc_running; then
        log "Force closing VLC..."
        kill_vlc ga || true
        sleep 1
    fi
    
    log "VLC closed"
fi

# Export VLC configuration file
if [ -f "$VLC_RC" ]; then
    cp "$VLC_RC" "$OUTPUT_DIR/vlcrc"
    log "✅ Exported vlcrc"
    
    # Extract cache settings for quick inspection
    log "Extracting cache settings..."
    grep -E "^(file-caching|network-caching|disc-caching|live-caching)" "$VLC_RC" > "$OUTPUT_DIR/cache_settings.txt" 2>/dev/null || echo "# No cache settings found" > "$OUTPUT_DIR/cache_settings.txt"
    
    # Get file-caching value specifically
    if grep -q "^file-caching=" "$VLC_RC"; then
        FILE_CACHE=$(grep "^file-caching=" "$VLC_RC" | cut -d= -f2)
        log "file-caching value: ${FILE_CACHE}ms"
        echo "$FILE_CACHE" > "$OUTPUT_DIR/file_caching_value.txt"
    else
        log "WARNING: file-caching not found in config (using default 300)"
        echo "300" > "$OUTPUT_DIR/file_caching_value.txt"
    fi
    
    # Copy full cache settings
    cat "$OUTPUT_DIR/cache_settings.txt"
    
else
    log "ERROR: VLC config file not found at $VLC_RC"
    echo "ERROR: Config file missing" > "$OUTPUT_DIR/error.txt"
fi

# Create summary
cat > "$OUTPUT_DIR/summary.txt" << EOF
Buffer Configuration Task Export
Generated: $(date)

Config file: $([ -f "$VLC_RC" ] && echo "Found" || echo "Missing")
EOF

if [ -f "$OUTPUT_DIR/file_caching_value.txt" ]; then
    CACHE_VAL=$(cat "$OUTPUT_DIR/file_caching_value.txt")
    echo "file-caching value: ${CACHE_VAL}ms" >> "$OUTPUT_DIR/summary.txt"
fi

# Copy to standard location for verifier
cp "$OUTPUT_DIR/vlcrc" /tmp/vlc_buffer_config.vlcrc 2>/dev/null || true
cp "$OUTPUT_DIR/cache_settings.txt" /tmp/vlc_cache_settings.txt 2>/dev/null || true

# Create completion marker
echo "$(date)" > /tmp/vlc_buffer_config_completed.txt
echo "Buffer configuration task completed" >> /tmp/vlc_buffer_config_completed.txt

log "Export complete: $OUTPUT_DIR"
log "Results also copied to /tmp/ for verification"

echo "=== Export Complete ==="