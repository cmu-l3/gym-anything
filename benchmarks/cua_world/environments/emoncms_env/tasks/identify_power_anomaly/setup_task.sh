#!/bin/bash
# setup_task.sh — Identify Power Anomaly task setup
# Injects a randomized anomaly into the feed data and records ground truth.

source /workspace/scripts/task_utils.sh

echo "=== Setting up identify_power_anomaly task ==="
date +%s > /tmp/task_start_time.txt

# Wait for Emoncms to be ready
wait_for_emoncms

APIKEY=$(get_apikey_write)
if [ -z "$APIKEY" ]; then
    echo "ERROR: Could not retrieve API key"
    exit 1
fi

# -----------------------------------------------------------------------
# 1. Get or Create the Target Feed
# -----------------------------------------------------------------------
FEED_NAME="House_Consumption_Power"
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='${FEED_NAME}' LIMIT 1" | tr -d '[:space:]')

if [ -z "$FEED_ID" ]; then
    echo "Creating '${FEED_NAME}' feed..."
    # Create feed via API
    RESULT=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=${FEED_NAME}&tag=Power&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W")
    FEED_ID=$(echo "$RESULT" | jq -r '.feedid // empty')
    
    if [ -z "$FEED_ID" ]; then
        echo "ERROR: Failed to create feed. Result: $RESULT"
        exit 1
    fi
    echo "Created feed ID: ${FEED_ID}"
else
    echo "Using existing feed ID: ${FEED_ID}"
fi

# -----------------------------------------------------------------------
# 2. Determine Anomaly Injection Time (Randomized)
#    Pick a time between 24 and 60 hours ago to ensure it's in history
# -----------------------------------------------------------------------
HOURS_AGO=$((24 + RANDOM % 36))
BASE_TIME=$(date -d "${HOURS_AGO} hours ago" +%s)
# Align to 10-minute boundary
ANOMALY_START=$((BASE_TIME / 600 * 600))

# Anomaly definition
# Pattern: Ramp up -> Peak -> Ramp down
# Interval: 10 minutes (600s)
# Values significantly higher than normal (<2500W)
ANOMALY_VALUES=(5500 7200 8450 6800 5900)
ANOMALY_DURATION=$(( ${#ANOMALY_VALUES[@]} * 10 )) # 50 minutes
PEAK_INDEX=2
ANOMALY_PEAK_VALUE=${ANOMALY_VALUES[$PEAK_INDEX]}
ANOMALY_PEAK_TIME=$((ANOMALY_START + PEAK_INDEX * 600))

echo "Injecting anomaly: Start=${ANOMALY_START}, PeakTime=${ANOMALY_PEAK_TIME}, PeakVal=${ANOMALY_PEAK_VALUE}"

# -----------------------------------------------------------------------
# 3. Inject Data Points
# -----------------------------------------------------------------------
for i in "${!ANOMALY_VALUES[@]}"; do
    T=$((ANOMALY_START + i * 600))
    V=${ANOMALY_VALUES[$i]}
    curl -s "${EMONCMS_URL}/feed/insert.json?apikey=${APIKEY}&id=${FEED_ID}&time=${T}&value=${V}" > /dev/null
done

# Fill in some normal background data around the anomaly (optional but good for realism)
# Add 3 hours before and after with normal values (approx 500-2000W)
for offset in $(seq -18 18); do
    # Skip the anomaly window (indices 0 to 4)
    if [ "$offset" -ge 0 ] && [ "$offset" -lt 5 ]; then continue; fi
    
    T=$((ANOMALY_START + offset * 600))
    V=$((500 + RANDOM % 1500))
    curl -s "${EMONCMS_URL}/feed/insert.json?apikey=${APIKEY}&id=${FEED_ID}&time=${T}&value=${V}" > /dev/null
done

# Force PHPFina buffer write (sleep slightly)
sleep 2

# -----------------------------------------------------------------------
# 4. Save Ground Truth (Hidden)
# -----------------------------------------------------------------------
GROUND_TRUTH_DIR="/var/lib/emoncms_ground_truth"
mkdir -p "$GROUND_TRUTH_DIR"
cat > "${GROUND_TRUTH_DIR}/anomaly_truth.json" << EOF
{
    "feed_id": $FEED_ID,
    "peak_timestamp": $ANOMALY_PEAK_TIME,
    "peak_value": $ANOMALY_PEAK_VALUE,
    "duration_minutes": $ANOMALY_DURATION
}
EOF
chmod 644 "${GROUND_TRUTH_DIR}/anomaly_truth.json"

# -----------------------------------------------------------------------
# 5. UI Setup
# -----------------------------------------------------------------------
# Launch Firefox to the Feeds page
launch_firefox_to "http://localhost/feed/list" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="