#!/bin/bash
echo "=== Setting up identify_event_provenance task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 2. Ensure services are running
echo "--- Ensuring SeisComP services are running ---"
systemctl start mariadb || true
sleep 2
ensure_scmaster_running

# 3. Verify event data is in the database and convert if missing
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found, attempting to import..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
        sleep 2
    fi
fi

# 4. Generate Randomized Metadata (Anti-Gaming)
RAND_ID=$((1000 + RANDOM % 9000))
SAFE_AUTHOR="Analyst_${RAND_ID}"
SAFE_AGENCY="SeisNet_${RAND_ID}"
METHODS=("trimmed_mean" "weighted_average" "median" "mean" "L1_norm")
SAFE_METHOD=${METHODS[$((RANDOM % ${#METHODS[@]}))]}

echo "Ground Truth Generated."

# 5. Store Ground Truth (Hidden from agent's immediate view)
cat > /tmp/task_ground_truth.json << EOF
{
  "author": "$SAFE_AUTHOR",
  "agency": "$SAFE_AGENCY",
  "method": "$SAFE_METHOD"
}
EOF
chmod 600 /tmp/task_ground_truth.json

# 6. Inject randomized values into the SeisComP Database
echo "Injecting metadata into database..."
mysql -u sysop -psysop seiscomp << SQLEOF
UPDATE Magnitude m
SET 
    m.creationInfo_author = '${SAFE_AUTHOR}',
    m.creationInfo_agencyID = '${SAFE_AGENCY}',
    m.methodID = '${SAFE_METHOD}'
WHERE m.publicID IN (
    SELECT preferredMagnitudeID FROM Event WHERE preferredMagnitudeID IS NOT NULL
);
SQLEOF

# Verify Injection
CHECK_VAL=$(mysql -u sysop -psysop seiscomp -N -e "SELECT creationInfo_author FROM Magnitude WHERE publicID IN (SELECT preferredMagnitudeID FROM Event WHERE preferredMagnitudeID IS NOT NULL) LIMIT 1")
if [ "$CHECK_VAL" == "$SAFE_AUTHOR" ]; then
    echo "Injection successful: $CHECK_VAL"
else
    echo "ERROR: Database update failed. Expected $SAFE_AUTHOR, got $CHECK_VAL"
fi

# 7. Prepare user environment (Create output directory)
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
rm -f /home/ga/Documents/magnitude_provenance.json 2>/dev/null || true

# 8. Launch scolv for the agent
echo "--- Launching scolv ---"
kill_seiscomp_gui scolv
launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

wait_for_window "scolv" 30 || wait_for_window "Origin" 15 || true
sleep 3
dismiss_dialogs 2
focus_and_maximize "scolv" || focus_and_maximize "Origin" || true
sleep 2

# 9. Take initial screenshot
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_initial.png
chmod 666 /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="