#!/bin/bash
# Export script for chinook_schema_documentation
# Captures files and verifies DBeaver configuration

echo "=== Exporting Chinook Schema Documentation Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png
sleep 1

# 2. Define expected paths
DB_PATH="/home/ga/Documents/databases/chinook.db"
DDL_PATH="/home/ga/Documents/exports/chinook_schema.sql"
REL_PATH="/home/ga/Documents/exports/chinook_relationships.csv"
STATS_PATH="/home/ga/Documents/exports/chinook_table_stats.csv"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

# 3. Check DBeaver Connection (Must be named 'Chinook')
CONNECTION_FOUND="false"
CONNECTION_CORRECT_PATH="false"

if [ -f "$DBEAVER_CONFIG" ]; then
    # Parse JSON to find connection named 'Chinook'
    CONN_CHECK=$(python3 -c "
import json, sys
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    found = False
    path_ok = False
    for k, v in config.get('connections', {}).items():
        if v.get('name', '') == 'Chinook':
            found = True
            if '$DB_PATH' in v.get('configuration', {}).get('database', ''):
                path_ok = True
            break
    print(f'{found}|{path_ok}')
except Exception as e:
    print('False|False')
")
    CONNECTION_FOUND=$(echo "$CONN_CHECK" | cut -d'|' -f1)
    CONNECTION_CORRECT_PATH=$(echo "$CONN_CHECK" | cut -d'|' -f2)
fi

# 4. Check file existence and timestamps
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo 0)

check_file_status() {
    local fpath=$1
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo 0)
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo 0)
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true|$size"
        else
            echo "false|$size"
        fi
    else
        echo "false|0"
    fi
}

DDL_STATUS=$(check_file_status "$DDL_PATH")
REL_STATUS=$(check_file_status "$REL_PATH")
STATS_STATUS=$(check_file_status "$STATS_PATH")

DDL_EXISTS=$(echo "$DDL_STATUS" | cut -d'|' -f1)
DDL_SIZE=$(echo "$DDL_STATUS" | cut -d'|' -f2)

REL_EXISTS=$(echo "$REL_STATUS" | cut -d'|' -f1)
REL_SIZE=$(echo "$REL_STATUS" | cut -d'|' -f2)

STATS_EXISTS=$(echo "$STATS_STATUS" | cut -d'|' -f1)
STATS_SIZE=$(echo "$STATS_STATUS" | cut -d'|' -f2)

# 5. Prepare files for verifier (copy to /tmp with readable names)
# We copy them to /tmp so verifier can read them easily via copy_from_env
if [ -f "$DDL_PATH" ]; then cp "$DDL_PATH" /tmp/agent_ddl.sql; chmod 644 /tmp/agent_ddl.sql; fi
if [ -f "$REL_PATH" ]; then cp "$REL_PATH" /tmp/agent_rel.csv; chmod 644 /tmp/agent_rel.csv; fi
if [ -f "$STATS_PATH" ]; then cp "$STATS_PATH" /tmp/agent_stats.csv; chmod 644 /tmp/agent_stats.csv; fi

# 6. Generate JSON Result
cat > /tmp/task_result.json << EOF
{
    "connection_found": ${CONNECTION_FOUND,,},
    "connection_correct_path": ${CONNECTION_CORRECT_PATH,,},
    "ddl_exists": ${DDL_EXISTS},
    "ddl_size": ${DDL_SIZE},
    "rel_exists": ${REL_EXISTS},
    "rel_size": ${REL_SIZE},
    "stats_exists": ${STATS_EXISTS},
    "stats_size": ${STATS_SIZE},
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="