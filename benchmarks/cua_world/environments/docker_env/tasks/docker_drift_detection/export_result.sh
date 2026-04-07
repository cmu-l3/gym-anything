#!/bin/bash
echo "=== Exporting Drift Detection Results ==="

# Source utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# ------------------------------------------------------------------
# 1. Check Output Files (Report & Configs)
# ------------------------------------------------------------------
REPORT_PATH="/home/ga/Desktop/drift_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_MTIME="0"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH")
    # Read first 2KB for verification
    REPORT_CONTENT=$(head -c 2000 "$REPORT_PATH" | base64 -w 0)
fi

# Check extracted configs
CONFIG_BASE="/home/ga/projects/container-configs"
HAS_WEBSERVER_CONFIG="false"
HAS_APPSERVER_CONFIG="false"
HAS_TASKRUNNER_CONFIG="false"

[ -f "$CONFIG_BASE/webserver/default.conf" ] || [ -f "$CONFIG_BASE/webserver/nginx.conf" ] && HAS_WEBSERVER_CONFIG="true"
[ -f "$CONFIG_BASE/appserver/config.json" ] && HAS_APPSERVER_CONFIG="true"
[ -f "$CONFIG_BASE/taskrunner/backup.sh" ] || [ -f "$CONFIG_BASE/taskrunner/root" ] && HAS_TASKRUNNER_CONFIG="true"

# ------------------------------------------------------------------
# 2. Check Container States (Originals & Clean)
# ------------------------------------------------------------------

# Function to get container status
check_status() {
    docker inspect --format '{{.State.Status}}' "$1" 2>/dev/null || echo "missing"
}

# Function to get container image
check_image() {
    docker inspect --format '{{.Config.Image}}' "$1" 2>/dev/null || echo "missing"
}

# Check Originals (Should be stopped/missing)
ORIG_WEBSERVER_STATUS=$(check_status "acme-webserver")
ORIG_APPSERVER_STATUS=$(check_status "acme-appserver")
ORIG_TASKRUNNER_STATUS=$(check_status "acme-taskrunner")

ORIGINALS_STOPPED="false"
if [[ "$ORIG_WEBSERVER_STATUS" != "running" && "$ORIG_APPSERVER_STATUS" != "running" && "$ORIG_TASKRUNNER_STATUS" != "running" ]]; then
    ORIGINALS_STOPPED="true"
fi

# Check Clean Replacements (Should be running)
CLEAN_WEBSERVER_STATUS=$(check_status "acme-webserver-clean")
CLEAN_APPSERVER_STATUS=$(check_status "acme-appserver-clean")
CLEAN_TASKRUNNER_STATUS=$(check_status "acme-taskrunner-clean")

# Check Clean Images (Should match base, NOT committed)
CLEAN_WEBSERVER_IMAGE=$(check_image "acme-webserver-clean")
CLEAN_APPSERVER_IMAGE=$(check_image "acme-appserver-clean")
CLEAN_TASKRUNNER_IMAGE=$(check_image "acme-taskrunner-clean")

# ------------------------------------------------------------------
# 3. Verify Cleanliness (No unauthorized drift inherited)
# ------------------------------------------------------------------
WEBSERVER_CLEAN="false"
APPSERVER_CLEAN="false"
TASKRUNNER_CLEAN="false" # Taskrunner drift was all legitimate, so base image might miss scripts if not mounted

# Webserver: Check for curl (should be absent in clean alpine image)
if [ "$CLEAN_WEBSERVER_STATUS" == "running" ]; then
    if docker exec acme-webserver-clean which curl >/dev/null 2>&1; then
        WEBSERVER_CLEAN="false" # Curl found -> Dirty
    else
        WEBSERVER_CLEAN="true"
    fi
fi

# Appserver: Check for debugpy (should be absent)
if [ "$CLEAN_APPSERVER_STATUS" == "running" ]; then
    if docker exec acme-appserver-clean pip show debugpy >/dev/null 2>&1; then
        APPSERVER_CLEAN="false" # Debugpy found -> Dirty
    else
        APPSERVER_CLEAN="true"
    fi
fi

# Taskrunner: Check it's running base alpine (no drift check needed as drift was valid, 
# but ensuring it's a fresh container is handled by image name check)
TASKRUNNER_CLEAN="true" 

# ------------------------------------------------------------------
# 4. Generate JSON Result
# ------------------------------------------------------------------
cat <<EOF > /tmp/task_result.json
{
  "timestamp": $EXPORT_TIME,
  "task_start": $TASK_START,
  "report": {
    "exists": $REPORT_EXISTS,
    "size": $REPORT_SIZE,
    "mtime": $REPORT_MTIME,
    "content_b64": "$REPORT_CONTENT"
  },
  "configs": {
    "webserver_extracted": $HAS_WEBSERVER_CONFIG,
    "appserver_extracted": $HAS_APPSERVER_CONFIG,
    "taskrunner_extracted": $HAS_TASKRUNNER_CONFIG
  },
  "originals": {
    "webserver_status": "$ORIG_WEBSERVER_STATUS",
    "appserver_status": "$ORIG_APPSERVER_STATUS",
    "taskrunner_status": "$ORIG_TASKRUNNER_STATUS",
    "all_stopped": $ORIGINALS_STOPPED
  },
  "clean_containers": {
    "webserver": {
      "status": "$CLEAN_WEBSERVER_STATUS",
      "image": "$CLEAN_WEBSERVER_IMAGE",
      "is_clean": $WEBSERVER_CLEAN
    },
    "appserver": {
      "status": "$CLEAN_APPSERVER_STATUS",
      "image": "$CLEAN_APPSERVER_IMAGE",
      "is_clean": $APPSERVER_CLEAN
    },
    "taskrunner": {
      "status": "$CLEAN_TASKRUNNER_STATUS",
      "image": "$CLEAN_TASKRUNNER_IMAGE",
      "is_clean": $TASKRUNNER_CLEAN
    }
  }
}
EOF

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json