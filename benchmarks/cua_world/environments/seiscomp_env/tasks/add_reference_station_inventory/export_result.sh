#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time and start time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Check current station count
CURRENT_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Station;" 2>/dev/null || echo "0")

# Helper function to check file stats
check_file() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        local mtime=$(stat -c %Y "$filepath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$filepath" 2>/dev/null || echo "0")
        local created_during="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            created_during="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"created_during\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during\": false}"
    fi
}

# 1. Check SCML converted file
SCML_PATH="/home/ga/seiscomp/var/lib/inventory/iu_ctao_station.scml"
SCML_STAT=$(check_file "$SCML_PATH")

SCML_CONTAINS_STATION="false"
if [ -s "$SCML_PATH" ]; then
    if grep -qi "CTAO" "$SCML_PATH" && grep -qi "network code=\"IU\"" "$SCML_PATH"; then
        SCML_CONTAINS_STATION="true"
    fi
fi

# 2. Check etc/inventory XML file (copied for scconfig)
ETC_INV_PATH="/home/ga/seiscomp/etc/inventory/iu_ctao_station.xml"
ETC_INV_STAT=$(check_file "$ETC_INV_PATH")

# 3. Check station key file
KEY_PATH="/home/ga/seiscomp/etc/key/station_IU_CTAO"
KEY_STAT=$(check_file "$KEY_PATH")

# 4. Check database state
DB_STATION_EXISTS="false"
DB_LAT="0"
DB_LON="0"
DB_CHANNELS=0

# Query station coordinates
STA_DATA=$(mysql -u sysop -psysop seiscomp -N -e "SELECT latitude, longitude FROM Station WHERE code='CTAO' AND _parent_oid IN (SELECT _oid FROM Network WHERE code='IU') LIMIT 1;" 2>/dev/null)

if [ -n "$STA_DATA" ]; then
    DB_STATION_EXISTS="true"
    DB_LAT=$(echo "$STA_DATA" | awk '{print $1}')
    DB_LON=$(echo "$STA_DATA" | awk '{print $2}')
    
    # Query channels count for the station
    DB_CHANNELS=$(mysql -u sysop -psysop seiscomp -N -e "
        SELECT COUNT(*) FROM SensorLocation sl
        JOIN Stream s ON s._parent_oid = sl._oid
        WHERE sl._parent_oid IN (
            SELECT _oid FROM Station WHERE code='CTAO' AND _parent_oid IN (
                SELECT _oid FROM Network WHERE code='IU'
            )
        );" 2>/dev/null || echo "0")
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Generate JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_station_count": $INITIAL_COUNT,
    "current_station_count": $CURRENT_COUNT,
    "scml_file": $SCML_STAT,
    "scml_contains_station": $SCML_CONTAINS_STATION,
    "etc_inventory_file": $ETC_INV_STAT,
    "key_file": $KEY_STAT,
    "db_station_exists": $DB_STATION_EXISTS,
    "db_lat": "$DB_LAT",
    "db_lon": "$DB_LON",
    "db_channels": $DB_CHANNELS
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="