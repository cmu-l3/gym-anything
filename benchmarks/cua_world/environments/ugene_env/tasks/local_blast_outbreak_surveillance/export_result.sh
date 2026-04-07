#!/bin/bash
echo "=== Exporting local_blast_outbreak_surveillance results ==="

OUTBREAK_DIR="/home/ga/UGENE_Data/outbreak"
RESULTS_DIR="$OUTBREAK_DIR/results"
DB_DIR="$OUTBREAK_DIR/blast_db"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 1. Check Database Compilation
DB_EXISTS="false"
DB_CREATED_DURING_TASK="false"
if [ -f "$DB_DIR/swabs_db.nhr" ] && [ -f "$DB_DIR/swabs_db.nin" ] && [ -f "$DB_DIR/swabs_db.nsq" ]; then
    DB_EXISTS="true"
    DB_MTIME=$(stat -c %Y "$DB_DIR/swabs_db.nhr" 2>/dev/null || echo "0")
    if [ "$DB_MTIME" -ge "$TASK_START" ]; then
        DB_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check GFF Export
GFF_EXISTS="false"
GFF_CREATED_DURING_TASK="false"
GFF_HAS_SWAB_A="false"
GFF_FILE="$RESULTS_DIR/mcr1_hits.gff"

if [ -f "$GFF_FILE" ]; then
    GFF_EXISTS="true"
    GFF_MTIME=$(stat -c %Y "$GFF_FILE" 2>/dev/null || echo "0")
    if [ "$GFF_MTIME" -ge "$TASK_START" ]; then
        GFF_CREATED_DURING_TASK="true"
    fi
    
    # Check if Swab A is referenced in the GFF (target sequence name column)
    if grep -qi "Hospital_Swab_A_Isolate" "$GFF_FILE"; then
        GFF_HAS_SWAB_A="true"
    fi
fi

# 3. Check Report Text
REPORT_EXISTS="false"
REPORT_HAS_SWAB_A="false"
REPORT_FILE="$RESULTS_DIR/surveillance_report.txt"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | tr '\n' ' ')
    if echo "$REPORT_CONTENT" | grep -qi "Swab_A\|Swab A"; then
        REPORT_HAS_SWAB_A="true"
    fi
fi

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/blast_result.XXXXXX.json)
python3 << EOF > "$TEMP_JSON"
import json

data = {
    "db_exists": ${DB_EXISTS},
    "db_created_during_task": ${DB_CREATED_DURING_TASK},
    "gff_exists": ${GFF_EXISTS},
    "gff_created_during_task": ${GFF_CREATED_DURING_TASK},
    "gff_has_swab_a": ${GFF_HAS_SWAB_A},
    "report_exists": ${REPORT_EXISTS},
    "report_has_swab_a": ${REPORT_HAS_SWAB_A}
}

with open("$TEMP_JSON", "w") as f:
    json.dump(data, f)
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="