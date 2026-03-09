#!/bin/bash
# Export script for HTTPS Security Protocol Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting HTTPS Security Protocol Audit Result ==="

# 1. Capture final state
take_screenshot /tmp/task_end_screenshot.png

# 2. Define paths and timestamps
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

SECURITY_EXPORT="$EXPORT_DIR/security_tab_export.csv"
INTERNAL_EXPORT="$EXPORT_DIR/internal_all_export.csv"
REPORT_FILE="$REPORTS_DIR/security_audit_report.txt"

# 3. Analyze Security Export CSV
SECURITY_EXISTS="false"
SECURITY_VALID="false"
SECURITY_ROW_COUNT=0
SECURITY_HAS_PROTOCOL="false"

if [ -f "$SECURITY_EXPORT" ]; then
    FILE_EPOCH=$(stat -c %Y "$SECURITY_EXPORT" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        SECURITY_EXISTS="true"
        # Check rows
        ROW_COUNT=$(wc -l < "$SECURITY_EXPORT" 2>/dev/null || echo "0")
        if [ "$ROW_COUNT" -gt 1 ]; then
            SECURITY_ROW_COUNT=$((ROW_COUNT - 1))
            SECURITY_VALID="true"
        fi
        # Check for Security-specific columns or data (Protocol, HSTS, etc)
        # Note: SF Security export usually contains columns like "Protocol", "Status", "Insecure Element"
        HEADER=$(head -1 "$SECURITY_EXPORT" 2>/dev/null || echo "")
        if echo "$HEADER" | grep -qi "Protocol\|Security\|Mixed Content\|HSTS"; then
            SECURITY_HAS_PROTOCOL="true"
        fi
    fi
fi

# 4. Analyze Internal Export CSV
INTERNAL_EXISTS="false"
INTERNAL_VALID="false"
INTERNAL_ROW_COUNT=0

if [ -f "$INTERNAL_EXPORT" ]; then
    FILE_EPOCH=$(stat -c %Y "$INTERNAL_EXPORT" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        INTERNAL_EXISTS="true"
        ROW_COUNT=$(wc -l < "$INTERNAL_EXPORT" 2>/dev/null || echo "0")
        if [ "$ROW_COUNT" -gt 10 ]; then # Internal export should have many rows for this site
            INTERNAL_ROW_COUNT=$((ROW_COUNT - 1))
            INTERNAL_VALID="true"
        fi
    fi
fi

# 5. Analyze Report File
REPORT_EXISTS="false"
REPORT_LENGTH=0
REPORT_CONTENT_CHECK="false"

if [ -f "$REPORT_FILE" ]; then
    FILE_EPOCH=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_EXISTS="true"
        REPORT_LENGTH=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")
        
        # Check for keywords
        CONTENT=$(cat "$REPORT_FILE" | tr '[:upper:]' '[:lower:]')
        if [[ "$CONTENT" == *"https"* ]] && [[ "$CONTENT" == *"recommend"* ]]; then
            REPORT_CONTENT_CHECK="true"
        fi
    fi
fi

# 6. Check App State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 7. Generate JSON Result
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING,
    "security_export": {
        "exists": $SECURITY_EXISTS,
        "valid": $SECURITY_VALID,
        "row_count": $SECURITY_ROW_COUNT,
        "has_protocol_columns": $SECURITY_HAS_PROTOCOL
    },
    "internal_export": {
        "exists": $INTERNAL_EXISTS,
        "valid": $INTERNAL_VALID,
        "row_count": $INTERNAL_ROW_COUNT
    },
    "report": {
        "exists": $REPORT_EXISTS,
        "length": $REPORT_LENGTH,
        "content_check": $REPORT_CONTENT_CHECK
    },
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result generated at /tmp/task_result.json")
PYEOF

cat /tmp/task_result.json
echo "=== Export Complete ==="