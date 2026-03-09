#!/bin/bash
# Export script for Metadata Dependency Cleanup task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh

# Load the IDs tracked during setup
if [ ! -f /tmp/task_metadata_ids.json ]; then
    echo "Error: Metadata IDs file not found. Setup may have failed."
    # Create dummy file to prevent catastrophic failure, will result in 0 score
    echo '{"de_id": "missing", "ds_id": "missing", "grp_id": "missing"}' > /tmp/task_metadata_ids.json
fi

DE_ID=$(jq -r '.de_id' /tmp/task_metadata_ids.json)
DS_ID=$(jq -r '.ds_id' /tmp/task_metadata_ids.json)
GRP_ID=$(jq -r '.grp_id' /tmp/task_metadata_ids.json)

echo "Checking status of objects:"
echo "  Target Data Element: $DE_ID"
echo "  Container Dataset:   $DS_ID"
echo "  Container Group:     $GRP_ID"

# helper to check existence via API code
check_exists() {
    local endpoint="$1"
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" -u admin:district "http://localhost:8080/api/$endpoint")
    if [ "$code" == "200" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Check existence
DE_EXISTS=$(check_exists "dataElements/$DE_ID")
DS_EXISTS=$(check_exists "dataSets/$DS_ID")
GRP_EXISTS=$(check_exists "dataElementGroups/$GRP_ID")

echo "  DE Exists: $DE_EXISTS (Expected: false)"
echo "  DS Exists: $DS_EXISTS (Expected: true)"
echo "  Grp Exists: $GRP_EXISTS (Expected: true)"

# Check if app is running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Generate Result JSON
cat > /tmp/task_result.json <<EOF
{
  "target_de_exists": $DE_EXISTS,
  "container_ds_exists": $DS_EXISTS,
  "container_grp_exists": $GRP_EXISTS,
  "app_was_running": $APP_RUNNING,
  "task_ids": {
    "de_id": "$DE_ID",
    "ds_id": "$DS_ID",
    "grp_id": "$GRP_ID"
  },
  "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="