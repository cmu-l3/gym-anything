#!/bin/bash
echo "=== Exporting extrude_constrained_profile result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/extrude_constrained_profile_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Documents/SolveSpace/profile_extruded.slvs"

sleep 1
take_screenshot /tmp/extrude_constrained_profile_end.png

FILE_EXISTS=false
FILE_IS_NEW=false
FILE_SIZE=0
if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$OUTPUT" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FILE_IS_NEW=true
fi

# Parse groups and constraints
PARSE_RESULT=$(python3 << 'PYEOF'
import json, sys

def parse_slvs(fp):
    try:
        with open(fp, 'rb') as f:
            content = f.read()
        groups = []
        constraints = []
        for part in content.split(b'\n\n'):
            text = part.decode('utf-8', errors='replace').strip()
            if 'AddGroup' in text:
                g = {}
                for line in text.split('\n'):
                    if '=' in line:
                        k, _, v = line.partition('=')
                        g[k.strip()] = v.strip()
                if 'Group.type' in g:
                    try: g['Group.type'] = int(g['Group.type'])
                    except: pass
                    groups.append(g)
            elif 'AddConstraint' in text:
                c = {}
                for line in text.split('\n'):
                    if '=' in line:
                        k, _, v = line.partition('=')
                        c[k.strip()] = v.strip()
                if 'Constraint.type' in c:
                    try: c['Constraint.type'] = int(c['Constraint.type'])
                    except: pass
                    if 'Constraint.valA' in c:
                        try: c['Constraint.valA'] = float(c['Constraint.valA'])
                        except: pass
                    constraints.append(c)
        return groups, constraints
    except Exception as e:
        return [], []

groups, constraints = parse_slvs('/home/ga/Documents/SolveSpace/profile_extruded.slvs')
group_types = [g.get('Group.type') for g in groups]
dist_cs = [{'type': c['Constraint.type'], 'valA': c.get('Constraint.valA', 0)}
           for c in constraints if c.get('Constraint.type') in (30, 90)]
print(json.dumps({'group_types': group_types, 'dist_constraints': dist_cs}))
PYEOF
)

if [ -z "$PARSE_RESULT" ]; then
    PARSE_RESULT='{"group_types": [], "dist_constraints": []}'
fi

cat > /tmp/extrude_constrained_profile_result.json << EOF
{
    "task_start": $TASK_START,
    "output_file_exists": $FILE_EXISTS,
    "output_file_is_new": $FILE_IS_NEW,
    "output_file_size": $FILE_SIZE,
    "parse_result": $PARSE_RESULT
}
EOF

echo "=== Export Complete ==="
