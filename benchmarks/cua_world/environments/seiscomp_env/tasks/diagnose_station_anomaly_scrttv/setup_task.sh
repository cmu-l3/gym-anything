#!/bin/bash
echo "=== Setting up diagnose_station_anomaly_scrttv task ==="

source /workspace/scripts/task_utils.sh

TASK="diagnose_station_anomaly_scrttv"
TARGET_STATION="KWP"
SDS_ROOT="$SEISCOMP_ROOT/var/lib/archive"

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Inject anomalous waveform data for the target station ─────────────

echo "--- Injecting station anomaly for GE.$TARGET_STATION ---"

# Create synthetic anomalous miniSEED for GE.KWP
# The anomaly: replace KWP waveform with a file containing noise spikes and gaps
# while other stations have clean data

YEAR=2024
DOY=001

# First ensure all stations have SDS data
for STA in GSI SANI BKB; do
    SDS_DIR="$SDS_ROOT/$YEAR/GE/$STA/BHZ.D"
    if [ ! -d "$SDS_DIR" ]; then
        mkdir -p "$SDS_DIR"
        # Copy from bundled data if available
        BUNDLED="$SEISCOMP_ROOT/var/lib/archive/GE.${STA}..BHZ.2024.001.mseed"
        [ -f "$BUNDLED" ] && cp "$BUNDLED" "$SDS_DIR/GE.${STA}..BHZ.D.${YEAR}.${DOY}"
    fi
done

# Create anomalous KWP data: generate a miniSEED with spikes using Python
python3 << 'PYEOF'
import struct
import os
import random

SDS_ROOT = os.environ.get("SEISCOMP_ROOT", "/home/ga/seiscomp") + "/var/lib/archive"
TARGET_DIR = f"{SDS_ROOT}/2024/GE/KWP/BHZ.D"
os.makedirs(TARGET_DIR, exist_ok=True)

# Read a good station's data as template
template_path = None
for sta in ["GSI", "SANI", "BKB"]:
    p = f"{SDS_ROOT}/2024/GE/{sta}/BHZ.D/GE.{sta}..BHZ.D.2024.001"
    if os.path.exists(p):
        template_path = p
        break

if template_path:
    with open(template_path, "rb") as f:
        data = bytearray(f.read())

    # Corrupt the data: inject periodic noise spikes into the data payload
    # miniSEED records are typically 4096 bytes. We'll corrupt every 3rd record's
    # data section (bytes 64 onward contain encoded samples)
    record_size = 4096
    num_records = len(data) // record_size

    for i in range(num_records):
        offset = i * record_size
        # Change station name in header to KWP (bytes 8-12 in SEED header)
        # SEED fixed header: seq(6) + quality(1) + reserved(1) + station(5)
        data[8:13] = b"KWP  "

        # Every 3rd record: inject spike noise
        if i % 3 == 0:
            # Zero out a portion of data section (simulate data gap)
            gap_start = offset + 64
            gap_end = min(gap_start + 512, offset + record_size)
            for j in range(gap_start, gap_end):
                if j < len(data):
                    data[j] = 0

            # Also inject random noise bytes at end of record
            spike_start = offset + record_size - 256
            for j in range(spike_start, offset + record_size):
                if j < len(data):
                    data[j] = random.randint(0, 255)

    target_file = f"{TARGET_DIR}/GE.KWP..BHZ.D.2024.001"
    with open(target_file, "wb") as f:
        f.write(data)
    print(f"Anomalous KWP data written: {target_file} ({len(data)} bytes)")
else:
    # Fallback: create a small file with mostly zeros (data gap)
    target_file = f"{TARGET_DIR}/GE.KWP..BHZ.D.2024.001"
    with open(target_file, "wb") as f:
        f.write(b"\x00" * 4096 * 5)
    print(f"Fallback anomalous KWP data written: {target_file}")
PYEOF

# Also add TOLI with clean data (copy from another station and rename)
TOLI_DIR="$SDS_ROOT/$YEAR/GE/TOLI/BHZ.D"
mkdir -p "$TOLI_DIR"
if [ ! -f "$TOLI_DIR/GE.TOLI..BHZ.D.${YEAR}.${DOY}" ]; then
    # Use GSI data as template for TOLI (clean data)
    SRC_FILE="$SDS_ROOT/$YEAR/GE/GSI/BHZ.D/GE.GSI..BHZ.D.${YEAR}.${DOY}"
    if [ -f "$SRC_FILE" ]; then
        python3 -c "
import os
with open('$SRC_FILE', 'rb') as f:
    data = bytearray(f.read())
# Rename station to TOLI in all records
rec_size = 4096
for i in range(len(data) // rec_size):
    data[i*rec_size+8:i*rec_size+13] = b'TOLI '
with open('$TOLI_DIR/GE.TOLI..BHZ.D.${YEAR}.${DOY}', 'wb') as f:
    f.write(data)
print('Clean TOLI data created')
" 2>/dev/null || true
    fi
fi

chown -R ga:ga "$SDS_ROOT"

# ─── 3. Set up initial module bindings for ALL stations ───────────────────

echo "--- Setting up initial module bindings for all stations ---"

# All 5 stations should have scautopick binding initially
for STA in TOLI GSI KWP SANI BKB; do
    KEY_FILE="$SEISCOMP_ROOT/etc/key/station_GE_${STA}"
    cat > "$KEY_FILE" << BINDEOF
scautopick
scamp
BINDEOF
done
chown -R ga:ga "$SEISCOMP_ROOT/etc/key"

echo "All 5 stations have scautopick + scamp bindings"

# ─── 4. Record baseline state ────────────────────────────────────────────

echo "--- Recording baseline state ---"

# Count stations with bindings
INITIAL_BINDING_COUNT=5
echo "$INITIAL_BINDING_COUNT" > /tmp/${TASK}_initial_binding_count

# Record that KWP currently has bindings
echo "true" > /tmp/${TASK}_kwp_initial_has_bindings

# Record timestamp
date +%s > /tmp/${TASK}_start_ts

# Remove any existing report file
rm -f /home/ga/Desktop/station_anomaly_report.txt

echo "Baseline recorded: all 5 stations have bindings, no report file exists"

# ─── 5. Configure and launch scrttv ──────────────────────────────────────

echo "--- Configuring scrttv ---"

cat > "$SEISCOMP_ROOT/etc/scrttv.cfg" << 'CFGEOF'
streams.codes = GE.TOLI..BHZ, GE.GSI..BHZ, GE.KWP..BHZ, GE.SANI..BHZ, GE.BKB..BHZ
recordstream = sdsarchive://var/lib/archive
CFGEOF
chown ga:ga "$SEISCOMP_ROOT/etc/scrttv.cfg"

# ─── 6. Kill existing GUIs and launch scrttv ─────────────────────────────

echo "--- Launching scrttv ---"
kill_seiscomp_gui scrttv
kill_seiscomp_gui scconfig

launch_seiscomp_gui scrttv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp"

wait_for_window "scrttv" 60 || wait_for_window "TraceView" 30 || wait_for_window "SeisComP" 30

sleep 4
dismiss_dialogs 2
focus_and_maximize "scrttv" || focus_and_maximize "TraceView" || focus_and_maximize "SeisComP"
sleep 2

# ─── 7. Take initial screenshot ──────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/${TASK}_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/${TASK}_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scrttv is open showing waveforms from all 5 GE stations."
echo "One station (hidden from agent) has anomalous data."
echo "Agent must: identify bad station, disable its bindings in scconfig, write report."
