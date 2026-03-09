#!/bin/bash
echo "=== Setting up Configure Dashboard Properties Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Emoncms to be ready
wait_for_emoncms

# Get Admin Write API Key
APIKEY=$(get_apikey_write)
echo "Using API Key: $APIKEY"

# -----------------------------------------------------------------------
# Ensure clean state: Dashboard ID 1 should exist with default values
# -----------------------------------------------------------------------

# Check if dashboard 1 exists
DASH_EXISTS=$(db_query "SELECT count(*) FROM dashboard WHERE id=1" 2>/dev/null)

if [ "$DASH_EXISTS" = "0" ]; then
    echo "Dashboard 1 not found. Creating..."
    # Create dashboard via API to ensure proper initialization
    # Note: API might not guarantee ID=1 if auto-increment is higher, 
    # but in a fresh env it likely will be. We force update ID if needed.
    
    # Create "My Dashboard"
    curl -s "${EMONCMS_URL}/dashboard/create.json?apikey=${APIKEY}&name=My+Dashboard&description=&public=0" > /dev/null
    
    # Get the ID of the dashboard we just created (most recent)
    NEW_ID=$(db_query "SELECT id FROM dashboard ORDER BY id DESC LIMIT 1")
    
    # Force it to ID 1 if it isn't (for consistency with task description)
    if [ "$NEW_ID" != "1" ]; then
        db_query "UPDATE dashboard SET id=1 WHERE id=${NEW_ID}"
    fi
else
    echo "Dashboard 1 exists. Resetting properties..."
    # Reset properties directly in DB to ensure known starting state
    db_query "UPDATE dashboard SET name='My Dashboard', description='', public=0, alias='', published=0 WHERE id=1"
fi

# -----------------------------------------------------------------------
# Populate with some widgets so it looks realistic
# -----------------------------------------------------------------------
# Only add widgets if content is empty/default
CONTENT_LEN=$(db_query "SELECT LENGTH(content) FROM dashboard WHERE id=1")
if [ "$CONTENT_LEN" -lt 10 ]; then
    echo "Populating dashboard with widgets..."
    # Minimal widget config: a heading and a feedvalue
    # We need a feed ID. Let's see if we have one.
    FEED_ID=$(db_query "SELECT id FROM feeds LIMIT 1")
    if [ -z "$FEED_ID" ]; then FEED_ID=1; fi
    
    # JSON content for dashboard
    WIDGETS_JSON="[{\"type\":\"heading\",\"x\":1,\"y\":1,\"width\":6,\"height\":1,\"options\":{\"text\":\"Current Power\",\"font\":\"bold\",\"color\":\"#333\"}},{\"type\":\"feedvalue\",\"x\":1,\"y\":2,\"width\":3,\"height\":1,\"options\":{\"feedid\":$FEED_ID,\"units\":\"W\"}}]"
    
    # Update content column (need to be careful with quotes in SQL)
    # Using python to escape/insert safely might be better, but we'll try API set
    # Actually, simpler to leave content null or basic. The task is about properties.
    # Let's just update DB.
    docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -e "UPDATE dashboard SET content='$WIDGETS_JSON' WHERE id=1"
fi

# -----------------------------------------------------------------------
# Record initial state for verification (Anti-gaming)
# -----------------------------------------------------------------------
# Capture the initial modification time or state
INITIAL_STATE=$(db_query "SELECT name, public, alias, description FROM dashboard WHERE id=1")
echo "$INITIAL_STATE" > /tmp/initial_db_state.txt

# -----------------------------------------------------------------------
# Prepare Browser
# -----------------------------------------------------------------------
# Launch Firefox logged in and navigated to Dashboard List
launch_firefox_to "http://localhost/dashboard/list" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="