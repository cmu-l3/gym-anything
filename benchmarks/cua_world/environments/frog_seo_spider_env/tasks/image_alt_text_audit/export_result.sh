#!/bin/bash
# Export result script for Image Alt Text Audit
# Validates existence and content of CSV export and text report

# Ensure we capture errors but don't exit immediately so we can generate the JSON
set +e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Initialize variables
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_PATH="/home/ga/Documents/SEO/reports/image_audit_report.txt"

# 3. Analyze CSV Export
# Logic: Find the most recently created CSV that has "image" in filename
BEST_CSV=""
CSV_CREATED_DURING_TASK="false"
CSV_HAS_IMAGE_COLS="false"
CSV_HAS_DATA="false"
CSV_TARGET_DOMAIN="false"
CSV_ROW_COUNT=0

# Find candidate files (contain 'image', newer than start time)
CANDIDATE_FILES=$(find "$EXPORT_DIR" -type f -name "*image*.csv" -newermt "@$TASK_START_EPOCH" 2>/dev/null)

if [ -n "$CANDIDATE_FILES" ]; then
    CSV_CREATED_DURING_TASK="true"
    # Pick the largest one (likely to contain data)
    BEST_CSV=$(ls -S $CANDIDATE_FILES | head -n 1)
    
    echo "Found candidate CSV: $BEST_CSV"
    
    # Analyze content
    HEADER=$(head -n 1 "$BEST_CSV")
    # Check for image-specific columns (Screaming Frog Image tab exports have 'Alt Text', 'Image', etc.)
    if echo "$HEADER" | grep -qi "Alt Text\|Image\|Source\|Size"; then
        CSV_HAS_IMAGE_COLS="true"
    fi
    
    # Check for target domain data
    if grep -qi "books.toscrape.com" "$BEST_CSV"; then
        CSV_TARGET_DOMAIN="true"
    fi
    
    # Count rows (excluding header)
    LINE_COUNT=$(wc -l < "$BEST_CSV")
    if [ "$LINE_COUNT" -gt 1 ]; then
        CSV_HAS_DATA="true"
        CSV_ROW_COUNT=$((LINE_COUNT - 1))
    fi
fi

# 4. Analyze Text Report
REPORT_EXISTS="false"
REPORT_LENGTH=0
REPORT_HAS_NUMBERS="false"
REPORT_HAS_KEYWORDS="false"
REPORT_HAS_RECOMMENDATION="false"
REPORT_HAS_URL="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_LENGTH=$(stat -c %s "$REPORT_PATH")
    
    CONTENT=$(cat "$REPORT_PATH")
    
    # Check for numbers (counts)
    if echo "$CONTENT" | grep -qE "[0-9]+"; then
        REPORT_HAS_NUMBERS="true"
    fi
    
    # Check for keywords "alt" (case insensitive)
    if echo "$CONTENT" | grep -qi "alt"; then
        REPORT_HAS_KEYWORDS="true"
    fi
    
    # Check for "recommend" section/keyword
    if echo "$CONTENT" | grep -qi "recommend"; then
        REPORT_HAS_RECOMMENDATION="true"
    fi
    
    # Check for target domain URL mentioning
    if echo "$CONTENT" | grep -qi "books.toscrape.com"; then
        REPORT_HAS_URL="true"
    fi
fi

# 5. Check App Status
APP_RUNNING="false"
if is_screamingfrog_running; then
    APP_RUNNING="true"
fi

# 6. Generate JSON Result
# Use python to generate safe JSON
python3 << EOF
import json
import os

result = {
    "timestamp": "$(date -Iseconds)",
    "app_running": $APP_RUNNING,
    "csv": {
        "exists": "$CSV_CREATED_DURING_TASK" == "true",
        "path": "$BEST_CSV",
        "has_image_columns": "$CSV_HAS_IMAGE_COLS" == "true",
        "has_target_domain": "$CSV_TARGET_DOMAIN" == "true",
        "has_data": "$CSV_HAS_DATA" == "true",
        "row_count": $CSV_ROW_COUNT
    },
    "report": {
        "exists": "$REPORT_EXISTS" == "true",
        "length": $REPORT_LENGTH,
        "has_numbers": "$REPORT_HAS_NUMBERS" == "true",
        "has_keywords": "$REPORT_HAS_KEYWORDS" == "true",
        "has_recommendation": "$REPORT_HAS_RECOMMENDATION" == "true",
        "has_url": "$REPORT_HAS_URL" == "true"
    }
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="