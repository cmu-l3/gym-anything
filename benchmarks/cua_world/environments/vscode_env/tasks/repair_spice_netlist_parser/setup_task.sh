#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair SPICE Netlist Parser Task ==="

# Record start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/spice_parser"
sudo -u ga mkdir -p "$WORKSPACE_DIR/spice_parser"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"

# ──────────────────────────────────────────────────────────
# Create the buggy source code files
# ──────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/spice_parser/__init__.py" << 'EOF'
# SPICE Parser package
EOF

cat > "$WORKSPACE_DIR/spice_parser/values.py" << 'EOF'
import re

def parse_value(val_str):
    """
    Parses a SPICE value string into a float.
    SPICE is case-insensitive.
    Standard suffix multipliers:
    MEG = 1e6, M = 1e-3, K = 1e3, U = 1e-6, N = 1e-9, P = 1e-12
    """
    val_str = str(val_str).strip().upper()
    if not val_str:
        return 0.0
        
    # BUG 1: Naive replacement treats M as mega instead of milli
    # and processes MEG first, but then M also matches...
    val_str = val_str.replace('MEG', 'e6').replace('M', 'e6')
    val_str = val_str.replace('K', 'e3').replace('U', 'e-6')
    val_str = val_str.replace('N', 'e-9').replace('P', 'e-12')
    
    # Strip any trailing units (like F, Ohm, H)
    val_str = re.sub(r'[A-Z]+$', '', val_str)
    
    try:
        return float(val_str)
    except ValueError:
        return 0.0
EOF

cat > "$WORKSPACE_DIR/spice_parser/lexer.py" << 'EOF'
def tokenize(lines):
    """
    Reads a list of raw SPICE lines, strips comments, and 
    handles continuation lines (lines starting with '+').
    """
    statements = []
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # BUG 3: Stripping EVERYTHING after '*' destroys inline math
        # SPICE rule: '*' is a comment ONLY if it is the first non-whitespace character.
        # Inline comments use ';'
        if '*' in line:
            line = line.split('*')[0].strip()
            
        if not line:
            continue
            
        # BUG 2: Continuation lines start with '+', they should be appended 
        # to the previous statement instead of being treated as new statements.
        statements.append(line)
        
    return statements
EOF

cat > "$WORKSPACE_DIR/spice_parser/nodes.py" << 'EOF'
class NodeManager:
    """Manages circuit nodes to build the adjacency matrix."""
    def __init__(self):
        self.nodes = {}
        self.next_id = 0
        
    def get_node(self, name):
        """
        Returns a unique ID for a given node name.
        """
        # BUG 4: SPICE treats '0', 'GND', 'gnd' as the exact same global ground node.
        # This implementation treats them as distinct string nodes.
        if name not in self.nodes:
            self.nodes[name] = self.next_id
            self.next_id += 1
            
        return self.nodes[name]
EOF

cat > "$WORKSPACE_DIR/spice_parser/subckt.py" << 'EOF'
class SubcircuitDef:
    def __init__(self, name, internal_nodes):
        self.name = name
        self.internal_nodes = internal_nodes

class SubcircuitInstantiator:
    """Handles expanding a subcircuit definition into the main netlist."""
    
    def instantiate(self, inst_name, subckt_def):
        """
        Expands the internal nodes of a subcircuit to prevent collisions.
        Returns a list of namespaced internal nodes.
        """
        # BUG 5: Internal nodes are prefixed with the definition name
        # If we have two LM358 op-amps (X1 and X2), they will short circuit 
        # because they'll both use 'LM358_nodeA' instead of 'X1_nodeA' and 'X2_nodeA'.
        prefix = subckt_def.name
        
        mapped_nodes = []
        for n in subckt_def.internal_nodes:
            mapped_nodes.append(f"{prefix}_{n}")
            
        return mapped_nodes
EOF

# ──────────────────────────────────────────────────────────
# Create the test suite for the user
# ──────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/tests/test_parser.py" << 'EOF'
import pytest
from spice_parser.values import parse_value
from spice_parser.lexer import tokenize
from spice_parser.nodes import NodeManager
from spice_parser.subckt import SubcircuitDef, SubcircuitInstantiator

def test_values_scale_factors():
    # 'MEG' or 'meg' is 10^6. 'M' or 'm' is 10^-3 (milli)
    assert parse_value("1MEG") == 1000000.0
    assert parse_value("1M") == 0.001
    assert parse_value("1m") == 0.001
    assert parse_value("10kOhm") == 10000.0

def test_lexer_continuation():
    # '+' denotes a continuation line in SPICE
    lines = ["R1 1 2", "+ 1k"]
    res = tokenize(lines)
    assert res == ["R1 1 2 1k"]

def test_lexer_comments():
    # '*' is a comment only at the start. ';' is an inline comment.
    lines = [
        "* This is a full line comment", 
        "R1 1 2 {2*3} ; This is an inline comment"
    ]
    res = tokenize(lines)
    assert len(res) == 1
    assert "2*3" in res[0]
    assert "inline" not in res[0]

def test_node_ground_equivalence():
    # Node 0 and GND are electrically identical
    nm = NodeManager()
    assert nm.get_node("GND") == nm.get_node("0")
    assert nm.get_node("gnd") == nm.get_node("0")

def test_subcircuit_namespacing():
    # Internal nodes must be scoped to the *instance*, not the *definition*
    inst = SubcircuitInstantiator()
    d = SubcircuitDef("LM358", ["A", "B"])
    
    nodes_x1 = inst.instantiate("X1", d)
    nodes_x2 = inst.instantiate("X2", d)
    
    assert nodes_x1[0] == "X1_A"
    assert nodes_x2[0] == "X2_A"
    assert set(nodes_x1).isdisjoint(set(nodes_x2))
EOF

# Set ownership
chown -R ga:ga "$WORKSPACE_DIR"

# Ensure VSCode is available and configured
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    echo "Starting VSCode..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Wait for window and maximize
for i in {1..30}; do
    if wmctrl -l | grep -i "Visual Studio Code"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Give VSCode time to stabilize
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="