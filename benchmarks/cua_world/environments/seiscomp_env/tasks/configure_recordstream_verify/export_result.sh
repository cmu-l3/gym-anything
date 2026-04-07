#!/bin/bash
echo "=== Exporting configure_recordstream_verify result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
GLOBAL_CFG="/home/ga/seiscomp/etc/global.cfg"
INV_FILE="/home/ga/inventory_listing.txt"
WAVE_FILE="/home/ga/extracted_waveforms.mseed"

# 1. Check global.cfg modifications
RS_LINE=$(grep -i "^recordstream" "$GLOBAL_CFG" 2>/dev/null | head -1 || echo "")
CFG_PRESERVED="false"
if grep -q "^database" "$GLOBAL_CFG" 2>/dev/null && grep -q "^plugins" "$GLOBAL_CFG" 2>/dev/null; then
    CFG_PRESERVED="true"
fi
CFG_MTIME=$(stat -c %Y "$GLOBAL_CFG" 2>/dev/null || echo "0")

# 2. Check inventory listing output
INV_EXISTS="false"
INV_SIZE=0
INV_MTIME=0
STATIONS_FOUND=0

if [ -f "$INV_FILE" ]; then
    INV_EXISTS="true"
    INV_SIZE=$(stat -c %s "$INV_FILE" 2>/dev/null || echo "0")
    INV_MTIME=$(stat -c %Y "$INV_FILE" 2>/dev/null || echo "0")
    
    # Count how many of the expected stations were found
    for STA in TOLI GSI KWP SANI BKB; do
        if grep -qi "$STA" "$INV_FILE"; then
            STATIONS_FOUND=$((STATIONS_FOUND + 1))
        fi
    done
fi

# 3. Check waveform extraction output
WAVE_EXISTS="false"
WAVE_SIZE=0
WAVE_MTIME=0
QUALITY_BYTE=""
GE_FOUND="false"

if [ -f "$WAVE_FILE" ]; then
    WAVE_EXISTS="true"
    WAVE_SIZE=$(stat -c %s "$WAVE_FILE" 2>/dev/null || echo "0")
    WAVE_MTIME=$(stat -c %Y "$WAVE_FILE" 2>/dev/null || echo "0")
    
    # Check miniSEED headers (byte offset 6 usually contains D, R, Q, M for data quality)
    if [ "$WAVE_SIZE" -gt 48 ]; then
        QUALITY_BYTE=$(dd if="$WAVE_FILE" bs=1 skip=6 count=1 2>/dev/null | od -A n -c | tr -d ' ' | tr -d '\n' | grep -o '[a-zA-Z]' || echo "")
    fi
    
    # Look for GE network string in binary data
    if strings "$WAVE_FILE" 2>/dev/null | grep -q "GE"; then
        GE_FOUND="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 4. Generate JSON report using jq safely
jq -n \
  --arg ts "$TASK_START" \
  --arg rs_line "$RS_LINE" \
  --argjson cfg_preserved "$CFG_PRESERVED" \
  --arg cfg_mtime "$CFG_MTIME" \
  --argjson inv_exists "$INV_EXISTS" \
  --arg inv_size "$INV_SIZE" \
  --arg inv_mtime "$INV_MTIME" \
  --arg st_found "$STATIONS_FOUND" \
  --argjson wave_exists "$WAVE_EXISTS" \
  --arg wave_size "$WAVE_SIZE" \
  --arg wave_mtime "$WAVE_MTIME" \
  --arg q_byte "$QUALITY_BYTE" \
  --argjson ge_found "$GE_FOUND" \
  '{
    task_start: ($ts|tonumber),
    recordstream_line: $rs_line,
    cfg_preserved: $cfg_preserved,
    cfg_mtime: ($cfg_mtime|tonumber),
    inv_exists: $inv_exists,
    inv_size: ($inv_size|tonumber),
    inv_mtime: ($inv_mtime|tonumber),
    stations_found: ($st_found|tonumber),
    wave_exists: $wave_exists,
    wave_size: ($wave_size|tonumber),
    wave_mtime: ($wave_mtime|tonumber),
    quality_byte: $q_byte,
    ge_found: $ge_found
  }' > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="