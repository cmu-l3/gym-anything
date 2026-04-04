#!/bin/bash
echo "=== Exporting prepare_multi_re_polar_dataset results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Project File
PROJECT_PATH="/home/ga/Documents/projects/re_dataset_study.wpa"
PROJECT_EXISTS="false"
PROJECT_SIZE=0
if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH" 2>/dev/null || echo "0")
fi

# 2. Check Polar Files
POLAR_DIR="/home/ga/Documents/polars"
FILE_1M="$POLAR_DIR/NACA4415_1M_360.dat"
FILE_3M="$POLAR_DIR/NACA4415_3M_360.dat"
FILE_5M="$POLAR_DIR/NACA4415_5M_360.dat"

# Helper to check file existence and modification time
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false" # Exists but old (anti-gaming, though we cleaned dir)
        fi
    else
        echo "false"
    fi
}

EXISTS_1M=$(check_file "$FILE_1M")
EXISTS_3M=$(check_file "$FILE_3M")
EXISTS_5M=$(check_file "$FILE_5M")

# 3. Bundle Polar Files for Verification
# We zip the polars directory so the python verifier can parse the full content
# of all generated files to check for 360 extrapolation and physics.
BUNDLE_PATH="/tmp/polars_bundle.zip"
rm -f "$BUNDLE_PATH"
if [ -d "$POLAR_DIR" ]; then
    # Zip only .dat or .txt files
    cd "$POLAR_DIR"
    zip -q "$BUNDLE_PATH" *.dat *.txt 2>/dev/null || true
fi

BUNDLE_EXISTS="false"
if [ -f "$BUNDLE_PATH" ]; then
    BUNDLE_EXISTS="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "polar_1m_exists": $EXISTS_1M,
    "polar_3m_exists": $EXISTS_3M,
    "polar_5m_exists": $EXISTS_5M,
    "bundle_exists": $BUNDLE_EXISTS,
    "bundle_path": "$BUNDLE_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"
chmod 666 "$BUNDLE_PATH" 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="