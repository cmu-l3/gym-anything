#!/bin/bash
echo "=== Exporting annotate_and_export_panel result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/annotate_and_export_panel_start_ts 2>/dev/null || echo "0")
BASELINE=$(cat /tmp/annotate_and_export_panel_baseline_count 2>/dev/null || echo "0")
SLVS_OUT="/home/ga/Documents/SolveSpace/divider_annotated.slvs"
DXF_OUT="/home/ga/Documents/SolveSpace/divider_shop_drawing.dxf"

sleep 1
take_screenshot /tmp/annotate_and_export_panel_end.png

# Check .slvs output
SLVS_EXISTS=false
SLVS_IS_NEW=false
SLVS_SIZE=0
if [ -f "$SLVS_OUT" ]; then
    SLVS_EXISTS=true
    SLVS_MTIME=$(stat -c %Y "$SLVS_OUT" 2>/dev/null || echo "0")
    SLVS_SIZE=$(stat -c %s "$SLVS_OUT" 2>/dev/null || echo "0")
    [ "$SLVS_MTIME" -gt "$TASK_START" ] && SLVS_IS_NEW=true
fi

# Check DXF output
DXF_EXISTS=false
DXF_IS_NEW=false
DXF_SIZE=0
if [ -f "$DXF_OUT" ]; then
    DXF_EXISTS=true
    DXF_MTIME=$(stat -c %Y "$DXF_OUT" 2>/dev/null || echo "0")
    DXF_SIZE=$(stat -c %s "$DXF_OUT" 2>/dev/null || echo "0")
    [ "$DXF_MTIME" -gt "$TASK_START" ] && DXF_IS_NEW=true
fi

# Parse constraints from the saved .slvs file
CONSTRAINT_JSON="[]"
NEW_CONSTRAINT_COUNT=0
if $SLVS_EXISTS; then
    PARSE_OUT=$(python3 << 'PYEOF'
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

cs = parse_slvs_constraints('/home/ga/Documents/SolveSpace/divider_annotated.slvs')
relevant = [{'type': c['Constraint.type'], 'valA': c.get('Constraint.valA', 0)}
            for c in cs if c.get('Constraint.type') in (30, 90)]
print(json.dumps({'total_count': len(cs), 'dist_constraints': relevant}))
PYEOF
    )
    if [ -n "$PARSE_OUT" ]; then
        CONSTRAINT_JSON=$(echo "$PARSE_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d['dist_constraints']))")
        TOTAL_COUNT=$(echo "$PARSE_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['total_count'])")
        NEW_CONSTRAINT_COUNT=$((TOTAL_COUNT - BASELINE))
    fi
fi

# Check DXF validity (starts with DXF marker)
DXF_VALID=false
if $DXF_EXISTS; then
    DXF_HEADER=$(head -c 10 "$DXF_OUT" 2>/dev/null || echo "")
    if echo "$DXF_HEADER" | grep -q "0"; then
        DXF_VALID=true
    fi
fi

cat > /tmp/annotate_and_export_panel_result.json << EOF
{
    "task_start": $TASK_START,
    "baseline_constraint_count": $BASELINE,
    "new_constraint_count": $NEW_CONSTRAINT_COUNT,
    "slvs_exists": $SLVS_EXISTS,
    "slvs_is_new": $SLVS_IS_NEW,
    "slvs_size": $SLVS_SIZE,
    "dxf_exists": $DXF_EXISTS,
    "dxf_is_new": $DXF_IS_NEW,
    "dxf_size": $DXF_SIZE,
    "dxf_valid": $DXF_VALID,
    "dist_constraints": $CONSTRAINT_JSON
}
EOF

echo "=== Export Complete ==="
