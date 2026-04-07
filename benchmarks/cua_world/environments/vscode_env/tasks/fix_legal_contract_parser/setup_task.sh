#!/bin/bash
set -e

# Source utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

echo "=== Setting up Fix Legal Contract Parser Task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/contract_parser"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"

# 1. Generate realistic SEC contract data text files
cat > "$WORKSPACE_DIR/data/contract_1.txt" << 'EOF'
This Agreement is made by and between Acme Corp and Beta LLC. This is another sentence. And another.
EOF

cat > "$WORKSPACE_DIR/data/contract_2.txt" << 'EOF'
This instrument is dated this 1st day of October, 2021 by and between the undersigned.
EOF

cat > "$WORKSPACE_DIR/data/contract_3.txt" << 'EOF'
This Agreement shall be governed by and construed in accordance with the laws of the State of New York.
EOF

cat > "$WORKSPACE_DIR/data/contract_4.txt" << 'EOF'
"Confidential Information" means all information disclosed by
One party to another that is marked confidential.
EOF

cat > "$WORKSPACE_DIR/data/contract_5.txt" << 'EOF'
Either party may invoke termination
for convenience with 30 days written notice to the other party.
EOF

# 2. Write the buggy extractor module
cat > "$WORKSPACE_DIR/contract_extractor.py" << 'PYEOF'
import re

def extract_parties(text):
    """Extract the parties entering into the agreement."""
    # BUG 1: Greedy match captures too much text
    match = re.search(r"This Agreement is made by and between (.*)\.", text)
    return match.group(1).strip() if match else None

def extract_date(text):
    """Extract the effective or signature date."""
    # BUG 2: Very strict date format, misses ordinal indicators and 'dated this X day of Y'
    match = re.search(r"dated as of ([A-Z][a-z]+\s+\d{1,2},\s+\d{4})", text)
    return match.group(1).strip() if match else None

def extract_governing_law(text):
    """Extract the state or jurisdiction governing the contract."""
    # BUG 3: Strict preceding text, fails on verbose legal phrasing like 'construed in accordance with'
    match = re.search(r"governed by the laws of ([A-Z][a-zA-Z\s]+)\.", text)
    return match.group(1).strip() if match else None

def extract_confidentiality(text):
    """Extract the definition of Confidential Information."""
    # BUG 4: Missing re.DOTALL (or equivalent), only gets the first line
    match = re.search(r'"Confidential Information"\s+means\s+(.*?)\.', text)
    return match.group(1).strip() if match else None

def extract_termination(text):
    """Check if the contract has a termination for convenience clause."""
    # BUG 5: Literal space, fails on line breaks
    match = re.search(r'termination for convenience', text, re.IGNORECASE)
    return bool(match)
PYEOF

# 3. Write the test suite (visible to agent)
cat > "$WORKSPACE_DIR/test_extractor.py" << 'PYEOF'
import pytest
from contract_extractor import *

def test_parties():
    with open("data/contract_1.txt", "r") as f:
        text = f.read()
    assert extract_parties(text) == "Acme Corp and Beta LLC"

def test_date():
    with open("data/contract_2.txt", "r") as f:
        text = f.read()
    res = extract_date(text)
    assert res is not None, "Date was not extracted"
    assert "October" in res and "2021" in res

def test_governing_law():
    with open("data/contract_3.txt", "r") as f:
        text = f.read()
    res = extract_governing_law(text)
    assert res is not None, "Governing law was not extracted"
    assert "New York" in res

def test_confidentiality():
    with open("data/contract_4.txt", "r") as f:
        text = f.read()
    res = extract_confidentiality(text)
    assert res is not None, "Confidentiality definition was not extracted"
    assert "marked confidential" in res

def test_termination():
    with open("data/contract_5.txt", "r") as f:
        text = f.read()
    assert extract_termination(text) is True
PYEOF

# Fix permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Ensure VSCode is running and focused on the workspace
if ! pgrep -f "code.*--ms-enable-electron" > /dev/null; then
    echo "Starting VS Code..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Try to use task_utils focus if available, otherwise fallback
if type focus_vscode_window &>/dev/null; then
    focus_vscode_window
else
    DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true
fi
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Open the target file explicitly
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/contract_extractor.py" 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="