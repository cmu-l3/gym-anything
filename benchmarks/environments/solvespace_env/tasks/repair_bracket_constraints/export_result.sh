#!/bin/bash
echo "=== Exporting repair_bracket_constraints result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/repair_bracket_constraints_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Documents/SolveSpace/bracket_constrained.slvs"

# Take final screenshot
sleep 1
take_screenshot /tmp/repair_bracket_constraints_end.png

# Check output file
FILE_EXISTS=false
FILE_IS_NEW=false
FILE_SIZE=0
if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
fi

# Parse the .slvs file for constraint info
CONSTRAINT_JSON="[]"
if $FILE_EXISTS; then
    CONSTRAINT_JSON=$(python3 << 'PYEOF'
import sys, json

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
    except Exception as e:
        return []

constraints = parse_slvs_constraints('/home/ga/Documents/SolveSpace/bracket_constrained.slvs')
# Only output distance/diameter constraints (types 30, 90)
relevant = [{'type': c['Constraint.type'], 'valA': c.get('Constraint.valA', 0)}
            for c in constraints if c.get('Constraint.type') in (30, 90)]
print(json.dumps(relevant))
PYEOF
    )
fi

cat > /tmp/repair_bracket_constraints_result.json << EOF
{
    "task_start": $TASK_START,
    "output_file_exists": $FILE_EXISTS,
    "output_file_is_new": $FILE_IS_NEW,
    "output_file_size": $FILE_SIZE,
    "constraints": $CONSTRAINT_JSON
}
EOF

echo "Result JSON saved to /tmp/repair_bracket_constraints_result.json"
echo "=== Export Complete ==="
