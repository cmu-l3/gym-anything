#!/bin/bash
# Setup script for Perform Feed Rollover task
set -u

echo "=== Setting up Perform Feed Rollover Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Emoncms is running
wait_for_emoncms

# 2. Get API Keys
APIKEY_WRITE=$(get_apikey_write)

# 3. Clean up any existing state (idempotency)
echo "Cleaning up old feeds/inputs..."
# Delete input 'solar_yield' if exists
INPUT_ID=$(db_query "SELECT id FROM input WHERE name='solar_yield'" 2>/dev/null | head -1)
if [ -n "$INPUT_ID" ]; then
    curl -s "${EMONCMS_URL}/input/delete.json?apikey=${APIKEY_WRITE}&inputid=${INPUT_ID}" >/dev/null
fi

# Delete feeds 'annual_yield' and 'annual_yield_archive' if exist
FEED_IDS=$(db_query "SELECT id FROM feeds WHERE name IN ('annual_yield', 'annual_yield_archive')" 2>/dev/null)
for fid in $FEED_IDS; do
    curl -s "${EMONCMS_URL}/feed/delete.json?apikey=${APIKEY_WRITE}&id=${fid}" >/dev/null
done

# 4. Create the initial 'annual_yield' feed (Simulating last year's data)
echo "Creating initial 'annual_yield' feed..."
# Create feed: PHPFina (5), 10s interval
FEED_RES=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY_WRITE}&name=annual_yield&tag=Solar&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=kWh")
INITIAL_FEED_ID=$(echo "$FEED_RES" | grep -oE '[0-9]+' || echo "")

if [ -z "$INITIAL_FEED_ID" ]; then
    echo "ERROR: Failed to create initial feed"
    exit 1
fi
echo "Initial Feed ID: $INITIAL_FEED_ID"
echo "$INITIAL_FEED_ID" > /tmp/initial_feed_id.txt

# Insert some "historical" data (simulate 10 points)
echo "Populating historical data..."
TS=$(date +%s)
START_TS=$((TS - 10000))
for i in {1..10}; do
    VAL=$((i * 10))
    TIME=$((START_TS + i * 10))
    curl -s "${EMONCMS_URL}/feed/insert.json?apikey=${APIKEY_WRITE}&id=${INITIAL_FEED_ID}&time=${TIME}&value=${VAL}" >/dev/null
done

# 5. Create the 'solar_yield' input and link it to the feed
echo "Creating 'solar_yield' input and linking..."
# Post data to create input
curl -s "${EMONCMS_URL}/input/post?apikey=${APIKEY_WRITE}&node=home&fulljson={\"solar_yield\":100}" >/dev/null

# Get Input ID
INPUT_ID=$(db_query "SELECT id FROM input WHERE name='solar_yield'" 2>/dev/null | head -1)

# Add "Log to feed" process (Process ID 1 = Log to feed)
# Format: input/process/add.json?inputid=X&processid=1&arg=FEED_ID
if [ -n "$INPUT_ID" ]; then
    curl -s "${EMONCMS_URL}/input/process/add.json?apikey=${APIKEY_WRITE}&inputid=${INPUT_ID}&processid=1&arg=${INITIAL_FEED_ID}" >/dev/null
    echo "Input $INPUT_ID linked to Feed $INITIAL_FEED_ID"
else
    echo "ERROR: Input creation failed"
    exit 1
fi

# 6. Start a background data generator to keep the input "live"
# This ensures that when the agent switches the feed, new data actually flows
cat > /tmp/solar_generator.sh << EOF
#!/bin/bash
while true; do
    VAL=\$((100 + RANDOM % 20))
    curl -s "http://localhost/input/post?apikey=${APIKEY_WRITE}&node=home&fulljson={\\"solar_yield\\":\$VAL}" >/dev/null
    sleep 5
done
EOF
chmod +x /tmp/solar_generator.sh
nohup /tmp/solar_generator.sh >/dev/null 2>&1 &
echo $! > /tmp/generator_pid.txt

# 7. Launch Firefox to the Feeds page
echo "Launching Firefox..."
launch_firefox_to "http://localhost/feed/list" 5

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="