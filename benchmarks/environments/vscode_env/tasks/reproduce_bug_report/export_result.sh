#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Bug Reproduction Result ==="

WORKSPACE_DIR="/home/ga/workspace/bug_repro"

# Save all open files
focus_vscode_window
{
    safe_xdotool ga :1 key --delay 200 ctrl+shift+s
} || {
    echo "⚠️ Failed to save all files; continuing"
}

sleep 1

# Copy test CSV files to /tmp (try multiple possible names)
CSV_FOUND=false
for csv_file in test_bug_input.csv test_input.csv bug_test.csv test.csv bug_input.csv; do
    if [ -f "$WORKSPACE_DIR/$csv_file" ]; then
        cp "$WORKSPACE_DIR/$csv_file" "/tmp/test_csv_file.csv"
        echo "✓ Exported $csv_file"
        CSV_FOUND=true
        break
    fi
done

if [ "$CSV_FOUND" = false ]; then
    echo "⚠️ No test CSV file found"
    echo "" > /tmp/test_csv_file.csv
fi

# Copy reproduction document to /tmp (try multiple possible names)
DOC_FOUND=false
for doc_file in REPRODUCTION.md README.md reproduction.md REPRO.md bug_reproduction.md BUG_REPRO.md; do
    if [ -f "$WORKSPACE_DIR/$doc_file" ]; then
        cp "$WORKSPACE_DIR/$doc_file" "/tmp/reproduction_doc.md"
        echo "✓ Exported $doc_file"
        DOC_FOUND=true
        break
    fi
done

if [ "$DOC_FOUND" = false ]; then
    echo "⚠️ No reproduction document found"
    echo "" > /tmp/reproduction_doc.md
fi

echo "✅ Export complete"
echo "Workspace: $WORKSPACE_DIR"