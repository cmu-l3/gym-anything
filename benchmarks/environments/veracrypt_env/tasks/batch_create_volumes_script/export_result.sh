#!/bin/bash
echo "=== Exporting batch_create_volumes_script result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SCRIPT_PATH="/home/ga/Scripts/create_dept_volumes.sh"
REPORT_PATH="/home/ga/Scripts/volume_report.txt"
RESULT_JSON="/tmp/task_result.json"

# Function to test a volume
test_volume() {
    local vol_name="$1"
    local password="$2"
    local expected_algo="$3"
    local min_size="$4"

    local vol_path="/home/ga/Volumes/$vol_name"
    local mount_point="/tmp/vc_check_${vol_name%.*}"
    local exists="false"
    local created_during_task="false"
    local size_bytes=0
    local mount_success="false"
    local detected_algo="unknown"

    if [ -f "$vol_path" ]; then
        exists="true"
        size_bytes=$(stat -c%s "$vol_path" 2>/dev/null || echo "0")
        local mtime=$(stat -c%Y "$vol_path" 2>/dev/null || echo "0")
        
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during_task="true"
        fi

        # Attempt mount
        mkdir -p "$mount_point"
        if veracrypt --text --mount "$vol_path" "$mount_point" \
            --password="$password" \
            --pim=0 \
            --keyfiles="" \
            --protect-hidden=no \
            --non-interactive >/dev/null 2>&1; then
            
            mount_success="true"
            
            # Check properties
            local props=$(veracrypt --text --volume-properties "$vol_path" --non-interactive 2>/dev/null)
            detected_algo=$(echo "$props" | grep -i "Encryption Algorithm" | awk -F': ' '{print $2}' | tr -d ' \n')
            
            # Dismount
            veracrypt --text --dismount "$mount_point" --non-interactive >/dev/null 2>&1
        fi
        rmdir "$mount_point" 2>/dev/null || true
    fi

    # Output JSON fragment
    echo "\"$vol_name\": {
        \"exists\": $exists,
        \"created_during_task\": $created_during_task,
        \"size_bytes\": $size_bytes,
        \"mount_success\": $mount_success,
        \"detected_algo\": \"$detected_algo\",
        \"expected_algo\": \"$expected_algo\",
        \"min_size\": $min_size
    }"
}

# 1. Analyze Script
SCRIPT_EXISTS="false"
SCRIPT_EXECUTABLE="false"
SCRIPT_CONTENT_SCORE=0

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    if [ -x "$SCRIPT_PATH" ]; then
        SCRIPT_EXECUTABLE="true"
    fi
    
    # Simple content checks
    grep -q "veracrypt.*--create" "$SCRIPT_PATH" && SCRIPT_CONTENT_SCORE=$((SCRIPT_CONTENT_SCORE + 1))
    grep -q "finance_dept" "$SCRIPT_PATH" && SCRIPT_CONTENT_SCORE=$((SCRIPT_CONTENT_SCORE + 1))
    grep -q "legal_dept" "$SCRIPT_PATH" && SCRIPT_CONTENT_SCORE=$((SCRIPT_CONTENT_SCORE + 1))
    grep -q "engineering_dept" "$SCRIPT_PATH" && SCRIPT_CONTENT_SCORE=$((SCRIPT_CONTENT_SCORE + 1))
    grep -q "/dev/urandom" "$SCRIPT_PATH" && SCRIPT_CONTENT_SCORE=$((SCRIPT_CONTENT_SCORE + 1))
fi

# 2. Analyze Report
REPORT_EXISTS="false"
REPORT_LINES_PASS=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_LINES_PASS=$(grep -c "PASS" "$REPORT_PATH" || echo "0")
fi

# 3. Check clean state (dismounted)
# If volumes are still mounted, it's a partial deduction
MOUNTED_COUNT=$(veracrypt --text --list 2>/dev/null | grep -c "Volume:" || echo "0")
CLEAN_STATE="true"
if [ "$MOUNTED_COUNT" -gt 0 ]; then
    CLEAN_STATE="false"
    # Cleanup for system
    veracrypt --text --dismount --non-interactive >/dev/null 2>&1
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Test Volumes
echo "Testing volumes..."
V1_JSON=$(test_volume "finance_dept.hc" "FinanceSafe2024!" "AES" 15728640)
V2_JSON=$(test_volume "legal_dept.hc" "LegalLock2024!" "Serpent" 20971520)
V3_JSON=$(test_volume "engineering_dept.hc" "EngVault2024!" "Twofish" 26214400)

# Construct final JSON
cat > "$RESULT_JSON" << EOF
{
    "script": {
        "exists": $SCRIPT_EXISTS,
        "executable": $SCRIPT_EXECUTABLE,
        "content_matches": $SCRIPT_CONTENT_SCORE
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "pass_count": $REPORT_LINES_PASS
    },
    "volumes": {
        $V1_JSON,
        $V2_JSON,
        $V3_JSON
    },
    "clean_state": $CLEAN_STATE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Result saved to $RESULT_JSON"
echo "=== Export complete ==="