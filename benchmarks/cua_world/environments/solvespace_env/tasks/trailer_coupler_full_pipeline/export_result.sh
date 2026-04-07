#!/bin/bash
echo "=== Exporting trailer_coupler_full_pipeline result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/trailer_coupler_full_pipeline_start_ts 2>/dev/null || echo "0")
SLVS_OUTPUT="/home/ga/Documents/SolveSpace/coupler_beam.slvs"
DXF_OUTPUT="/home/ga/Documents/SolveSpace/coupler_beam.dxf"

sleep 1
take_screenshot /tmp/trailer_coupler_full_pipeline_end.png

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

# Parse constraints AND groups from .slvs
CONSTRAINT_JSON="[]"
HAS_EXTRUDE_GROUP=false

if $SLVS_EXISTS; then
    PARSE_RESULT=$(python3 << 'PYEOF'
import json

def parse_slvs(filepath):
    try:
        with open(filepath, 'rb') as f:
            content = f.read()
        parts = content.split(b'\n\n')
        constraints = []
        has_extrude = False
        for part in parts:
            text = part.decode('utf-8', errors='replace').strip()
            if 'AddConstraint' in text:
                c = {}
                for line in text.split('\n'):
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
            if 'AddGroup' in text:
                gtype = None
                for line in text.split('\n'):
                    if '=' in line:
                        key, _, val = line.partition('=')
                        if key.strip() == 'Group.type':
                            try:
                                gtype = int(val.strip())
                            except:
                                pass
                if gtype == 5100:  # extrude group
                    has_extrude = True
        relevant = [{'type': c['Constraint.type'], 'valA': c.get('Constraint.valA', 0)}
                    for c in constraints if c.get('Constraint.type') in (30, 90)]
        print(json.dumps({'constraints': relevant, 'has_extrude': has_extrude}))
    except Exception as e:
        print(json.dumps({'constraints': [], 'has_extrude': False}))

parse_slvs('/home/ga/Documents/SolveSpace/coupler_beam.slvs')
PYEOF
    )
    CONSTRAINT_JSON=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d['constraints']))" 2>/dev/null || echo "[]")
    HAS_EXTRUDE=$(echo "$PARSE_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(str(d['has_extrude']).lower())" 2>/dev/null || echo "false")
fi

cat > /tmp/trailer_coupler_full_pipeline_result.json << EOF
{
    "task_start": $TASK_START,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_is_new": $SLVS_IS_NEW,
    "slvs_size": $SLVS_SIZE,
    "dxf_exists": $DXF_EXISTS,
    "dxf_is_new": $DXF_IS_NEW,
    "has_extrude_group": $HAS_EXTRUDE,
    "constraints": $CONSTRAINT_JSON
}
EOF

echo "Result JSON saved to /tmp/trailer_coupler_full_pipeline_result.json"
echo "=== Export Complete ==="
