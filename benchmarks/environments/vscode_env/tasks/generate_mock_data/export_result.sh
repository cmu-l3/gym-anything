#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Generate Mock Data Result ==="

WORKSPACE_DIR="/home/ga/workspace/ecommerce-mocks"
OUTPUT_DIR="/tmp/mock_data_task"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Try to save any open files in VSCode
focus_vscode_window || true
{
    safe_xdotool ga :1 key --delay 200 ctrl+s
    sleep 1
} || {
    echo "⚠️ Could not send save command to VSCode"
}

# Wait a moment for files to be written
sleep 2

# Find and copy TypeScript/JavaScript files
echo "Searching for generated files..."
file_found=false

# Check for common file names
for filename in "mockDataGenerator.ts" "mockDataGenerator.js" "generator.ts" "generator.js" "mockData.ts" "mockData.js" "dataGenerator.ts" "dataGenerator.js"; do
    if [ -f "$WORKSPACE_DIR/$filename" ]; then
        echo "Found: $filename"
        cp "$WORKSPACE_DIR/$filename" "$OUTPUT_DIR/" 2>/dev/null || true
        file_found=true
    fi
done

# If no specific files found, copy all .ts and .js files (excluding node_modules)
if [ "$file_found" = false ]; then
    echo "No specific files found, copying all .ts and .js files..."
    find "$WORKSPACE_DIR" -maxdepth 1 -type f \( -name "*.ts" -o -name "*.js" \) ! -name "*.config.js" ! -name "*.config.ts" -exec cp {} "$OUTPUT_DIR/" \; 2>/dev/null || true
fi

# List what was exported
echo ""
echo "Files exported to $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR" 2>/dev/null || echo "No files exported"

# Export file list for verifier
ls -la "$WORKSPACE_DIR" > "$OUTPUT_DIR/workspace_listing.txt" 2>&1 || echo "Empty workspace" > "$OUTPUT_DIR/workspace_listing.txt"

echo "✅ Export complete"