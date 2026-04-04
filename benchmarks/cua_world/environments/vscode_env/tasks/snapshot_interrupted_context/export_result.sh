#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting Snapshot Interrupted Context Result ==="

PROJECT_PATH="/home/ga/workspace/project_alpha"
EXPORT_DIR="/tmp/task_export_snapshot"

# Create export directory
sudo rm -rf "$EXPORT_DIR" 2>/dev/null || true
mkdir -p "$EXPORT_DIR"

# Give VSCode time to save any auto-saved files
sleep 2

# Try to trigger a save in VSCode (in case agent didn't save)
echo "Attempting to save files..."
focus_vscode_window || true
su - ga -c "DISPLAY=:1 xdotool key --delay 200 ctrl+s" 2>/dev/null || true
sleep 1

# Export the modified payment processor
echo "Exporting payment_processor.py..."
if [ -f "$PROJECT_PATH/services/payment_processor.py" ]; then
    cp "$PROJECT_PATH/services/payment_processor.py" "$EXPORT_DIR/payment_processor.py"
    echo "✅ payment_processor.py exported"
else
    echo "⚠️ payment_processor.py not found"
    echo "" > "$EXPORT_DIR/payment_processor.py"
fi

# Export debug notes if created
echo "Exporting _DEBUG_NOTES.md..."
if [ -f "$PROJECT_PATH/_DEBUG_NOTES.md" ]; then
    cp "$PROJECT_PATH/_DEBUG_NOTES.md" "$EXPORT_DIR/_DEBUG_NOTES.md"
    echo "✅ _DEBUG_NOTES.md exported"
else
    echo "⚠️ _DEBUG_NOTES.md not found"
    echo "" > "$EXPORT_DIR/_DEBUG_NOTES.md"
fi

# Export workspace file if saved
echo "Exporting workspace file..."
if [ -f "$PROJECT_PATH/project_alpha_debug_session.code-workspace" ]; then
    cp "$PROJECT_PATH/project_alpha_debug_session.code-workspace" "$EXPORT_DIR/workspace.code-workspace"
    echo "✅ workspace file exported"
else
    echo "⚠️ workspace file not found"
    echo "{}" > "$EXPORT_DIR/workspace.code-workspace"
fi

# Also check alternate locations for workspace file
if [ ! -s "$EXPORT_DIR/workspace.code-workspace" ]; then
    for ws_file in "$PROJECT_PATH"/*.code-workspace; do
        if [ -f "$ws_file" ]; then
            cp "$ws_file" "$EXPORT_DIR/workspace.code-workspace"
            echo "✅ Found workspace file: $(basename $ws_file)"
            break
        fi
    done
fi

# Export test file in case agent added comments there
echo "Exporting test_payment.py..."
if [ -f "$PROJECT_PATH/tests/test_payment.py" ]; then
    cp "$PROJECT_PATH/tests/test_payment.py" "$EXPORT_DIR/test_payment.py"
fi

# List exported files
echo ""
echo "📦 Exported files:"
ls -lh "$EXPORT_DIR/" 2>/dev/null || echo "Export directory empty"

echo ""
echo "✅ Export complete: $EXPORT_DIR"