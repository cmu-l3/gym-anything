#!/bin/bash
# Setup for backup_database task
# IMPORTANT: This script ensures Azure Data Studio is running and connected
# to SQL Server BEFORE the task starts, so the agent can focus on the actual task.
echo "=== Setting up backup_database task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Remove any existing backup file
echo "Cleaning up any existing backup..."
docker exec mssql-server rm -f /backup/AdventureWorks2022_backup.bak 2>/dev/null || true

# Record initial state
echo "Recording initial state..."

# Get database size for reference
DB_SIZE=$(mssql_query "
    SELECT CAST(SUM(size) * 8.0 / 1024 AS INT) AS SizeMB
    FROM sys.database_files
" | tr -d ' \r\n')
echo "Database size: ${DB_SIZE}MB" > /tmp/initial_state.txt

# Record timestamp
echo "Setup timestamp: $(date -Iseconds)" >> /tmp/initial_state.txt

# List existing backups
EXISTING_BACKUPS=$(docker exec mssql-server ls -la /backup/ 2>/dev/null | grep -c ".bak" || echo "0")
echo "Existing backup files: $EXISTING_BACKUPS" >> /tmp/initial_state.txt

echo "Initial state:"
cat /tmp/initial_state.txt

# ============================================================
# CRITICAL: Ensure Azure Data Studio is running and connected
# ============================================================

echo "Ensuring Azure Data Studio is running and connected..."

# Check if Azure Data Studio is already running
ADS_RUNNING=false
if pgrep -f "azuredatastudio" > /dev/null 2>&1; then
    ADS_RUNNING=true
    echo "Azure Data Studio is already running"
fi

# Launch Azure Data Studio if not running
if [ "$ADS_RUNNING" = false ]; then
    echo "Launching Azure Data Studio..."
    ADS_CMD="/snap/bin/azuredatastudio"
    if [ ! -x "$ADS_CMD" ]; then
        ADS_CMD="azuredatastudio"
    fi
    su - ga -c "DISPLAY=:1 $ADS_CMD > /tmp/azuredatastudio_task.log 2>&1 &"

    # Wait for Azure Data Studio window to appear
    echo "Waiting for Azure Data Studio window..."
    for i in $(seq 1 30); do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "azure\|data studio"; then
            echo "Azure Data Studio window detected after ${i}s"
            break
        fi
        sleep 1
    done
fi

# Give ADS time to fully initialize
sleep 5

# Bring Azure Data Studio window to foreground and maximize
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure\|data studio" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    echo "Azure Data Studio window activated and maximized"
fi

sleep 2

# ============================================================
# Handle startup dialogs (OS keyring, Welcome screen, etc.)
# ============================================================
echo "Dismissing any startup dialogs..."

# Dismiss OS keyring dialog if present - click "Use weaker encryption" button
DISPLAY=:1 xdotool key Tab Tab Return
sleep 1

# Dismiss Preview features dialog - click "No" button (bottom right)
# Coordinates from VLM: 1253,677 at 1280x720 scale -> 1879,1015 at 1920x1080
DISPLAY=:1 xdotool mousemove 1879 1015 click 1
sleep 1

# Press Escape multiple times to ensure all dialogs are closed
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool key Escape
sleep 0.5

# Click on the main editor area to ensure focus
DISPLAY=:1 xdotool mousemove 960 540 click 1
sleep 0.5

# ============================================================
# Connect to SQL Server using Command Palette -> New Connection
# This is more reliable than clicking toolbar buttons
# ============================================================

echo "Establishing SQL Server connection via Command Palette..."

# Open Command Palette with F1
DISPLAY=:1 xdotool key F1
sleep 1

# Type "new connection" to find the command
DISPLAY=:1 xdotool type 'new connection'
sleep 1

# Press Enter to select "New Connection"
DISPLAY=:1 xdotool key Return
sleep 2

# The Connection panel should now be visible on the right side
# Fill in the connection fields by clicking and typing
# Coordinates verified by VLM at 1280x720 -> scaled to 1920x1080:
# Server: 1160,460 -> 1740,690
# User name: 1160,503 -> 1740,755
# Password: 1160,523 -> 1740,785
# Trust server cert: 1160,603 -> 1740,905
# Connect button: 1180,699 -> 1770,1049

echo "Filling connection details..."
# Click on Server field and type localhost
DISPLAY=:1 xdotool mousemove 1740 690 click 1
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a
DISPLAY=:1 xdotool type 'localhost'
sleep 0.3

# Click on User name field
DISPLAY=:1 xdotool mousemove 1740 755 click 1
sleep 0.3
DISPLAY=:1 xdotool type 'sa'
sleep 0.3

# Click on Password field
DISPLAY=:1 xdotool mousemove 1740 785 click 1
sleep 0.3
DISPLAY=:1 xdotool type 'GymAnything#2024'
sleep 0.3

# Click on Trust server certificate dropdown and change to True
DISPLAY=:1 xdotool mousemove 1740 905 click 1
sleep 0.5
# Press 't' to select True option, then Enter to confirm
DISPLAY=:1 xdotool key t Return
sleep 0.5

# Click the Connect button in the Connection panel
echo "Connecting to SQL Server..."
DISPLAY=:1 xdotool mousemove 1770 1049 click 1
sleep 5

# Wait for connection to establish (keep master database for backup operations)
# When connected, title shows "localhost - Azure Data Studio"
echo "Waiting for connection to establish..."
CONNECTION_ESTABLISHED=false
for i in $(seq 1 15); do
    TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure" | head -1)
    # Check for "localhost" in title (indicates connection)
    if echo "$TITLE" | grep -qi "localhost.*Azure"; then
        CONNECTION_ESTABLISHED=true
        echo "Connection established after ${i}s"
        echo "Window title: $TITLE"
        break
    fi
    # If still not connected after 8s, try pressing Enter again
    if [ "$i" -eq 8 ]; then
        echo "Retrying connection..."
        DISPLAY=:1 xdotool key Return
    fi
    sleep 1
done

# CRITICAL VERIFICATION: Ensure connection was established
if [ "$CONNECTION_ESTABLISHED" = "false" ]; then
    echo "ERROR: Connection not established after 15 seconds!"
    echo "Attempting full retry of connection sequence..."

    # Retry: Open Command Palette and try again
    DISPLAY=:1 xdotool key Escape
    sleep 0.5
    DISPLAY=:1 xdotool key F1
    sleep 1
    DISPLAY=:1 xdotool type 'new connection'
    sleep 1
    DISPLAY=:1 xdotool key Return
    sleep 2

    # Fill connection fields again
    DISPLAY=:1 xdotool mousemove 1740 690 click 1
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type 'localhost'
    sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 755 click 1
    sleep 0.3
    DISPLAY=:1 xdotool type 'sa'
    sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 785 click 1
    sleep 0.3
    DISPLAY=:1 xdotool type 'GymAnything#2024'
    sleep 0.3
    DISPLAY=:1 xdotool mousemove 1740 905 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key t Return
    sleep 0.5
    DISPLAY=:1 xdotool mousemove 1770 1049 click 1
    sleep 8

    # Check again
    RETRY_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure" | head -1)
    if echo "$RETRY_TITLE" | grep -qi "localhost.*Azure"; then
        echo "Connection established on retry!"
        CONNECTION_ESTABLISHED=true
    else
        echo "CRITICAL: Connection still failed after retry. Task may not work correctly."
        echo "Title: $RETRY_TITLE"
    fi
fi

# Save connection state for debugging
FINAL_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure" | head -1)
echo "Final window title: $FINAL_TITLE"
echo "$FINAL_TITLE" > /tmp/ads_connection_state.txt

# Open a new query editor for backup operations
echo "Opening new query editor..."
DISPLAY=:1 xdotool key F1
sleep 0.5
DISPLAY=:1 xdotool type 'new query'
sleep 0.5
DISPLAY=:1 xdotool key Return
sleep 2

# Keep master database for backup operations (default after connection)
# Clear the query editor content and ensure focus for agent
DISPLAY=:1 xdotool mousemove 600 400 click 1
sleep 0.3
DISPLAY=:1 xdotool key ctrl+a Delete
sleep 0.5

# Final dialog dismissal - handle any popups that appeared during setup
echo "Final dialog cleanup..."
# Click X close button on Preview features dialog
DISPLAY=:1 xdotool mousemove 1889 917 click 1
sleep 0.5
DISPLAY=:1 xdotool key Escape
sleep 0.5
DISPLAY=:1 xdotool mousemove 960 400 click 1
sleep 0.5

# FINAL VERIFICATION: Confirm ADS is connected before taking screenshot
echo "Final verification of connection state..."
FINAL_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "azure" | head -1)
# Connected state shows "localhost - Azure Data Studio" or similar
if echo "$FINAL_TITLE" | grep -qi "localhost"; then
    echo "VERIFIED: ADS connection confirmed"
    echo "Title: $FINAL_TITLE"
else
    echo "WARNING: ADS may not be connected. Title: $FINAL_TITLE"
fi

# Take initial screenshot AFTER Azure Data Studio is ready
echo "Taking initial screenshot with Azure Data Studio ready..."
take_screenshot /tmp/task_start_screenshot.png

# Also capture as verification evidence
DISPLAY=:1 import -window root /tmp/verified_task_start.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo ""
echo "Azure Data Studio is running and connected to SQL Server."
echo ""
echo "Task: Create a full backup of AdventureWorks2022"
echo "- Execute BACKUP DATABASE statement"
echo "- Backup path: /backup/AdventureWorks2022_backup.bak"
echo "- Verify with RESTORE VERIFYONLY"
echo ""
