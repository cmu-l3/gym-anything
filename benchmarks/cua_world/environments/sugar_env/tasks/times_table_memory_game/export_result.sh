#!/bin/bash
# Do NOT use set -e
echo "=== Exporting times_table_memory_game task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

su - ga -c "$SUGAR_ENV scrot /tmp/memorize_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/times_table_memory_game_start_ts 2>/dev/null || echo "0")
JOURNAL_DIR="/home/ga/.sugar/default/datastore"

JOURNAL_FOUND="false"
JOURNAL_ENTRY_PATH=""
PAIR_COUNT=0
HAS_SIX_TABLE="false"
HAS_ANSWER_6="false"
HAS_ANSWER_48="false"
DATA_SIZE=0

# Search Journal for "6 Times Table Game" entry created after task start
if [ -d "$JOURNAL_DIR" ]; then
    # Find metadata/title files newer than task start
    while IFS= read -r -d '' TITLE_FILE; do
        if grep -q "6 Times Table Game" "$TITLE_FILE" 2>/dev/null; then
            JOURNAL_FOUND="true"
            ENTRY_DIR=$(dirname "$(dirname "$TITLE_FILE")")
            JOURNAL_ENTRY_PATH="$ENTRY_DIR/data"
            echo "Found Journal entry: 6 Times Table Game at $ENTRY_DIR"
            break
        fi
    done < <(find "$JOURNAL_DIR" -name "title" -newer /tmp/times_table_memory_game_start_ts -print0 2>/dev/null)

    # Also search all title files (in case timestamp differs)
    if [ "$JOURNAL_FOUND" = "false" ]; then
        while IFS= read -r -d '' TITLE_FILE; do
            if grep -q "6 Times Table Game" "$TITLE_FILE" 2>/dev/null; then
                JOURNAL_FOUND="true"
                ENTRY_DIR=$(dirname "$(dirname "$TITLE_FILE")")
                JOURNAL_ENTRY_PATH="$ENTRY_DIR/data"
                echo "Found Journal entry (any time): 6 Times Table Game"
                break
            fi
        done < <(find "$JOURNAL_DIR" -name "title" -print0 2>/dev/null)
    fi
fi

# If found, inspect the data file for game content
if [ "$JOURNAL_FOUND" = "true" ] && [ -f "$JOURNAL_ENTRY_PATH" ]; then
    DATA_SIZE=$(stat --format=%s "$JOURNAL_ENTRY_PATH" 2>/dev/null || echo "0")
    echo "Game data file: $JOURNAL_ENTRY_PATH ($DATA_SIZE bytes)"

    # Parse game data file — Memorize stores games as XML
    python3 << 'PYEOF' > /tmp/memorize_analysis.json 2>/dev/null || echo '{"error":"parse_failed","pair_count":0}' > /tmp/memorize_analysis.json
import json
import xml.etree.ElementTree as ET
import re
import os
import sys

result = {
    "pair_count": 0,
    "has_six_table": False,
    "has_answer_6": False,
    "has_answer_48": False,
    "expressions_found": [],
    "answers_found": [],
    "error": None
}

# Find the data file path
import subprocess
proc = subprocess.run(
    ['find', '/home/ga/.sugar/default/datastore', '-name', 'title'],
    capture_output=True, text=True
)
data_file = None
for line in proc.stdout.strip().split('\n'):
    if not line:
        continue
    try:
        with open(line) as f:
            if '6 Times Table Game' in f.read():
                entry_dir = os.path.dirname(os.path.dirname(line))
                data_file = os.path.join(entry_dir, 'data')
                break
    except Exception:
        pass

if not data_file or not os.path.exists(data_file):
    result["error"] = "data_file_not_found"
    print(json.dumps(result))
    sys.exit(0)

try:
    # Try XML parsing first (Memorize uses XML format)
    content = open(data_file, 'r', errors='replace').read()
    result["raw_content_preview"] = content[:500]

    # Look for 6x table expressions and answers
    six_table_exprs = re.findall(r'6\s*[xX\u00d7\*]\s*\d+|\d+\s*[xX\u00d7\*]\s*6', content)
    answers = re.findall(r'\b(6|12|18|24|30|36|42|48)\b', content)

    result["expressions_found"] = list(set(six_table_exprs))[:20]
    result["answers_found"] = list(set(answers))[:20]
    result["has_six_table"] = len(six_table_exprs) > 0
    result["has_answer_6"] = '6' in answers
    result["has_answer_48"] = '48' in answers

    # Try to count pairs from XML structure
    try:
        root = ET.fromstring(content)
        # Memorize game XML has <pair> elements or similar
        pairs = root.findall('.//pair') or root.findall('.//card')
        if pairs:
            result["pair_count"] = len(pairs)
        else:
            # Count by counting expression occurrences as fallback
            result["pair_count"] = len(six_table_exprs)
    except ET.ParseError:
        result["pair_count"] = len(six_table_exprs)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    if [ -f /tmp/memorize_analysis.json ]; then
        PAIR_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/memorize_analysis.json')); print(d.get('pair_count',0))" 2>/dev/null || echo "0")
        HAS_SIX_TABLE=$(python3 -c "import json; d=json.load(open('/tmp/memorize_analysis.json')); print(str(d.get('has_six_table',False)).lower())" 2>/dev/null || echo "false")
        HAS_ANSWER_6=$(python3 -c "import json; d=json.load(open('/tmp/memorize_analysis.json')); print(str(d.get('has_answer_6',False)).lower())" 2>/dev/null || echo "false")
        HAS_ANSWER_48=$(python3 -c "import json; d=json.load(open('/tmp/memorize_analysis.json')); print(str(d.get('has_answer_48',False)).lower())" 2>/dev/null || echo "false")
    fi
fi

cat > /tmp/times_table_memory_game_result.json << EOF
{
    "journal_found": $JOURNAL_FOUND,
    "data_size": $DATA_SIZE,
    "pair_count": $PAIR_COUNT,
    "has_six_table": $HAS_SIX_TABLE,
    "has_answer_6": $HAS_ANSWER_6,
    "has_answer_48": $HAS_ANSWER_48
}
EOF

chmod 666 /tmp/times_table_memory_game_result.json
echo "Result saved to /tmp/times_table_memory_game_result.json"
cat /tmp/times_table_memory_game_result.json
echo "=== Export complete ==="
