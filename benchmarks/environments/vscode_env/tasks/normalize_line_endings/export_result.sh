#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Normalize Line Endings Result ==="

REPO_PATH="/home/ga/workspace/payment-service"
OUTPUT_DIR="/tmp/line_endings_output"

sudo -u ga mkdir -p "$OUTPUT_DIR"

# Focus VSCode and try to save any open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
    sleep 1
} || {
    echo "⚠️ Failed to save all files; continuing"
}

# Export workspace settings if exists
if [ -d "$REPO_PATH/.vscode" ]; then
    echo "Exporting .vscode directory..."
    sudo -u ga cp -r "$REPO_PATH/.vscode" "$OUTPUT_DIR/" 2>/dev/null || true
fi

# Export .gitattributes if exists
if [ -f "$REPO_PATH/.gitattributes" ]; then
    echo "Exporting .gitattributes..."
    sudo -u ga cp "$REPO_PATH/.gitattributes" "$OUTPUT_DIR/" 2>/dev/null || true
fi

# Export git status
cd "$REPO_PATH"
echo "Exporting git status..."
sudo -u ga git status --porcelain > "$OUTPUT_DIR/git_status.txt" 2>&1 || echo "" > "$OUTPUT_DIR/git_status.txt"
sudo -u ga git status > "$OUTPUT_DIR/git_status_full.txt" 2>&1 || true

# Check line endings of critical files using file command
for filepath in "src/api.py" "src/models.py" "src/utils.js" "tests/test_api.py" "scripts/deploy.sh" "docs/README.md" "config/settings.json"; do
    if [ -f "$REPO_PATH/$filepath" ]; then
        filename=$(basename "$filepath")
        file "$REPO_PATH/$filepath" > "$OUTPUT_DIR/file_type_${filename}.txt" 2>&1 || true
        
        # Also check with grep for CRLF
        if grep -q $'\r' "$REPO_PATH/$filepath" 2>/dev/null; then
            echo "HAS_CRLF" > "$OUTPUT_DIR/line_ending_${filename}.txt"
        else
            echo "NO_CRLF" > "$OUTPUT_DIR/line_ending_${filename}.txt"
        fi
    fi
done

# Export actual file contents for verification
sudo -u ga mkdir -p "$OUTPUT_DIR/files"
for filepath in "src/api.py" "src/models.py" "src/utils.js" "scripts/deploy.sh"; do
    if [ -f "$REPO_PATH/$filepath" ]; then
        sudo -u ga cp "$REPO_PATH/$filepath" "$OUTPUT_DIR/files/" 2>/dev/null || true
    fi
done

echo "✅ Export complete"
echo "Repository: $REPO_PATH"
echo "Output: $OUTPUT_DIR"