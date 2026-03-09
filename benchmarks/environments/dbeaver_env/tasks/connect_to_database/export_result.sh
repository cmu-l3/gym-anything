#!/bin/bash
# Export script for connect_to_database task
# Saves verification data to JSON file

echo "=== Exporting Connect to Database Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get initial state
INITIAL_CONNECTIONS=$(cat /tmp/initial_connection_count 2>/dev/null || echo "0")

# Check DBeaver configuration for connections
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
DATASOURCES_FILE="$CONFIG_DIR/data-sources.json"

CONNECTION_FOUND="false"
CONNECTION_NAME=""
DB_PATH=""
DB_TYPE=""
CURRENT_CONNECTIONS=0
CONNECTION_EXPANDED="false"
EXACT_NAME_MATCH="false"

echo "Checking DBeaver configuration at: $DATASOURCES_FILE"

if [ -f "$DATASOURCES_FILE" ]; then
    echo "Data sources file found"
    cat "$DATASOURCES_FILE" 2>/dev/null | head -100

    # Count connections (count provider entries which indicate actual connections)
    CURRENT_CONNECTIONS=$(grep -c '"provider"' "$DATASOURCES_FILE" 2>/dev/null || echo "0")

    # Check for Chinook connection - extract the actual name
    if grep -qi "chinook" "$DATASOURCES_FILE" 2>/dev/null; then
        CONNECTION_FOUND="true"
        # Extract connection name more reliably
        CONNECTION_NAME=$(python3 -c "
import json
try:
    with open('$DATASOURCES_FILE', 'r') as f:
        data = json.load(f)
    for key, conn in data.get('connections', {}).items():
        name = conn.get('name', '')
        if 'chinook' in name.lower():
            print(name)
            break
except:
    pass
" 2>/dev/null)

        # Check if name is exactly "Chinook" (case-sensitive)
        if [ "$CONNECTION_NAME" = "Chinook" ]; then
            EXACT_NAME_MATCH="true"
            echo "Exact name match: Chinook"
        else
            echo "Name mismatch: got '$CONNECTION_NAME', expected 'Chinook'"
        fi
    fi

    # Check for SQLite connection type
    if grep -qi "sqlite" "$DATASOURCES_FILE" 2>/dev/null; then
        DB_TYPE="sqlite"
    fi

    # Check for the expected database path
    if grep -q "/home/ga/Documents/databases/chinook.db" "$DATASOURCES_FILE" 2>/dev/null; then
        DB_PATH="/home/ga/Documents/databases/chinook.db"
    fi

    # Check if connection was expanded (look for cached metadata indicating tables were loaded)
    METADATA_DIR="$CONFIG_DIR/.metadata"
    if [ -d "$METADATA_DIR" ]; then
        # Check if there are cached table metadata files for chinook
        if find "$METADATA_DIR" -name "*.json" -newer /tmp/task_start_time 2>/dev/null | grep -q .; then
            CONNECTION_EXPANDED="true"
            echo "Connection metadata found - connection was expanded"
        fi
    fi

    # Alternative check: see if connection folder shows expansion state
    if grep -q '"folder"' "$DATASOURCES_FILE" 2>/dev/null; then
        # Check DBeaver navigator state file
        NAV_STATE_FILE="$CONFIG_DIR/../.metadata/.plugins/org.eclipse.ui.workbench/workbench.xml"
        if [ -f "$NAV_STATE_FILE" ] && grep -qi "chinook" "$NAV_STATE_FILE" 2>/dev/null; then
            CONNECTION_EXPANDED="true"
            echo "Connection appears in navigator state - likely expanded"
        fi
    fi
else
    echo "Data sources file not found"
fi

# Check window title and visible content for expansion evidence
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Window list:"
echo "$WINDOW_LIST"

# Use xdotool to get active window content info
ACTIVE_WINDOW_NAME=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "")
echo "Active window: $ACTIVE_WINDOW_NAME"

# Check if DBeaver window shows expanded connection (Tables visible)
# Take screenshot and check if "Tables" text is visible indicating expansion
if [ -f /tmp/task_end_screenshot.png ]; then
    # Simple check: if screenshot was taken successfully during task, we can do VLM verification later
    echo "Screenshot captured for VLM verification"
fi

# Check if DBeaver is running
DBEAVER_RUNNING=$(is_dbeaver_running)

# Verify connection actually works through DBeaver
# Check for evidence that DBeaver successfully connected:
# 1. Metadata cache files created for the connection
# 2. Connection state shows as "connected" in config
# 3. Database file exists and is valid (baseline check)
CONNECTION_WORKING="false"
CONNECTION_VERIFIED_VIA="none"

# First check if database file exists (baseline requirement)
if [ -n "$DB_PATH" ] && [ -f "$DB_PATH" ]; then
    TABLE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" 2>/dev/null || echo "0")
    if [ "$TABLE_COUNT" -gt "0" ]; then
        echo "Database file exists with $TABLE_COUNT tables"

        # Now verify DBeaver actually connected (not just file exists)
        # Check 1: Look for DBeaver's connection metadata cache
        CACHE_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/.cache"
        if [ -d "$CACHE_DIR" ] && find "$CACHE_DIR" -name "*.json" -newer /tmp/task_start_time 2>/dev/null | grep -q .; then
            CONNECTION_WORKING="true"
            CONNECTION_VERIFIED_VIA="metadata_cache"
            echo "DBeaver created connection cache files - connection verified"
        fi

        # Check 2: Look for connection in DBeaver's runtime state
        DBEAVER_STATE_DIR="/home/ga/.local/share/DBeaverData/workspace6/.metadata/.plugins"
        if [ -d "$DBEAVER_STATE_DIR" ]; then
            # Check for dbeaver state files modified during task
            if find "$DBEAVER_STATE_DIR" -name "*.xml" -newer /tmp/task_start_time 2>/dev/null | head -1 | grep -q .; then
                CONNECTION_WORKING="true"
                CONNECTION_VERIFIED_VIA="runtime_state"
                echo "DBeaver runtime state updated - connection verified"
            fi
        fi

        # Check 3: Look for successful connection expansion (tables loaded)
        if [ "$CONNECTION_EXPANDED" = "true" ]; then
            CONNECTION_WORKING="true"
            CONNECTION_VERIFIED_VIA="expansion"
            echo "Connection was expanded (tables visible) - connection verified"
        fi

        # If still not verified, check if connection appears properly configured
        if [ "$CONNECTION_WORKING" = "false" ] && [ "$EXACT_NAME_MATCH" = "true" ] && [ "$DB_PATH" = "/home/ga/Documents/databases/chinook.db" ]; then
            # Connection is properly configured - give benefit of doubt if DBeaver is running
            if [ "$DBEAVER_RUNNING" = "true" ]; then
                CONNECTION_WORKING="true"
                CONNECTION_VERIFIED_VIA="config_valid"
                echo "Connection properly configured with DBeaver running - connection verified"
            fi
        fi
    fi
fi

echo "Connection working: $CONNECTION_WORKING (verified via: $CONNECTION_VERIFIED_VIA)"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/connect_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_connection_count": ${INITIAL_CONNECTIONS:-0},
    "current_connection_count": ${CURRENT_CONNECTIONS:-0},
    "connection_found": $CONNECTION_FOUND,
    "connection_name": "$CONNECTION_NAME",
    "exact_name_match": $EXACT_NAME_MATCH,
    "db_path": "$DB_PATH",
    "db_type": "$DB_TYPE",
    "connection_expanded": $CONNECTION_EXPANDED,
    "connection_working": $CONNECTION_WORKING,
    "connection_verified_via": "$CONNECTION_VERIFIED_VIA",
    "dbeaver_running": $DBEAVER_RUNNING,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/connect_result.json 2>/dev/null || sudo rm -f /tmp/connect_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/connect_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/connect_result.json
chmod 666 /tmp/connect_result.json 2>/dev/null || sudo chmod 666 /tmp/connect_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/connect_result.json"
cat /tmp/connect_result.json

echo ""
echo "=== Export Complete ==="
