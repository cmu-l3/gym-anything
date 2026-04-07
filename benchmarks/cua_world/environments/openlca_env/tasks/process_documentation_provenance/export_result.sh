#!/bin/bash
# Export script for Process Documentation task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Verification Data ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Basic file check (JSON-LD Export)
EXPORT_FILE="/home/ga/LCA_Results/hdpe_process_export.zip"
EXPORT_EXISTS="false"
EXPORT_SIZE=0
EXPORT_MTIME=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    EXPORT_SIZE=$(stat -c%s "$EXPORT_FILE")
    EXPORT_MTIME=$(stat -c%Y "$EXPORT_FILE")
fi

# Check other possible locations/names if user didn't follow exact naming
if [ "$EXPORT_EXISTS" = "false" ]; then
    ALT_FILE=$(find /home/ga/LCA_Results -name "*.zip" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$ALT_FILE" ]; then
        EXPORT_FILE="$ALT_FILE"
        EXPORT_EXISTS="true"
        EXPORT_SIZE=$(stat -c%s "$EXPORT_FILE")
        EXPORT_MTIME=$(stat -c%Y "$EXPORT_FILE")
    fi
fi

# 3. Database Verification (Derby Queries)
# Close OpenLCA to unlock Derby DB
close_openlca
sleep 3

# Find active database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
if [ -d "$DB_DIR" ]; then
    ACTIVE_DB=$(du -s "$DB_DIR"/*/ 2>/dev/null | sort -nr | head -1 | cut -f2)
fi

DB_DATA_JSON="{}"

if [ -n "$ACTIVE_DB" ] && [ -d "$ACTIVE_DB" ]; then
    echo "Querying database: $ACTIVE_DB"
    
    # Query Actors
    ACTORS_OUT=$(derby_query "$ACTIVE_DB" "SELECT NAME, DESCRIPTION FROM TBL_ACTORS;")
    
    # Query Sources
    SOURCES_OUT=$(derby_query "$ACTIVE_DB" "SELECT NAME, YEAR FROM TBL_SOURCES;")
    
    # Query Process
    PROCESS_OUT=$(derby_query "$ACTIVE_DB" "SELECT NAME, DESCRIPTION FROM TBL_PROCESSES WHERE NAME LIKE '%HDPE%';")
    
    # Advanced: Query Documentation Links
    # Note: Schema varies by version. 
    # TBL_PROCESS_DOCS usually links to ACTORS via f_data_generator, f_reviewer
    # TBL_PROCESSES links to TBL_PROCESS_DOCS via f_doc
    
    DOC_LINKS_OUT=$(derby_query "$ACTIVE_DB" "
        SELECT p.NAME, gen.NAME as GENERATOR, rev.NAME as REVIEWER, src.NAME as SOURCE 
        FROM TBL_PROCESSES p 
        LEFT JOIN TBL_PROCESS_DOCS d ON p.F_DOC = d.ID 
        LEFT JOIN TBL_ACTORS gen ON d.F_DATA_GENERATOR = gen.ID 
        LEFT JOIN TBL_ACTORS rev ON d.F_REVIEWER = rev.ID 
        LEFT JOIN TBL_SOURCES src ON d.F_PUBLICATION = src.ID
        WHERE p.NAME LIKE '%HDPE%';
    ")
    
    # Use python to construct the JSON properly to avoid escaping hell in bash
    DB_DATA_JSON=$(python3 -c "
import json, sys
def parse_derby(text):
    lines = [l.strip() for l in text.split('\n') if l.strip() and not l.startswith('ij>') and 'rows selected' not in l]
    # Skip header row if exists (usually first row of actual data)
    return lines

actors = '''$ACTORS_OUT'''
sources = '''$SOURCES_OUT'''
process = '''$PROCESS_OUT'''
links = '''$DOC_LINKS_OUT'''

data = {
    'actors': parse_derby(actors),
    'sources': parse_derby(sources),
    'processes': parse_derby(process),
    'links': parse_derby(links)
}
print(json.dumps(data))
")
fi

# 4. Construct Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "export_file_exists": $EXPORT_EXISTS,
    "export_file_size": $EXPORT_SIZE,
    "export_file_mtime": $EXPORT_MTIME,
    "db_data": $DB_DATA_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"