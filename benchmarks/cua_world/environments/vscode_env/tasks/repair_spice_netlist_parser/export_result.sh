#!/bin/bash
set -e

echo "=== Exporting SPICE Netlist Parser Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Force VSCode to save all files
DISPLAY=:1 xdotool key --delay 100 ctrl+shift+s 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key --delay 100 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# Run an isolated Python evaluation script inside the container
# This executes against the agent's edited code to see if the bugs are fixed.
cat > /tmp/eval_spice.py << 'EOF'
import sys
import json
import traceback

# Point to the agent's workspace
sys.path.insert(0, "/home/ga/workspace/spice_parser")

results = {
    "bug1_values": False,
    "bug2_continuation": False,
    "bug3_comments": False,
    "bug4_nodes": False,
    "bug5_subckt": False,
    "errors": []
}

try:
    # --- Check 1: Values ---
    from spice_parser.values import parse_value
    try:
        v1 = parse_value("1M")
        v2 = parse_value("1m")
        v3 = parse_value("1MEG")
        if v1 == 0.001 and v2 == 0.001 and v3 == 1000000.0:
            results["bug1_values"] = True
    except Exception as e:
        results["errors"].append(f"Values Error: {str(e)}")

    # --- Check 2 & 3: Lexer ---
    from spice_parser.lexer import tokenize
    try:
        # Check 2: Continuation lines
        res_cont = tokenize(["R1 1 2", "+ 1k"])
        if len(res_cont) == 1 and res_cont[0].replace(" ", "") == "R1121k":
            results["bug2_continuation"] = True
            
        # Check 3: Comments and math
        res_comm = tokenize(["* full comment", "R1 1 2 {2*3} ; inline"])
        if len(res_comm) == 1 and "2*3" in res_comm[0] and "inline" not in res_comm[0]:
            results["bug3_comments"] = True
    except Exception as e:
        results["errors"].append(f"Lexer Error: {str(e)}")

    # --- Check 4: Nodes ---
    from spice_parser.nodes import NodeManager
    try:
        nm = NodeManager()
        n1 = nm.get_node("GND")
        n2 = nm.get_node("0")
        n3 = nm.get_node("gnd")
        if n1 == n2 == n3:
            results["bug4_nodes"] = True
    except Exception as e:
        results["errors"].append(f"Nodes Error: {str(e)}")

    # --- Check 5: Subckt ---
    from spice_parser.subckt import SubcircuitInstantiator, SubcircuitDef
    try:
        inst = SubcircuitInstantiator()
        d = SubcircuitDef("LM358", ["A"])
        n1 = inst.instantiate("X1", d)
        n2 = inst.instantiate("X2", d)
        
        # Ensure it uses instance names, not definition names
        if n1 and n2 and "X1" in n1[0] and "X2" in n2[0] and n1[0] != n2[0]:
            results["bug5_subckt"] = True
    except Exception as e:
        results["errors"].append(f"Subckt Error: {str(e)}")

except Exception as global_e:
    results["errors"].append(f"Global Error: {str(global_e)}")

# Get file modification info to ensure work was actually done
import os
mtimes = {}
for f in ["values.py", "lexer.py", "nodes.py", "subckt.py"]:
    path = os.path.join("/home/ga/workspace/spice_parser/spice_parser", f)
    if os.path.exists(path):
        mtimes[f] = os.path.getmtime(path)
    else:
        mtimes[f] = 0

results["mtimes"] = mtimes

with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=2)

EOF

python3 /tmp/eval_spice.py

# Add metadata
TEMP_JSON=$(mktemp)
jq --arg start "$TASK_START" --arg end "$TASK_END" \
   '. + {task_start: ($start|tonumber), task_end: ($end|tonumber)}' \
   /tmp/task_result.json > "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json