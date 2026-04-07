#!/bin/bash
# export_result.sh - Post-task hook for FDA 510(k) Research

echo "=== Exporting FDA Research Results ==="

# Paths
OUTPUT_DIR="/home/ga/Documents/FDA_Research"
LOG_FILE="$OUTPUT_DIR/clearance_log.txt"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check Edge History for FDA visits
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
CURRENT_FDA_VISITS="0"
INITIAL_FDA_VISITS=$(cat /tmp/initial_fda_visits.txt 2>/dev/null || echo "0")

if [ -f "$HISTORY_DB" ]; then
    cp "$HISTORY_DB" /tmp/history_final.db
    chmod 666 /tmp/history_final.db
    CURRENT_FDA_VISITS=$(sqlite3 /tmp/history_final.db "SELECT COUNT(*) FROM urls WHERE url LIKE '%accessdata.fda.gov%';" 2>/dev/null || echo "0")
    rm -f /tmp/history_final.db
fi

# Calculate new visits
NEW_VISITS=$((CURRENT_FDA_VISITS - INITIAL_FDA_VISITS))
if [ "$NEW_VISITS" -lt 0 ]; then NEW_VISITS=0; fi

# 3. Analyze Output Directory
DIR_EXISTS="false"
PDF_FILES="[]"
LOG_EXISTS="false"
LOG_CONTENT=""

if [ -d "$OUTPUT_DIR" ]; then
    DIR_EXISTS="true"
    
    # List PDF files with their modification times and sizes
    # We use python to get a clean JSON list of file info
    PDF_FILES=$(python3 -c "
import os, json
pdf_files = []
directory = '$OUTPUT_DIR'
start_time = $TASK_START_TIME
try:
    for f in os.listdir(directory):
        if f.lower().endswith('.pdf'):
            path = os.path.join(directory, f)
            stat = os.stat(path)
            # Check if valid PDF header
            is_pdf_header = False
            try:
                with open(path, 'rb') as pdf:
                    header = pdf.read(4)
                    if header.startswith(b'%PDF'):
                        is_pdf_header = True
            except:
                pass
                
            pdf_files.append({
                'filename': f,
                'size': stat.st_size,
                'mtime': stat.st_mtime,
                'created_during_task': stat.st_mtime > start_time,
                'valid_header': is_pdf_header
            })
    print(json.dumps(pdf_files))
except Exception as e:
    print('[]')
")

    # Read Log File
    if [ -f "$LOG_FILE" ]; then
        LOG_EXISTS="true"
        # Read content, escape for JSON
        LOG_CONTENT=$(cat "$LOG_FILE" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')
    else
        LOG_CONTENT="\"\""
    fi
fi

# 4. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START_TIME,
    "fda_visits_new": $NEW_VISITS,
    "output_dir_exists": $DIR_EXISTS,
    "log_file_exists": $LOG_EXISTS,
    "log_content": $LOG_CONTENT,
    "pdf_files": $PDF_FILES,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"