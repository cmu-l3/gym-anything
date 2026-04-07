#!/bin/bash
set -e
echo "=== Setting up transclusion task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure TiddlyWiki server is running
TW_URL="http://localhost:8080"
for i in $(seq 1 30); do
    if curl -s "$TW_URL/" > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# Create source tiddlers via TiddlyWiki HTTP API
echo "Creating source tiddler: Service Health Check Procedure"
curl -s -X PUT "${TW_URL}/recipes/default/tiddlers/Service%20Health%20Check%20Procedure" \
  -H "Content-Type: application/json" \
  -H "X-Requested-With: TiddlyWiki" \
  -d @- << 'ENDJSON'
{
  "title": "Service Health Check Procedure",
  "tags": "Operations Procedures",
  "text": "!! Service Health Verification Steps\n\n# Verify all Kubernetes pods are in Running state:\n\n