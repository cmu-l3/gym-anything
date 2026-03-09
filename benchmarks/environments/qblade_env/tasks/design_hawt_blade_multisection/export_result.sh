#!/bin/bash
echo "=== Exporting design_hawt_blade_multisection Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

PROJECT_DIR="/home/ga/Documents/projects"
OUTPUT_FILE="$PROJECT_DIR/my_hawt_blade.wpa"
RESULT_FILE="/tmp/task_result.json"

FILE_EXISTS="false"
FILE_SIZE=0
FILE_IS_UNIQUE="false"
FILE_HASH=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_HASH=$(md5sum "$OUTPUT_FILE" 2>/dev/null | cut -d' ' -f1)

    # Anti-copy check: compare against all sample projects
    FILE_IS_UNIQUE="true"
    if [ -f /tmp/initial_sample_hashes ]; then
        if grep -q "$FILE_HASH" /tmp/initial_sample_hashes 2>/dev/null; then
            FILE_IS_UNIQUE="false"
        fi
    fi

    # Also check against sample projects directly
    for wpa in /home/ga/Documents/sample_projects/*.wpa /opt/qblade/*/sample\ projects/*.wpa /opt/qblade/*/*/sample\ projects/*.wpa; do
        if [ -f "$wpa" ]; then
            sample_hash=$(md5sum "$wpa" 2>/dev/null | cut -d' ' -f1)
            if [ "$FILE_HASH" = "$sample_hash" ]; then
                FILE_IS_UNIQUE="false"
                break
            fi
        fi
    done
fi

# Check for alternate output locations
ALT_FILES=""
for d in "/home/ga/Desktop" "/home/ga" "/tmp" "/home/ga/Documents"; do
    found=$(ls "$d"/*.wpa 2>/dev/null | tr '\n' ',')
    if [ -n "$found" ]; then
        ALT_FILES="${ALT_FILES}${found}"
    fi
done

# Check QBlade running state
QBLADE_RUNNING="false"
if is_qblade_running; then
    QBLADE_RUNNING="true"
fi

# Baseline
INITIAL_WPA_COUNT=$(cat /tmp/initial_wpa_count 2>/dev/null || echo "0")
CURRENT_WPA_COUNT=$(ls "$PROJECT_DIR"/*.wpa 2>/dev/null | wc -l)

cat > "$RESULT_FILE" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_hash": "$FILE_HASH",
    "file_is_unique": $FILE_IS_UNIQUE,
    "initial_wpa_count": $INITIAL_WPA_COUNT,
    "current_wpa_count": $CURRENT_WPA_COUNT,
    "alternative_files": "$ALT_FILES",
    "qblade_running": $QBLADE_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="
