#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Compare Implementations Task ==="

WORKSPACE_DIR="/home/ga/workspace"
PIPELINES_DIR="$WORKSPACE_DIR/pipelines"

# Create project structure
sudo -u ga mkdir -p "$PIPELINES_DIR"

# Copy implementation files from assets
ASSETS_DIR="/workspace/tasks/compare_implementations/assets"

if [ -f "$ASSETS_DIR/traditional_pipeline.py" ]; then
    sudo -u ga cp "$ASSETS_DIR/traditional_pipeline.py" "$PIPELINES_DIR/"
    echo "Copied traditional_pipeline.py"
else
    echo "⚠️ Warning: traditional_pipeline.py not found in assets"
fi

if [ -f "$ASSETS_DIR/functional_pipeline.py" ]; then
    sudo -u ga cp "$ASSETS_DIR/functional_pipeline.py" "$PIPELINES_DIR/"
    echo "Copied functional_pipeline.py"
else
    echo "⚠️ Warning: functional_pipeline.py not found in assets"
fi

# Create README with task instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Pipeline Comparison Task

## Objective
Compare two implementations of the same data processing pipeline:

1. **traditional_pipeline.py** - Loop-based imperative approach
2. **functional_pipeline.py** - Functional programming with optimizations

## Your Task
1. Open both files side-by-side in split editor view
   - Open traditional_pipeline.py
   - Use Ctrl+\ to split editor
   - Open functional_pipeline.py in the right pane
2. Compare the implementations visually
3. Identify the key optimization in the functional version
4. Create comparison_notes.txt in workspace root documenting the optimization

## Expected Optimization
The functional version includes a performance optimization not present in traditional version.
Look for caching or memoization techniques.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Remove any existing comparison_notes.txt from previous runs
rm -f "$WORKSPACE_DIR/comparison_notes.txt"

# Open VSCode with workspace
echo "Opening VSCode..."
cd "$WORKSPACE_DIR"
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Compare Implementations Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Open pipelines/traditional_pipeline.py"
echo "  2. Split editor with Ctrl+\\"
echo "  3. Open pipelines/functional_pipeline.py in right pane"
echo "  4. Compare implementations side-by-side"
echo "  5. Create comparison_notes.txt documenting the optimization"