#!/bin/bash
echo "=== Exporting exhaust_port_gasket_template result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/exhaust_port_gasket_start_ts 2>/dev/null || echo "0")
SLVS_OUTPUT="/home/ga/Documents/SolveSpace/exhaust_gasket.slvs"
DXF_OUTPUT="/home/ga/Documents/SolveSpace/exhaust_gasket.dxf"

sleep 1
take_screenshot /tmp/exhaust_port_gasket_end.png

# --- Check .slvs file ---
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

# --- Check .dxf file ---
DXF_EXISTS=false
DXF_IS_NEW=false
if [ -f "$DXF_OUTPUT" ]; then
    DXF_EXISTS=true
    DXF_MTIME=$(stat -c %Y "$DXF_OUTPUT" 2>/dev/null || echo "0")
    if [ "$DXF_MTIME" -gt "$TASK_START" ]; then
        DXF_IS_NEW=true
    fi
fi

# --- Parse .slvs for entity counts, constraints, and groups ---
PARSE_JSON="{}"
if $SLVS_EXISTS; then
    PARSE_JSON=$(python3 << 'PYEOF'
import json

def parse_slvs(filepath):
    try:
        with open(filepath, 'rb') as f:
            content = f.read()
        text = content.decode('utf-8', errors='replace')
        parts = text.split('\n\n')

        constraints = []
        has_extrude = False
        line_count = 0
        circle_count = 0
        arc_count = 0
        param_vals = []

        for part in parts:
            block = part.strip()

            # Count entity types via Request.type
            if 'AddRequest' in block:
                for line in block.split('\n'):
                    if line.strip().startswith('Request.type='):
                        rtype = line.strip().split('=')[1]
                        if rtype == '200':
                            line_count += 1
                        elif rtype == '400':
                            circle_count += 1
                        elif rtype in ('300', '500', '600'):
                            arc_count += 1

            # Collect parameter values
            if 'AddParam' in block:
                for line in block.split('\n'):
                    if line.strip().startswith('Param.val='):
                        try:
                            val = float(line.strip().split('=')[1])
                            param_vals.append(val)
                        except:
                            pass

            # Parse constraints
            if 'AddConstraint' in block:
                c = {}
                for line in block.split('\n'):
                    if '=' in line:
                        key, _, val = line.partition('=')
                        c[key.strip()] = val.strip()
                ctype = None
                cval = None
                if 'Constraint.type' in c:
                    try:
                        ctype = int(c['Constraint.type'])
                    except:
                        pass
                if 'Constraint.valA' in c:
                    try:
                        cval = float(c['Constraint.valA'])
                    except:
                        pass
                if ctype is not None:
                    constraints.append({'type': ctype, 'valA': cval})

            # Check for extrude group
            if 'AddGroup' in block:
                for line in block.split('\n'):
                    if line.strip().startswith('Group.type='):
                        try:
                            gtype = int(line.strip().split('=')[1])
                            if gtype == 5100:
                                has_extrude = True
                        except:
                            pass

        # Also count arc entities (Entity.type=12000, 14000, 20000)
        arc_entity_count = 0
        for part in parts:
            block = part.strip()
            if 'AddEntity' in block:
                for line in block.split('\n'):
                    if line.strip().startswith('Entity.type='):
                        etype = line.strip().split('=')[1]
                        if etype in ('12000', '13000', '14000', '20000', '20001'):
                            arc_entity_count += 1

        print(json.dumps({
            'constraints': constraints,
            'has_extrude': has_extrude,
            'line_requests': line_count,
            'circle_requests': circle_count,
            'arc_requests': arc_count,
            'arc_entities': arc_entity_count,
            'param_vals': param_vals
        }))
    except Exception as e:
        print(json.dumps({
            'constraints': [],
            'has_extrude': False,
            'line_requests': 0,
            'circle_requests': 0,
            'arc_requests': 0,
            'arc_entities': 0,
            'param_vals': [],
            'parse_error': str(e)
        }))

parse_slvs('/home/ga/Documents/SolveSpace/exhaust_gasket.slvs')
PYEOF
    )
fi

# --- Assemble result JSON ---
RESULT_FILE="/tmp/exhaust_port_gasket_result.json"
TEMP_FILE=$(mktemp)

cat > "$TEMP_FILE" << EOF
{
    "task_start": $TASK_START,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_is_new": $SLVS_IS_NEW,
    "slvs_size": $SLVS_SIZE,
    "dxf_exists": $DXF_EXISTS,
    "dxf_is_new": $DXF_IS_NEW,
    "app_was_running": $(is_solvespace_running && echo true || echo false),
    "parse": $PARSE_JSON
}
EOF

rm -f "$RESULT_FILE"
cp "$TEMP_FILE" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_FILE"

echo "Result JSON saved to $RESULT_FILE"
echo "=== Export Complete ==="
