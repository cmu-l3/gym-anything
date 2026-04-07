#!/bin/bash
echo "=== Setting up save_draft_post task ==="

source /workspace/scripts/task_utils.sh

# Remove any root-owned tmp files from previous runs that would block writes
sudo rm -f /tmp/task_start_timestamp /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Download image to the target location for the agent to use
mkdir -p /home/ga/Documents
wget -qO /home/ga/Documents/Q3_Sustainability_Campaign.jpg "https://upload.wikimedia.org/wikipedia/commons/thumb/b/b6/Wind_turbines_in_southern_California_2016.jpg/1024px-Wind_turbines_in_southern_California_2016.jpg"
chmod 666 /home/ga/Documents/Q3_Sustainability_Campaign.jpg
log "Campaign image downloaded to /home/ga/Documents"

# Clear existing drafts with similar text to ensure clean verification state
cat > /tmp/mongo_clear.js << 'EOF'
db.getCollectionNames().forEach(function(c) {
  try {
    db.getCollection(c).deleteMany({
      $or: [
        { "postDetails": { $regex: "Q3 sustainability", $options: "i" } },
        { "description": { $regex: "Q3 sustainability", $options: "i" } },
        { "message": { $regex: "Q3 sustainability", $options: "i" } }
      ]
    });
  } catch(e) {
    // Ignore collections that do not support standard querying/deletion
  }
});
EOF
mongosh socioboard --quiet /tmp/mongo_clear.js 2>/dev/null || mongo socioboard --quiet /tmp/mongo_clear.js 2>/dev/null || true
log "Cleared existing related drafts from MongoDB"

# Wait for Socioboard to be ready
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable"
  exit 1
fi

# Clear any existing session by navigating to logout first
log "Clearing browser session via logout..."
open_socioboard_page "http://localhost/logout"
sleep 2

# Open Socioboard login page
navigate_to "http://localhost/login"
sleep 3

take_screenshot /tmp/task_start.png
log "Task start screenshot saved: /tmp/task_start.png"
echo "=== Task setup complete: save_draft_post ==="