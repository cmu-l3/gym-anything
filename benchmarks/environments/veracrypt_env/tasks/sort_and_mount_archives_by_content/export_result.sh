#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Sort and Mount Result ==="

# 1. Get VeraCrypt List Output
# Expected format lines like: "11: /home/ga/Volumes/archive_X.hc /media/veracrypt11"
VC_LIST=$(veracrypt --text --list --non-interactive 2>&1 || echo "")
echo "$VC_LIST" > /tmp/vc_list_output.txt

# 2. Check Slot 11
SLOT11_MOUNTED="false"
SLOT11_CONTENT="unknown"
SLOT11_PATH=""

# Check if line starting with "11:" exists
if echo "$VC_LIST" | grep -q "^11:"; then
    SLOT11_MOUNTED="true"
    # Extract mount point (usually 3rd column, but handle spaces carefully)
    # Standard output: Slot: Volume MountPoint
    SLOT11_PATH=$(echo "$VC_LIST" | grep "^11:" | awk '{print $3}')
    
    # If path is empty, try default
    if [ -z "$SLOT11_PATH" ]; then SLOT11_PATH="/media/veracrypt11"; fi
    
    if [ -d "$SLOT11_PATH" ]; then
        if [ -f "$SLOT11_PATH/financial_records.csv" ]; then
            SLOT11_CONTENT="financial"
        elif [ -f "$SLOT11_PATH/legal_contract.txt" ]; then
            SLOT11_CONTENT="legal"
        elif [ -f "$SLOT11_PATH/obsolete_notes.txt" ]; then
            SLOT11_CONTENT="obsolete"
        else
            SLOT11_CONTENT="empty_or_other"
        fi
    else
        SLOT11_CONTENT="mount_point_missing"
    fi
fi

# 3. Check Slot 22
SLOT22_MOUNTED="false"
SLOT22_CONTENT="unknown"
SLOT22_PATH=""

if echo "$VC_LIST" | grep -q "^22:"; then
    SLOT22_MOUNTED="true"
    SLOT22_PATH=$(echo "$VC_LIST" | grep "^22:" | awk '{print $3}')
    
    if [ -z "$SLOT22_PATH" ]; then SLOT22_PATH="/media/veracrypt22"; fi
    
    if [ -d "$SLOT22_PATH" ]; then
        if [ -f "$SLOT22_PATH/financial_records.csv" ]; then
            SLOT22_CONTENT="financial"
        elif [ -f "$SLOT22_PATH/legal_contract.txt" ]; then
            SLOT22_CONTENT="legal"
        elif [ -f "$SLOT22_PATH/obsolete_notes.txt" ]; then
            SLOT22_CONTENT="obsolete"
        else
            SLOT22_CONTENT="empty_or_other"
        fi
    else
        SLOT22_CONTENT="mount_point_missing"
    fi
fi

# 4. Count total mounted volumes
TOTAL_MOUNTED=$(echo "$VC_LIST" | grep -c "^[0-9]")

# 5. Take screenshot
take_screenshot /tmp/task_end.png

# 6. Create JSON
cat > /tmp/sort_mount_result.json << EOF
{
    "slot11_mounted": $SLOT11_MOUNTED,
    "slot11_content": "$SLOT11_CONTENT",
    "slot11_path": "$SLOT11_PATH",
    "slot22_mounted": $SLOT22_MOUNTED,
    "slot22_content": "$SLOT22_CONTENT",
    "slot22_path": "$SLOT22_PATH",
    "total_mounted_count": $TOTAL_MOUNTED,
    "vc_list_output": "$(echo "$VC_LIST" | sed 's/"/\\"/g' | tr '\n' ';')",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Secure copy
write_result_json "/tmp/task_result.json" "$(cat /tmp/sort_mount_result.json)"

echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="