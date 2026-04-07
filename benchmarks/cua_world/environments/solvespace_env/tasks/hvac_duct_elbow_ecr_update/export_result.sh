#!/bin/bash
echo "=== Exporting hvac_duct_elbow_ecr_update result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/hvac_duct_elbow_ecr_update_start_ts 2>/dev/null || echo "0")
SLVS_OUTPUT="/home/ga/Documents/SolveSpace/duct_elbow_updated.slvs"
DXF_OUTPUT="/home/ga/Documents/SolveSpace/duct_elbow_updated.dxf"

sleep 1
take_screenshot /tmp/hvac_duct_elbow_ecr_update_end.png

SLVS_EXISTS=false
SLVS_IS_NEW=false
SLVS_SIZE=0
if [ -f "$SLVS_OUTPUT" ]; then
    SLVS_EXISTS=true
    SLVS_MTIME=$(stat -c %Y "$SLVS_OUTPUT" 2>/dev/null || echo "0")
    SLVS_SIZE=$(stat -c %s "$SLVS_OUTPUT" 2>/dev/null || echo "0")
    if [ "$SLVS_MTIME" -gt "$TASK_START" ]; then
        SLVS_IS_NEW=true
    fi
fi

DXF_EXISTS=false
DXF_IS_NEW=false
if [ -f "$DXF_OUTPUT" ]; then
    DXF_EXISTS=true
    DXF_MTIME=$(stat -c %Y "$DXF_OUTPUT" 2>/dev/null || echo "0")
    if [ "$DXF_MTIME" -gt "$TASK_START" ]; then
        DXF_IS_NEW=true
    fi
fi

CONSTRAINT_JSON="[]"
if $SLVS_EXISTS; then
    CONSTRAINT_JSON=$(python3 << 'PYEOF'
import json
def parse_slvs_constraints(filepath):
    try:
        with open(filepath, 'rb') as f:
            content = f.read()
        parts = content.split(b'\n\n')
        constraints = []
        for part in parts:
            if b'AddConstraint' not in part:
                continue
            c = {}
            for line in part.decode('utf-8', errors='replace').strip().split('\n'):
                if '=' in line:
                    key, _, val = line.partition('=')
                    c[key.strip()] = val.strip()
            if 'Constraint.type' in c:
                try:
                    c['Constraint.type'] = int(c['Constraint.type'])
                except:
                    pass
                if 'Constraint.valA' in c:
                    try:
                        c['Constraint.valA'] = float(c['Constraint.valA'])
                    except:
                        pass
                constraints.append(c)
        return constraints
    except Exception:
        return []

constraints = parse_slvs_constraints('/home/ga/Documents/SolveSpace/duct_elbow_updated.slvs')
relevant = [{'type': c['Constraint.type'], 'valA': c.get('Constraint.valA', 0)}
            for c in constraints if c.get('Constraint.type') in (30, 90)]
print(json.dumps(relevant))
PYEOF
    )
fi

cat > /tmp/hvac_duct_elbow_ecr_update_result.json << EOF
{
    "task_start": $TASK_START,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_is_new": $SLVS_IS_NEW,
    "slvs_size": $SLVS_SIZE,
    "dxf_exists": $DXF_EXISTS,
    "dxf_is_new": $DXF_IS_NEW,
    "constraints": $CONSTRAINT_JSON
}
EOF

echo "Result JSON saved to /tmp/hvac_duct_elbow_ecr_update_result.json"
echo "=== Export Complete ==="
