#!/bin/bash
echo "=== Setting up multi_event_magnitude_comparison_scolv task ==="

source /workspace/scripts/task_utils.sh

TASK="multi_event_magnitude_comparison_scolv"

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Ensure mainshock is in database ──────────────────────────────────────

echo "--- Verifying mainshock event ---"

MAINSHOCK_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events in database: $MAINSHOCK_COUNT"

if [ "$MAINSHOCK_COUNT" = "0" ] || [ -z "$MAINSHOCK_COUNT" ]; then
    echo "No events found, reimporting mainshock..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    QML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.xml"
    if [ ! -s "$SCML_FILE" ] && [ -s "$QML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            PYTHONPATH=$SEISCOMP_ROOT/lib/python:\$PYTHONPATH \
            python3 /workspace/scripts/convert_quakeml.py $QML_FILE $SCML_FILE" 2>/dev/null || true
    fi
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
        sleep 2
    fi
fi

# ─── 3. Remove any previously imported aftershock (clean slate) ──────────────

echo "--- Cleaning aftershock from database ---"

# Delete aftershock event if it exists (based on origin time match)
# The aftershock has origin time 2024-01-01T07:34:56, lat ~37.31, lon ~136.79
seiscomp_db_query "DELETE ar FROM Arrival ar
    JOIN Origin o ON ar._parent_oid = o._oid
    WHERE ABS(o.latitude_value - 37.3107) < 0.1
    AND ABS(o.longitude_value - 136.7858) < 0.1" 2>/dev/null || true

seiscomp_db_query "DELETE FROM OriginReference WHERE originID IN (
    SELECT po.publicID FROM PublicObject po
    JOIN Origin o ON o._oid = po._oid
    WHERE ABS(o.latitude_value - 37.3107) < 0.1
    AND ABS(o.longitude_value - 136.7858) < 0.1
)" 2>/dev/null || true

seiscomp_db_query "DELETE e FROM Event e
    JOIN Origin o ON e.preferredOriginID = (
        SELECT po.publicID FROM PublicObject po WHERE po._oid = o._oid
    )
    WHERE ABS(o.latitude_value - 37.3107) < 0.1
    AND ABS(o.longitude_value - 136.7858) < 0.1" 2>/dev/null || true

seiscomp_db_query "DELETE FROM Origin
    WHERE ABS(latitude_value - 37.3107) < 0.1
    AND ABS(longitude_value - 136.7858) < 0.1" 2>/dev/null || true

echo "Aftershock cleaned from database"

# ─── 4. Create aftershock QuakeML file on Desktop ────────────────────────────

echo "--- Creating aftershock QuakeML file ---"

mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/aftershock_data.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<q:quakeml xmlns="http://quakeml.org/xmlns/bed/1.2"
           xmlns:q="http://quakeml.org/xmlns/quakeml/1.2"
           xmlns:catalog="http://anss.org/xmlns/catalog/0.1">
<eventParameters publicID="quakeml:earthquake.usgs.gov/aftershock_query">
<event catalog:datasource="us" catalog:eventsource="us" catalog:eventid="6000m13n"
       publicID="quakeml:earthquake.usgs.gov/fdsnws/event/1/query?eventid=us6000m13n&amp;format=quakeml">
  <description><type>earthquake name</type><text>Noto Peninsula, Japan (aftershock)</text></description>
  <origin catalog:datasource="us" catalog:dataid="us6000m13n" catalog:eventsource="us" catalog:eventid="6000m13n"
          publicID="quakeml:earthquake.usgs.gov/product/origin/us6000m13n/us/1704099296040/product.xml">
    <time><value>2024-01-01T07:34:56.000Z</value></time>
    <longitude><value>136.7858</value></longitude>
    <latitude><value>37.3107</value></latitude>
    <depth><value>10000</value><uncertainty>5000</uncertainty></depth>
    <quality>
      <usedPhaseCount>45</usedPhaseCount>
      <usedStationCount>42</usedStationCount>
      <standardError>0.89</standardError>
      <azimuthalGap>52</azimuthalGap>
      <minimumDistance>1.2</minimumDistance>
    </quality>
    <evaluationMode>manual</evaluationMode>
    <creationInfo><agencyID>us</agencyID><creationTime>2024-01-02T12:00:00.000Z</creationTime></creationInfo>
  </origin>
  <magnitude catalog:datasource="us" catalog:dataid="us6000m13n" catalog:eventsource="us" catalog:eventid="6000m13n"
             publicID="quakeml:earthquake.usgs.gov/product/origin/us6000m13n/us/1704099296040/product.xml#magnitude">
    <mag><value>6.2</value><uncertainty>0.058</uncertainty></mag>
    <type>mww</type>
    <stationCount>38</stationCount>
    <originID>quakeml:earthquake.usgs.gov/product/origin/us6000m13n/us/1704099296040/product.xml</originID>
    <evaluationMode>manual</evaluationMode>
    <creationInfo><agencyID>us</agencyID><creationTime>2024-01-02T12:00:00.000Z</creationTime></creationInfo>
  </magnitude>
  <preferredOriginID>quakeml:earthquake.usgs.gov/product/origin/us6000m13n/us/1704099296040/product.xml</preferredOriginID>
  <preferredMagnitudeID>quakeml:earthquake.usgs.gov/product/origin/us6000m13n/us/1704099296040/product.xml#magnitude</preferredMagnitudeID>
  <type>earthquake</type>
  <creationInfo><agencyID>us</agencyID><creationTime>2024-01-02T12:00:00.000Z</creationTime></creationInfo>
</event>
</eventParameters>
</q:quakeml>
XMLEOF

chown ga:ga /home/ga/Desktop/aftershock_data.xml
echo "Aftershock QuakeML written to /home/ga/Desktop/aftershock_data.xml"

# ─── 5. Record baseline ─────────────────────────────────────────────────────

echo "--- Recording baseline ---"

INITIAL_EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "$INITIAL_EVENT_COUNT" > /tmp/${TASK}_initial_event_count
echo "Initial event count: $INITIAL_EVENT_COUNT"

date +%s > /tmp/${TASK}_start_ts

rm -f /home/ga/Desktop/event_comparison.txt

echo "Baseline: $INITIAL_EVENT_COUNT event(s), no comparison bulletin"

# ─── 6. Configure and launch scolv ──────────────────────────────────────────

echo "--- Configuring scolv ---"

cat > "$SEISCOMP_ROOT/etc/scolv.cfg" << 'CFGEOF'
loadEventDB = 1000
recordstream = sds://var/lib/archive
CFGEOF
chown ga:ga "$SEISCOMP_ROOT/etc/scolv.cfg"

echo "--- Launching scolv ---"
kill_seiscomp_gui scolv

launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

wait_for_window "scolv" 60 || wait_for_window "Origin" 30 || wait_for_window "SeisComP" 30

sleep 4
dismiss_dialogs 2
focus_and_maximize "scolv" || focus_and_maximize "Origin" || focus_and_maximize "SeisComP"
sleep 2

# Also open a terminal for CLI operations
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xfce4-terminal --title='SeisComP Terminal'" > /dev/null 2>&1 &
sleep 1
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal -- bash -i" > /dev/null 2>&1 &
fi
sleep 2

# ─── 7. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/${TASK}_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/${TASK}_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scolv is open with mainshock only. Aftershock QuakeML on Desktop."
echo "Agent must: import aftershock, verify both events in scolv, set aftershock"
echo "type/magnitude, export comparison bulletin."
