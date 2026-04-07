#!/bin/bash
echo "=== Exporting Import Focal Mechanism Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check if expected SCML file exists and was created during the task
FILE_PATH="/home/ga/noto_mechanism.scml"
FILE_EXISTS="false"
FILE_MTIME=0

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
fi

# Query the DB for the expected base Origin ID (from the Noto event)
EXPECTED_ORIGIN_ID=$(mysql -u sysop -psysop seiscomp -N -B -e "SELECT preferredOriginID FROM Event WHERE preferredOriginID IS NOT NULL ORDER BY _oid DESC LIMIT 1" 2>/dev/null)
if [ -z "$EXPECTED_ORIGIN_ID" ]; then
    EXPECTED_ORIGIN_ID="UNKNOWN"
fi

# Query the DB for the agent's inserted FocalMechanism
FM_FOUND="false"
FM_OID="0"
FM_TRIGGERING_ORIGIN_ID=""
FM_STRIKE="-999.0"
FM_DIP="-999.0"
FM_RAKE="-999.0"

FM_DATA=$(mysql -u sysop -psysop seiscomp -N -B -e "SELECT _oid, triggeringOriginID, IFNULL(nodalPlanes_nodalPlane1_strike_value, -999), IFNULL(nodalPlanes_nodalPlane1_dip_value, -999), IFNULL(nodalPlanes_nodalPlane1_rake_value, -999) FROM FocalMechanism WHERE creationInfo_agencyID='GCMT' ORDER BY _oid DESC LIMIT 1" 2>/dev/null)

if [ -n "$FM_DATA" ]; then
    FM_FOUND="true"
    FM_OID=$(echo "$FM_DATA" | awk '{print $1}')
    FM_TRIGGERING_ORIGIN_ID=$(echo "$FM_DATA" | awk '{print $2}')
    FM_STRIKE=$(echo "$FM_DATA" | awk '{print $3}')
    FM_DIP=$(echo "$FM_DATA" | awk '{print $4}')
    FM_RAKE=$(echo "$FM_DATA" | awk '{print $5}')
fi

# Query the DB for the agent's inserted MomentTensor (child of FocalMechanism)
MT_FOUND="false"
MT_SCALAR_MOMENT="-999.0"

if [ "$FM_FOUND" = "true" ]; then
    MT_DATA=$(mysql -u sysop -psysop seiscomp -N -B -e "SELECT scalarMoment_value FROM MomentTensor WHERE _parent_oid=$FM_OID ORDER BY _oid DESC LIMIT 1" 2>/dev/null)
    if [ -n "$MT_DATA" ]; then
        MT_FOUND="true"
        MT_SCALAR_MOMENT=$(echo "$MT_DATA" | awk '{print $1}')
    fi
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "expected_origin_id": "$EXPECTED_ORIGIN_ID",
    "scml_file_exists": $FILE_EXISTS,
    "scml_file_mtime": $FILE_MTIME,
    "fm_found": $FM_FOUND,
    "fm_oid": "$FM_OID",
    "fm_triggering_origin_id": "$FM_TRIGGERING_ORIGIN_ID",
    "fm_strike": $FM_STRIKE,
    "fm_dip": $FM_DIP,
    "fm_rake": $FM_RAKE,
    "mt_found": $MT_FOUND,
    "mt_scalar_moment": $MT_SCALAR_MOMENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="