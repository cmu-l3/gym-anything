#!/bin/bash
echo "=== Setting up create_filtered_dashboard task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create the realistic seed tiddlers using Python to ensure robust text handling
su - ga -c 'python3 -c "
import os

tiddlers = [
    {\"title\": \"Implement rate limiting middleware\", \"tags\": \"InProgress ProjectAlpha\"},
    {\"title\": \"Add OAuth2 authentication flow\", \"tags\": \"Done ProjectAlpha\"},
    {\"title\": \"Fix CORS configuration for staging\", \"tags\": \"Todo ProjectAlpha\"},
    {\"title\": \"Set up API versioning strategy\", \"tags\": \"InProgress ProjectAlpha\"},
    {\"title\": \"Write integration tests for users endpoint\", \"tags\": \"Todo ProjectAlpha\"},
    {\"title\": \"Migrate to React Navigation v6\", \"tags\": \"Done ProjectBeta\"},
    {\"title\": \"Implement push notification handler\", \"tags\": \"InProgress ProjectBeta\"},
    {\"title\": \"Fix memory leak in image carousel\", \"tags\": \"Todo ProjectBeta\"},
    {\"title\": \"Add biometric authentication support\", \"tags\": \"Todo ProjectBeta\"},
    {\"title\": \"Optimize bundle size for production\", \"tags\": \"Done ProjectBeta\"},
    {\"title\": \"Configure Apache Airflow DAG for ETL\", \"tags\": \"InProgress ProjectGamma\"},
    {\"title\": \"Add data quality checks for customer table\", \"tags\": \"Todo ProjectGamma\"},
    {\"title\": \"Migrate from Redshift to BigQuery\", \"tags\": \"Todo ProjectGamma\"},
    {\"title\": \"Implement incremental load for orders\", \"tags\": \"Done ProjectGamma\"},
    {\"title\": \"Set up monitoring dashboards in Grafana\", \"tags\": \"InProgress ProjectGamma\"}
]

base_dir = \"/home/ga/mywiki/tiddlers\"
os.makedirs(base_dir, exist_ok=True)

for t in tiddlers:
    filename = t[\"title\"].replace(\"/\", \"_\") + \".tid\"
    path = os.path.join(base_dir, filename)
    with open(path, \"w\") as f:
        f.write(f\"title: {t[\"title\"]}\\ntags: {t[\"tags\"]}\\n\\nTask description for {t[\"title\"]}.\")
"'

# Remove any existing Project Dashboard to ensure a clean slate
rm -f "/home/ga/mywiki/tiddlers/Project Dashboard.tid" 2>/dev/null || true
rm -f "/home/ga/mywiki/tiddlers/Project_Dashboard.tid" 2>/dev/null || true

# Ensure TiddlyWiki is running
if ! curl -s http://localhost:8080/ > /dev/null 2>&1; then
    su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"
    sleep 5
fi

# Ensure Firefox is open to the wiki
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla\|tiddly"; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Maximize Firefox and refresh to pick up the new seed data
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key F5
sleep 3

# Take initial screenshot showing starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="