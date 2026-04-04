#!/bin/bash
echo "=== Setting up emoncms_data_audit_remediation ==="
source /workspace/scripts/task_utils.sh

wait_for_emoncms
WRITE_KEY=$(get_apikey_write)

# Ensure the seed feeds and inputs exist (they should from setup_emoncms.sh)
# Make sure House Power feed exists
HOUSE_POWER_ID=$(db_query "SELECT id FROM feeds WHERE userid=1 AND name='House Power'" 2>/dev/null | head -1)
if [ -z "$HOUSE_POWER_ID" ]; then
    echo "House Power feed missing — creating..."
    curl -s "${EMONCMS_URL}/feed/create.json?apikey=${WRITE_KEY}&name=House+Power&tag=power&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W" >/dev/null 2>&1 || true
    sleep 2
    HOUSE_POWER_ID=$(db_query "SELECT id FROM feeds WHERE userid=1 AND name='House Power'" 2>/dev/null | head -1)
fi

SOLAR_PV_ID=$(db_query "SELECT id FROM feeds WHERE userid=1 AND name='Solar PV'" 2>/dev/null | head -1)
if [ -z "$SOLAR_PV_ID" ]; then
    echo "Solar PV feed missing — creating..."
    curl -s "${EMONCMS_URL}/feed/create.json?apikey=${WRITE_KEY}&name=Solar+PV&tag=solar&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W" >/dev/null 2>&1 || true
    sleep 2
    SOLAR_PV_ID=$(db_query "SELECT id FROM feeds WHERE userid=1 AND name='Solar PV'" 2>/dev/null | head -1)
fi

HOUSE_TEMP_ID=$(db_query "SELECT id FROM feeds WHERE userid=1 AND name='House Temperature'" 2>/dev/null | head -1)
if [ -z "$HOUSE_TEMP_ID" ]; then
    echo "House Temperature feed missing — creating..."
    curl -s "${EMONCMS_URL}/feed/create.json?apikey=${WRITE_KEY}&name=House+Temperature&tag=temperature&datatype=1&engine=5&options=%7B%22interval%22%3A60%7D&unit=degC" >/dev/null 2>&1 || true
    sleep 2
    HOUSE_TEMP_ID=$(db_query "SELECT id FROM feeds WHERE userid=1 AND name='House Temperature'" 2>/dev/null | head -1)
fi

# Ensure power1 and solar inputs exist
curl -s "${EMONCMS_URL}/input/post?apikey=${WRITE_KEY}&node=home&fulljson=%7B%22power1%22%3A1500%2C%22solar%22%3A2000%7D" >/dev/null 2>&1 || true
sleep 2

echo "Feed IDs: House Power=${HOUSE_POWER_ID}, Solar PV=${SOLAR_PV_ID}, House Temp=${HOUSE_TEMP_ID}"

# === INJECT 5 BROKEN CONFIGURATIONS ===

# Broken config 1: power1 input processlist → non-existent feed ID 99991
POWER1_ID=$(db_query "SELECT id FROM input WHERE userid=1 AND name='power1'" 2>/dev/null | head -1)
if [ -n "$POWER1_ID" ]; then
    db_query "UPDATE input SET processList='1:99991' WHERE id=${POWER1_ID}" 2>/dev/null || true
    echo "BROKEN: power1 input processlist set to 1:99991 (non-existent feed)"
fi

# Broken config 2: solar input processlist → non-existent feed ID 99992
SOLAR_INPUT_ID=$(db_query "SELECT id FROM input WHERE userid=1 AND name='solar'" 2>/dev/null | head -1)
if [ -n "$SOLAR_INPUT_ID" ]; then
    db_query "UPDATE input SET processList='1:99992' WHERE id=${SOLAR_INPUT_ID}" 2>/dev/null || true
    echo "BROKEN: solar input processlist set to 1:99992 (non-existent feed)"
fi

# Broken config 3: House Power feed interval = 0 (invalid — PHPFina cannot store at interval 0)
if [ -n "$HOUSE_POWER_ID" ]; then
    db_query "UPDATE feeds SET interval=0 WHERE id=${HOUSE_POWER_ID}" 2>/dev/null || true
    echo "BROKEN: House Power feed interval set to 0"
fi

# Broken config 4: House Temperature feed engine = 0 (disabled engine — no storage)
if [ -n "$HOUSE_TEMP_ID" ]; then
    db_query "UPDATE feeds SET engine=0 WHERE id=${HOUSE_TEMP_ID}" 2>/dev/null || true
    echo "BROKEN: House Temperature feed engine set to 0 (disabled)"
fi

# Broken config 5: Solar PV feed tag = '' (empty tag)
if [ -n "$SOLAR_PV_ID" ]; then
    db_query "UPDATE feeds SET tag='' WHERE id=${SOLAR_PV_ID}" 2>/dev/null || true
    echo "BROKEN: Solar PV feed tag cleared to empty string"
fi

# Store known good feed IDs so verifier can check processlists reference them
echo "${HOUSE_POWER_ID:-0}" > /tmp/audit_house_power_feed_id
echo "${SOLAR_PV_ID:-0}"   > /tmp/audit_solar_pv_feed_id

date +%s > /tmp/task_start_timestamp

# Navigate to feeds page so agent can start auditing
launch_firefox_to "http://localhost/feed/list" 5

take_screenshot /tmp/task_audit_start.png

echo "=== Setup complete: emoncms_data_audit_remediation ==="
echo "5 broken configs injected. Agent must discover and fix all."
echo "  - power1 input: processlist→non-existent feed"
echo "  - solar input: processlist→non-existent feed"
echo "  - House Power feed: interval=0"
echo "  - House Temperature feed: engine=0"
echo "  - Solar PV feed: tag=''"
