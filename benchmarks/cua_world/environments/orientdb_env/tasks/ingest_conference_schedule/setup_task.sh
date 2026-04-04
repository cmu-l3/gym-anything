#!/bin/bash
set -e
echo "=== Setting up Ingest Conference Schedule task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure OrientDB is running and ready
wait_for_orientdb 120

# 2. Ensure DemoDB is loaded and populated
# The standard setup script usually does this, but we verify here
if ! orientdb_db_exists "demodb"; then
    echo "Creating demodb..."
    /workspace/scripts/seed_demodb.py > /tmp/seed_log.txt 2>&1
fi

# 3. Create the JSON data file
echo "Creating conference data file..."
cat > /home/ga/conference_data.json << 'EOF'
[
  {
    "name": "Global Graph Summit 2026",
    "venue_hotel": "Hotel Artemide",
    "sessions": [
      {
        "title": "Scaling OrientDB Clusters",
        "duration": 45,
        "speaker_email": "luca.rossi@example.com"
      },
      {
        "title": "Graph Algorithms in Practice",
        "duration": 60,
        "speaker_email": "sophie.martin@example.com"
      }
    ]
  },
  {
    "name": "Travel Tech World",
    "venue_hotel": "The Savoy",
    "sessions": [
      {
        "title": "Recommender Systems 101",
        "duration": 30,
        "speaker_email": "david.jones@example.com"
      },
      {
        "title": "The Future of Booking",
        "duration": 50,
        "speaker_email": "luca.rossi@example.com"
      }
    ]
  }
]
EOF

# Set permissions
chown ga:ga /home/ga/conference_data.json
chmod 644 /home/ga/conference_data.json

# 4. Clean up any previous run artifacts (schema)
# We want the agent to create these
echo "Cleaning up any previous schema..."
orientdb_sql "demodb" "DROP CLASS Conferences UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS Sessions UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS HostedAt UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS HasSession UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS PresentedBy UNSAFE" >/dev/null 2>&1 || true

# 5. Launch Firefox to Studio
echo "Launching Firefox..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="