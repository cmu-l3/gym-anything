#!/bin/bash
echo "=== Exporting fix_wrong_panel_dimensions result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/fix_wrong_panel_dimensions_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Documents/SolveSpace/panel_corrected.slvs"

sleep 1
take_screenshot /tmp/fix_wrong_panel_dimensions_end.png

FILE_EXISTS=false
FILE_IS_NEW=false
FILE_SIZE=0
if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$OUTPUT" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FILE_IS_NEW=true
fi

CONSTRAINT_JSON="[]"
if $FILE_EXISTS; then
    CONSTRAINT_JSON=$(python3 << 'PYEOF'
import json

def parse_slvs_constraints(fp):
    try:
        with open(fp, 'rb') as f:
            content = f.read()
        cs = []
        for part in content.split(b'\n\n'):
            if b'AddConstraint' not in part:
                continue
            c = {}
            for line in part.decode('utf-8', errors='replace').strip().split('\n'):
                if '=' in line:
                    k, _, v = line.partition('=')
                    c[k.strip()] = v.strip()
            if 'Constraint.type' in c:
                try: c['Constraint.type'] = int(c['Constraint.type'])
                except: pass
                if 'Constraint.valA' in c:
                    try: c['Constraint.valA'] = float(c['Constraint.valA'])
                    except: pass
                cs.append(c)
        return cs
    except:
        return []

cs = parse_slvs_constraints('/home/ga/Documents/SolveSpace/panel_corrected.slvs')
relevant = [{'type': c['Constraint.type'], 'valA': c.get('Constraint.valA', 0)}
            for c in cs if c.get('Constraint.type') in (30, 90)]
print(json.dumps(relevant))
PYEOF
    )
fi

cat > /tmp/fix_wrong_panel_dimensions_result.json << EOF
{
    "task_start": $TASK_START,
    "output_file_exists": $FILE_EXISTS,
    "output_file_is_new": $FILE_IS_NEW,
    "output_file_size": $FILE_SIZE,
    "constraints": $CONSTRAINT_JSON
}
EOF

echo "=== Export Complete ==="
