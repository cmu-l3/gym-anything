#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Fix Timezone Display Bug Result ==="

WORKSPACE_DIR="/home/ga/workspace/appointment-booking"

# Focus VSCode and save all files
if pgrep -f "code" > /dev/null; then
    echo "Saving all files..."
    focus_vscode_window
    sleep 0.5
    
    # Save all files
    {
        safe_xdotool ga :1 key --delay 100 ctrl+shift+s
        sleep 1
        safe_xdotool ga :1 key --delay 100 ctrl+s
    } || {
        echo "⚠️ Failed to send save command; continuing"
    }
    
    sleep 1
fi

# Wait for files to be written
wait_for_file "$WORKSPACE_DIR/src/utils/dateHelpers.js" 3
wait_for_file "$WORKSPACE_DIR/src/components/AppointmentCard.js" 3

# Verify files exist and have content
if [ -f "$WORKSPACE_DIR/src/utils/dateHelpers.js" ]; then
    HELPERS_SIZE=$(stat -f%z "$WORKSPACE_DIR/src/utils/dateHelpers.js" 2>/dev/null || stat -c%s "$WORKSPACE_DIR/src/utils/dateHelpers.js" 2>/dev/null || echo "0")
    echo "✅ dateHelpers.js exists (${HELPERS_SIZE} bytes)"
else
    echo "⚠️ dateHelpers.js not found"
fi

if [ -f "$WORKSPACE_DIR/src/components/AppointmentCard.js" ]; then
    CARD_SIZE=$(stat -f%z "$WORKSPACE_DIR/src/components/AppointmentCard.js" 2>/dev/null || stat -c%s "$WORKSPACE_DIR/src/components/AppointmentCard.js" 2>/dev/null || echo "0")
    echo "✅ AppointmentCard.js exists (${CARD_SIZE} bytes)"
else
    echo "⚠️ AppointmentCard.js not found"
fi

echo "✅ Export complete"
echo "Modified files:"
echo "  - $WORKSPACE_DIR/src/utils/dateHelpers.js"
echo "  - $WORKSPACE_DIR/src/components/AppointmentCard.js"