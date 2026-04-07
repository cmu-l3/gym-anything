#!/bin/bash
echo "=== Exporting extract_section_to_document results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Identify Project Path
# We match the path used in setup_task.sh
PROJECT_PATH="/home/ga/Documents/ReqView/extract_section_project"
RESULT_DIR="/tmp/task_export"

rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"

# 3. Export Project Files for Verification
if [ -d "$PROJECT_PATH" ]; then
    echo "Exporting project files from $PROJECT_PATH..."
    cp "$PROJECT_PATH/project.json" "$RESULT_DIR/" 2>/dev/null || true
    if [ -d "$PROJECT_PATH/documents" ]; then
        cp -r "$PROJECT_PATH/documents" "$RESULT_DIR/"
    fi
else
    echo "WARNING: Project directory not found at $PROJECT_PATH"
fi

# 4. Record Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 5. Create Metadata JSON
cat > "$RESULT_DIR/metadata.json" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_found": $([ -d "$PROJECT_PATH" ] && echo "true" || echo "false")
}
EOF

# 6. Bundle into a single result file for the verifier to pull
# We'll use a tarball to preserve directory structure of the export
cd /tmp
tar -czf task_result.tar.gz task_export

# Clean up
rm -rf "$RESULT_DIR"

echo "Export ready at /tmp/task_result.tar.gz"
echo "=== Export complete ==="