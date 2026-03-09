#!/bin/bash
echo "=== Exporting Export ER Diagram results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize
DIAGRAM_FILE_EXISTS=false
DIAGRAM_FILE_PATH=""
DIAGRAM_FILE_SIZE=0
SQL_DEVELOPER_RUNNING=false
DATA_MODELER_OPENED=false

# Check SQL Developer running
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    SQL_DEVELOPER_RUNNING=true
fi

# Check if Data Modeler window/tab was opened
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "data modeler\|relational model"; then
    DATA_MODELER_OPENED=true
fi

# Check for exported diagram file (PNG, SVG, JPG, or PDF)
for ext in png svg jpg jpeg pdf; do
    FILE="/home/ga/Documents/exports/hr_schema_diagram.$ext"
    if [ -f "$FILE" ] && [ -s "$FILE" ]; then
        DIAGRAM_FILE_EXISTS=true
        DIAGRAM_FILE_PATH="$FILE"
        DIAGRAM_FILE_SIZE=$(stat -c%s "$FILE" 2>/dev/null || echo "0")
        break
    fi
done

# Also check for any image file in the exports directory with "diagram" or "er" in name
if [ "$DIAGRAM_FILE_EXISTS" = "false" ]; then
    for f in /home/ga/Documents/exports/*diagram* /home/ga/Documents/exports/*er_* /home/ga/Documents/exports/*schema*; do
        if [ -f "$f" ] && [ -s "$f" ]; then
            DIAGRAM_FILE_EXISTS=true
            DIAGRAM_FILE_PATH="$f"
            DIAGRAM_FILE_SIZE=$(stat -c%s "$f" 2>/dev/null || echo "0")
            break
        fi
    done
fi

# Check if Data Modeler designs directory was created (proves DM was used)
DM_DESIGNS_EXIST=false
DM_XML_TABLES=""
if [ -d "/home/ga/.sqldeveloper" ]; then
    DM_DIR=$(find /home/ga/.sqldeveloper -path "*/datamodeler*" -type d 2>/dev/null | head -1)
    if [ -n "$DM_DIR" ]; then
        DM_DESIGNS_EXIST=true
        # Check Data Modeler XML design files for HR table names
        for xmlf in $(find /home/ga/.sqldeveloper -name "*.xml" -path "*/datamodeler*" -type f 2>/dev/null | head -10); do
            for tbl in EMPLOYEES DEPARTMENTS JOBS LOCATIONS; do
                if grep -qi "$tbl" "$xmlf" 2>/dev/null; then
                    if ! echo "$DM_XML_TABLES" | grep -q "$tbl"; then
                        DM_XML_TABLES="${DM_XML_TABLES:+$DM_XML_TABLES,}$tbl"
                    fi
                fi
            done
        done
    fi
fi

# Check diagram content for SVG (text-based, can search for table names)
DIAGRAM_CONTENT_TABLES=""
if [ "$DIAGRAM_FILE_EXISTS" = "true" ] && [ -n "$DIAGRAM_FILE_PATH" ]; then
    if echo "$DIAGRAM_FILE_PATH" | grep -qi "\.svg$"; then
        for tbl in EMPLOYEES DEPARTMENTS JOBS LOCATIONS COUNTRIES REGIONS JOB_HISTORY; do
            if grep -qi "$tbl" "$DIAGRAM_FILE_PATH" 2>/dev/null; then
                DIAGRAM_CONTENT_TABLES="${DIAGRAM_CONTENT_TABLES:+$DIAGRAM_CONTENT_TABLES,}$tbl"
            fi
        done
    fi
fi

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sql_developer_running": $SQL_DEVELOPER_RUNNING,
    "diagram_file_exists": $DIAGRAM_FILE_EXISTS,
    "diagram_file_path": "$DIAGRAM_FILE_PATH",
    "diagram_file_size": $DIAGRAM_FILE_SIZE,
    "data_modeler_opened": $DATA_MODELER_OPENED,
    "dm_designs_exist": $DM_DESIGNS_EXIST,
    "dm_xml_tables": "$DM_XML_TABLES",
    "diagram_content_tables": "$DIAGRAM_CONTENT_TABLES",
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/er_diagram_result.json 2>/dev/null || sudo rm -f /tmp/er_diagram_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/er_diagram_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/er_diagram_result.json
chmod 666 /tmp/er_diagram_result.json 2>/dev/null || sudo chmod 666 /tmp/er_diagram_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/er_diagram_result.json"
cat /tmp/er_diagram_result.json
echo "=== Export complete ==="
