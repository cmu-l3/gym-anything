#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Create React Snippet Result ==="

# Give time for any unsaved changes to be written
sleep 2

# Try to save any open files in VSCode
{
    focus_vscode_window
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Could not focus VSCode; continuing export"
}

# Export all possible snippet file locations
SNIPPETS_DIR="/home/ga/.config/Code/User/snippets"

# Create export directory structure
EXPORT_DIR="/tmp/snippet_export"
mkdir -p "$EXPORT_DIR"

# Export directory listing
echo "Exporting snippets directory listing..."
ls -la "$SNIPPETS_DIR" > "$EXPORT_DIR/snippets_dir_list.txt" 2>&1 || echo "Snippets directory not found" > "$EXPORT_DIR/snippets_dir_list.txt"

# Copy all potential snippet files
for snippet_file in \
    "$SNIPPETS_DIR/javascriptreact.json" \
    "$SNIPPETS_DIR/typescriptreact.json" \
    "$SNIPPETS_DIR/javascript.json" \
    "$SNIPPETS_DIR/typescript.json" \
    "$SNIPPETS_DIR/react.json"; do
    
    if [ -f "$snippet_file" ]; then
        filename=$(basename "$snippet_file")
        cp "$snippet_file" "$EXPORT_DIR/$filename"
        echo "✅ Exported: $filename"
        # Also show content for debugging
        echo "Content of $filename:" >> "$EXPORT_DIR/all_snippets_content.txt"
        cat "$snippet_file" >> "$EXPORT_DIR/all_snippets_content.txt" 2>&1
        echo "---" >> "$EXPORT_DIR/all_snippets_content.txt"
    fi
done

# List what was exported
echo "Exported files:"
ls -la "$EXPORT_DIR"

# Also export the test component file in case user tried testing the snippet
TEST_COMPONENT="/home/ga/workspace/react-app/src/components/NewComponent.tsx"
if [ -f "$TEST_COMPONENT" ]; then
    cp "$TEST_COMPONENT" "$EXPORT_DIR/test_component.tsx"
    echo "✅ Exported test component"
fi

echo "✅ Export complete"
echo "Export directory: $EXPORT_DIR"