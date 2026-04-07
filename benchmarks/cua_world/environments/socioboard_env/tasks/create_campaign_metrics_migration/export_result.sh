#!/bin/bash
echo "=== Exporting create_campaign_metrics_migration task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_TABLES=$(cat /tmp/initial_table_count.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if table exists
TABLE_EXISTS="false"
TABLE_CHECK=$(mysql -u root socioboard -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='socioboard' AND table_name='campaign_metrics';" 2>/dev/null || echo "0")
if [ "$TABLE_CHECK" -ge 1 ]; then
    TABLE_EXISTS="true"
fi

# Get current table count
CURRENT_TABLES=$(mysql -u root socioboard -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='socioboard';" 2>/dev/null || echo "0")

# Get columns info
COLUMNS_JSON="[]"
if [ "$TABLE_EXISTS" = "true" ]; then
    COLUMNS_JSON=$(python3 -c "
import subprocess, json
try:
    cmd = \"mysql -u root socioboard -N -e \\\"SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT FROM information_schema.columns WHERE table_schema='socioboard' AND table_name='campaign_metrics' ORDER BY ORDINAL_POSITION;\\\"\"
    out = subprocess.check_output(cmd, shell=True, text=True)
    cols = []
    for line in out.strip().split('\n'):
        if line.strip():
            parts = line.split('\t')
            if len(parts) >= 4:
                cols.append({
                    'name': parts[0].strip(),
                    'type': parts[1].strip().lower(),
                    'nullable': parts[2].strip(),
                    'default': parts[3].strip() if parts[3].strip() != 'NULL' else None
                })
    print(json.dumps(cols))
except Exception as e:
    print('[]')
")
fi

# Analyze migration file via Python
python3 << 'PYEOF'
import os, json

mig_dir = "/opt/socioboard/socioboard-api/library/sequelize-cli/migrations"
res = {
    "exists": False,
    "path": "",
    "content": "",
    "mtime": 0,
    "has_create": False,
    "has_drop": False
}

if os.path.exists(mig_dir):
    for f in os.listdir(mig_dir):
        if 'campaign' in f.lower() and 'metric' in f.lower() and f.endswith('.js'):
            filepath = os.path.join(mig_dir, f)
            res["exists"] = True
            res["path"] = filepath
            res["mtime"] = int(os.path.getmtime(filepath))
            try:
                with open(filepath, 'r') as fh:
                    content = fh.read()
                    res["content"] = content
                    res["has_create"] = 'createTable' in content
                    res["has_drop"] = 'dropTable' in content
            except Exception:
                pass
            break

with open('/tmp/mig_info.json', 'w') as f:
    json.dump(res, f)
PYEOF

MIG_EXISTS=$(python3 -c "import json; print(str(json.load(open('/tmp/mig_info.json'))['exists']).lower())")
MIG_PATH=$(python3 -c "import json; print(json.load(open('/tmp/mig_info.json'))['path'])")
MIG_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/mig_info.json'))['mtime'])")
MIG_HAS_CREATE=$(python3 -c "import json; print(str(json.load(open('/tmp/mig_info.json'))['has_create']).lower())")
MIG_HAS_DROP=$(python3 -c "import json; print(str(json.load(open('/tmp/mig_info.json'))['has_drop']).lower())")
rm -f /tmp/mig_info.json

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_tables": $INITIAL_TABLES,
    "current_tables": $CURRENT_TABLES,
    "table_exists": $TABLE_EXISTS,
    "columns": $COLUMNS_JSON,
    "migration_exists": $MIG_EXISTS,
    "migration_path": "$MIG_PATH",
    "migration_mtime": $MIG_MTIME,
    "migration_has_create": $MIG_HAS_CREATE,
    "migration_has_drop": $MIG_HAS_DROP,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="