#!/bin/bash
# Export results for digital_billboard_legacy_compliance task
set -e

echo "=== Exporting DOOH Legacy Compliance results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create a temporary JSON to hold anti-gaming file metadata
TEMP_JSON=$(mktemp /tmp/dooh_metadata.XXXXXX.json)
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"files\": {" >> "$TEMP_JSON"

# Helper function to check file stats
check_file() {
    local filepath="$1"
    local name="$2"
    local is_last="$3"
    
    if [ -f "$filepath" ]; then
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        
        echo "    \"$name\": {\"exists\": true, \"size_bytes\": $size, \"mtime\": $mtime, \"created_during_task\": $created_during_task}" >> "$TEMP_JSON"
    else
        echo "    \"$name\": {\"exists\": false, \"size_bytes\": 0, \"mtime\": 0, \"created_during_task\": false}" >> "$TEMP_JSON"
    fi
    
    if [ "$is_last" != "true" ]; then
        echo "," >> "$TEMP_JSON"
    fi
}

check_file "/home/ga/Videos/dooh_delivery/highway_board.avi" "highway_board" "false"
check_file "/home/ga/Videos/dooh_delivery/subway_screen.mpg" "subway_screen" "false"
check_file "/home/ga/Videos/dooh_delivery/stadium_ribbon.mp4" "stadium_ribbon" "false"
check_file "/home/ga/Videos/dooh_delivery/proofs/highway_proof.png" "highway_proof" "false"
check_file "/home/ga/Videos/dooh_delivery/proofs/subway_proof.png" "subway_proof" "false"
check_file "/home/ga/Videos/dooh_delivery/proofs/stadium_proof.png" "stadium_proof" "false"
check_file "/home/ga/Documents/dooh_manifest.json" "manifest" "false"
check_file "/home/ga/Videos/client_master_promo.mp4" "master_promo" "true"

echo "  }" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Create export directory
mkdir -p /tmp/dooh_export
cp "$TEMP_JSON" /tmp/dooh_export/file_metadata.json

# Copy all generated files to the export directory
cp -r /home/ga/Videos/dooh_delivery/* /tmp/dooh_export/ 2>/dev/null || true
cp /home/ga/Documents/dooh_manifest.json /tmp/dooh_export/ 2>/dev/null || true
cp /home/ga/Videos/client_master_promo.mp4 /tmp/dooh_export/ 2>/dev/null || true
cp /tmp/task_final.png /tmp/dooh_export/ 2>/dev/null || true
cp /tmp/task_initial.png /tmp/dooh_export/ 2>/dev/null || true

# Kill VLC
pkill -u ga -f vlc || true

echo "Export complete for digital_billboard_legacy_compliance"