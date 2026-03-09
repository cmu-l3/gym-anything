#!/bin/bash
echo "=== Setting up inventory_network_expansion_scconfig task ==="

source /workspace/scripts/task_utils.sh

TASK="inventory_network_expansion_scconfig"

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Clean up any previous IU network data ────────────────────────────────

echo "--- Cleaning previous IU network data ---"

# Remove IU stations from database inventory
seiscomp_db_query "DELETE FROM Station WHERE code IN ('ANMO','HRV','KONO')" 2>/dev/null || true
seiscomp_db_query "DELETE FROM Network WHERE code='IU'" 2>/dev/null || true

# Remove IU key files
rm -f "$SEISCOMP_ROOT/etc/key/station_IU_ANMO"
rm -f "$SEISCOMP_ROOT/etc/key/station_IU_HRV"
rm -f "$SEISCOMP_ROOT/etc/key/station_IU_KONO"

# Remove IU inventory files
rm -f "$SEISCOMP_ROOT/etc/inventory/iu_stations.xml"
rm -f "$SEISCOMP_ROOT/etc/inventory/iu_stations.scml"

echo "Previous IU data cleaned"

# ─── 3. Create realistic IU StationXML file ──────────────────────────────────

echo "--- Creating IU StationXML file ---"

mkdir -p /home/ga/Desktop

cat > /home/ga/Desktop/iu_stations.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<FDSNStationXML xmlns="http://www.fdsn.org/xml/station/1" schemaVersion="1.1">
  <Source>IRIS-DMC</Source>
  <Sender>IRIS-DMC</Sender>
  <Module>IRIS WEB SERVICE: fdsnws-station | version: 1.1.52</Module>
  <ModuleURI>http://service.iris.edu/fdsnws/station/1/query</ModuleURI>
  <Created>2024-01-15T00:00:00.000Z</Created>
  <Network code="IU" startDate="1988-01-01T00:00:00.000Z" restrictedStatus="open">
    <Description>Global Seismograph Network - IRIS/USGS</Description>

    <Station code="ANMO" startDate="2002-11-19T21:07:00.000Z" restrictedStatus="open">
      <Latitude>34.9459</Latitude>
      <Longitude>-106.4572</Longitude>
      <Elevation>1850.0</Elevation>
      <Site><Name>Albuquerque, New Mexico, USA</Name></Site>
      <CreationDate>2002-11-19T21:07:00.000Z</CreationDate>
      <Channel code="BHZ" locationCode="00" startDate="2018-07-09T17:00:00.000Z" restrictedStatus="open">
        <Latitude>34.9459</Latitude>
        <Longitude>-106.4572</Longitude>
        <Elevation>1632.0</Elevation>
        <Depth>188.0</Depth>
        <Azimuth>0.0</Azimuth>
        <Dip>-90.0</Dip>
        <Type>CONTINUOUS</Type>
        <Type>GEOPHYSICAL</Type>
        <SampleRate>40.0</SampleRate>
        <ClockDrift>0.0</ClockDrift>
        <Sensor><Description>Streckeisen STS-6A VBB Seismometer</Description></Sensor>
        <Response>
          <InstrumentSensitivity>
            <Value>3.35831e+09</Value>
            <Frequency>1.0</Frequency>
            <InputUnits><Name>m/s</Name></InputUnits>
            <OutputUnits><Name>counts</Name></OutputUnits>
          </InstrumentSensitivity>
        </Response>
      </Channel>
      <Channel code="BHN" locationCode="00" startDate="2018-07-09T17:00:00.000Z" restrictedStatus="open">
        <Latitude>34.9459</Latitude>
        <Longitude>-106.4572</Longitude>
        <Elevation>1632.0</Elevation>
        <Depth>188.0</Depth>
        <Azimuth>0.0</Azimuth>
        <Dip>0.0</Dip>
        <Type>CONTINUOUS</Type>
        <Type>GEOPHYSICAL</Type>
        <SampleRate>40.0</SampleRate>
        <ClockDrift>0.0</ClockDrift>
        <Sensor><Description>Streckeisen STS-6A VBB Seismometer</Description></Sensor>
        <Response>
          <InstrumentSensitivity>
            <Value>3.35831e+09</Value>
            <Frequency>1.0</Frequency>
            <InputUnits><Name>m/s</Name></InputUnits>
            <OutputUnits><Name>counts</Name></OutputUnits>
          </InstrumentSensitivity>
        </Response>
      </Channel>
      <Channel code="BHE" locationCode="00" startDate="2018-07-09T17:00:00.000Z" restrictedStatus="open">
        <Latitude>34.9459</Latitude>
        <Longitude>-106.4572</Longitude>
        <Elevation>1632.0</Elevation>
        <Depth>188.0</Depth>
        <Azimuth>90.0</Azimuth>
        <Dip>0.0</Dip>
        <Type>CONTINUOUS</Type>
        <Type>GEOPHYSICAL</Type>
        <SampleRate>40.0</SampleRate>
        <ClockDrift>0.0</ClockDrift>
        <Sensor><Description>Streckeisen STS-6A VBB Seismometer</Description></Sensor>
        <Response>
          <InstrumentSensitivity>
            <Value>3.35831e+09</Value>
            <Frequency>1.0</Frequency>
            <InputUnits><Name>m/s</Name></InputUnits>
            <OutputUnits><Name>counts</Name></OutputUnits>
          </InstrumentSensitivity>
        </Response>
      </Channel>
    </Station>

    <Station code="HRV" startDate="2012-10-18T14:00:00.000Z" restrictedStatus="open">
      <Latitude>42.5064</Latitude>
      <Longitude>-71.5583</Longitude>
      <Elevation>200.0</Elevation>
      <Site><Name>Adam Dziewonski Observatory (Oak Ridge), Massachusetts, USA</Name></Site>
      <CreationDate>2012-10-18T14:00:00.000Z</CreationDate>
      <Channel code="BHZ" locationCode="00" startDate="2019-10-22T18:00:00.000Z" restrictedStatus="open">
        <Latitude>42.5064</Latitude>
        <Longitude>-71.5583</Longitude>
        <Elevation>30.0</Elevation>
        <Depth>200.0</Depth>
        <Azimuth>0.0</Azimuth>
        <Dip>-90.0</Dip>
        <Type>CONTINUOUS</Type>
        <Type>GEOPHYSICAL</Type>
        <SampleRate>40.0</SampleRate>
        <ClockDrift>0.0</ClockDrift>
        <Sensor><Description>Streckeisen STS-6A VBB Seismometer</Description></Sensor>
        <Response>
          <InstrumentSensitivity>
            <Value>3.30919e+09</Value>
            <Frequency>1.0</Frequency>
            <InputUnits><Name>m/s</Name></InputUnits>
            <OutputUnits><Name>counts</Name></OutputUnits>
          </InstrumentSensitivity>
        </Response>
      </Channel>
      <Channel code="BHN" locationCode="00" startDate="2019-10-22T18:00:00.000Z" restrictedStatus="open">
        <Latitude>42.5064</Latitude>
        <Longitude>-71.5583</Longitude>
        <Elevation>30.0</Elevation>
        <Depth>200.0</Depth>
        <Azimuth>0.0</Azimuth>
        <Dip>0.0</Dip>
        <Type>CONTINUOUS</Type>
        <SampleRate>40.0</SampleRate>
        <ClockDrift>0.0</ClockDrift>
        <Sensor><Description>Streckeisen STS-6A VBB Seismometer</Description></Sensor>
        <Response>
          <InstrumentSensitivity>
            <Value>3.30919e+09</Value>
            <Frequency>1.0</Frequency>
            <InputUnits><Name>m/s</Name></InputUnits>
            <OutputUnits><Name>counts</Name></OutputUnits>
          </InstrumentSensitivity>
        </Response>
      </Channel>
      <Channel code="BHE" locationCode="00" startDate="2019-10-22T18:00:00.000Z" restrictedStatus="open">
        <Latitude>42.5064</Latitude>
        <Longitude>-71.5583</Longitude>
        <Elevation>30.0</Elevation>
        <Depth>200.0</Depth>
        <Azimuth>90.0</Azimuth>
        <Dip>0.0</Dip>
        <Type>CONTINUOUS</Type>
        <SampleRate>40.0</SampleRate>
        <ClockDrift>0.0</ClockDrift>
        <Sensor><Description>Streckeisen STS-6A VBB Seismometer</Description></Sensor>
        <Response>
          <InstrumentSensitivity>
            <Value>3.30919e+09</Value>
            <Frequency>1.0</Frequency>
            <InputUnits><Name>m/s</Name></InputUnits>
            <OutputUnits><Name>counts</Name></OutputUnits>
          </InstrumentSensitivity>
        </Response>
      </Channel>
    </Station>

    <Station code="KONO" startDate="1991-09-05T00:00:00.000Z" restrictedStatus="open">
      <Latitude>59.6491</Latitude>
      <Longitude>9.5982</Longitude>
      <Elevation>216.0</Elevation>
      <Site><Name>Kongsberg, Norway</Name></Site>
      <CreationDate>1991-09-05T00:00:00.000Z</CreationDate>
      <Channel code="BHZ" locationCode="00" startDate="2017-05-03T12:00:00.000Z" restrictedStatus="open">
        <Latitude>59.6491</Latitude>
        <Longitude>9.5982</Longitude>
        <Elevation>87.0</Elevation>
        <Depth>129.0</Depth>
        <Azimuth>0.0</Azimuth>
        <Dip>-90.0</Dip>
        <Type>CONTINUOUS</Type>
        <Type>GEOPHYSICAL</Type>
        <SampleRate>40.0</SampleRate>
        <ClockDrift>0.0</ClockDrift>
        <Sensor><Description>Streckeisen STS-2 High Gain</Description></Sensor>
        <Response>
          <InstrumentSensitivity>
            <Value>2.51640e+09</Value>
            <Frequency>1.0</Frequency>
            <InputUnits><Name>m/s</Name></InputUnits>
            <OutputUnits><Name>counts</Name></OutputUnits>
          </InstrumentSensitivity>
        </Response>
      </Channel>
      <Channel code="BHN" locationCode="00" startDate="2017-05-03T12:00:00.000Z" restrictedStatus="open">
        <Latitude>59.6491</Latitude>
        <Longitude>9.5982</Longitude>
        <Elevation>87.0</Elevation>
        <Depth>129.0</Depth>
        <Azimuth>0.0</Azimuth>
        <Dip>0.0</Dip>
        <Type>CONTINUOUS</Type>
        <SampleRate>40.0</SampleRate>
        <ClockDrift>0.0</ClockDrift>
        <Sensor><Description>Streckeisen STS-2 High Gain</Description></Sensor>
        <Response>
          <InstrumentSensitivity>
            <Value>2.51640e+09</Value>
            <Frequency>1.0</Frequency>
            <InputUnits><Name>m/s</Name></InputUnits>
            <OutputUnits><Name>counts</Name></OutputUnits>
          </InstrumentSensitivity>
        </Response>
      </Channel>
      <Channel code="BHE" locationCode="00" startDate="2017-05-03T12:00:00.000Z" restrictedStatus="open">
        <Latitude>59.6491</Latitude>
        <Longitude>9.5982</Longitude>
        <Elevation>87.0</Elevation>
        <Depth>129.0</Depth>
        <Azimuth>90.0</Azimuth>
        <Dip>0.0</Dip>
        <Type>CONTINUOUS</Type>
        <SampleRate>40.0</SampleRate>
        <ClockDrift>0.0</ClockDrift>
        <Sensor><Description>Streckeisen STS-2 High Gain</Description></Sensor>
        <Response>
          <InstrumentSensitivity>
            <Value>2.51640e+09</Value>
            <Frequency>1.0</Frequency>
            <InputUnits><Name>m/s</Name></InputUnits>
            <OutputUnits><Name>counts</Name></OutputUnits>
          </InstrumentSensitivity>
        </Response>
      </Channel>
    </Station>

  </Network>
</FDSNStationXML>
XMLEOF

chown ga:ga /home/ga/Desktop/iu_stations.xml
echo "IU StationXML written to /home/ga/Desktop/iu_stations.xml"

# ─── 4. Record baseline ─────────────────────────────────────────────────────

echo "--- Recording baseline ---"

INITIAL_NETWORK_COUNT=$(seiscomp_db_query "SELECT COUNT(DISTINCT code) FROM Network" 2>/dev/null || echo "0")
INITIAL_STATION_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Station" 2>/dev/null || echo "0")
echo "$INITIAL_NETWORK_COUNT" > /tmp/${TASK}_initial_network_count
echo "$INITIAL_STATION_COUNT" > /tmp/${TASK}_initial_station_count

echo "Initial networks: $INITIAL_NETWORK_COUNT, stations: $INITIAL_STATION_COUNT"

date +%s > /tmp/${TASK}_start_ts

rm -f /home/ga/Desktop/network_inventory.txt

# ─── 5. Launch scconfig and terminal ─────────────────────────────────────────

echo "--- Launching scconfig ---"
kill_seiscomp_gui scconfig

launch_seiscomp_gui scconfig

wait_for_window "scconfig" 60 || wait_for_window "Configuration" 30 || wait_for_window "SeisComP" 30

sleep 4
dismiss_dialogs 2
focus_and_maximize "scconfig" || focus_and_maximize "Configuration" || focus_and_maximize "SeisComP"
sleep 2

# Open terminal for CLI commands
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xfce4-terminal --title='SeisComP Terminal'" > /dev/null 2>&1 &
sleep 1
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal -- bash -i" > /dev/null 2>&1 &
fi
sleep 2

# ─── 6. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/${TASK}_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/${TASK}_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scconfig is open. IU StationXML on Desktop."
echo "Agent must: convert StationXML, import to DB, copy to etc/inventory,"
echo "configure bindings for 3 IU stations, verify with scinv ls."
