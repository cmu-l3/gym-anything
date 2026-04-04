#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Minimal Reproduction Result ==="

REPRO_DIR="/home/ga/workspace/bug-reproduction"

# Save file to ensure any open files are persisted
focus_vscode_window || true
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+shift+s" 2>/dev/null || true
sleep 2

# Export directory structure
if [ -d "$REPRO_DIR" ]; then
    echo "Exporting reproduction directory structure..."
    ls -la "$REPRO_DIR" > /tmp/repro_structure.txt 2>&1
    
    # Export individual files if they exist
    if [ -f "$REPRO_DIR/repro.py" ]; then
        cp "$REPRO_DIR/repro.py" /tmp/repro.py 2>/dev/null || true
        echo "✅ repro.py exported"
    else
        echo "⚠️ repro.py not found"
    fi
    
    if [ -f "$REPRO_DIR/README.md" ]; then
        cp "$REPRO_DIR/README.md" /tmp/repro_README.md 2>/dev/null || true
        echo "✅ README.md exported"
    else
        echo "⚠️ README.md not found"
    fi
    
    if [ -f "$REPRO_DIR/requirements.txt" ]; then
        cp "$REPRO_DIR/requirements.txt" /tmp/repro_requirements.txt 2>/dev/null || true
        echo "✅ requirements.txt exported"
    else
        echo "⚠️ requirements.txt not found"
    fi
    
    echo "Directory contents:"
    cat /tmp/repro_structure.txt
else
    echo "⚠️ Reproduction directory not found at $REPRO_DIR"
    echo "Directory does not exist" > /tmp/repro_structure.txt
fi

echo "✅ Export complete"
echo "Expected location: $REPRO_DIR"