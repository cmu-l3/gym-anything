#!/bin/bash
echo "=== Setting up export_event_bulletin_scbulletin task ==="

source /workspace/scripts/task_utils.sh

TASK="export_event_bulletin_scbulletin"
OUTPUT_FILE="/home/ga/Desktop/noto_bulletin.txt"

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Verify event data is in the database ─────────────────────────────────

echo "--- Verifying event data ---"

EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events in database: $EVENT_COUNT"

if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found, attempting to reimport..."
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

EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events after verification: $EVENT_COUNT"

# ─── 3. Delete any stale bulletin file on Desktop ─────────────────────────────

echo "--- Removing any stale bulletin file ---"
rm -f "$OUTPUT_FILE" 2>/dev/null || true
chown ga:ga /home/ga/Desktop/ 2>/dev/null || true

if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Output file cleared (starting from no bulletin)"
else
    echo "WARN: Could not remove $OUTPUT_FILE"
fi

# ─── 4. Record baseline state ────────────────────────────────────────────────

echo "--- Recording baseline state ---"
date +%s > /tmp/${TASK}_start_ts
echo "Baseline timestamp recorded"

# Ensure SeisComP binaries are on PATH for ga user
su - ga -c "echo 'PATH=/home/ga/seiscomp/bin:\$PATH' >> /home/ga/.bashrc" 2>/dev/null || true

# ─── 5. Ensure a terminal emulator is available ───────────────────────────────

echo "--- Ensuring terminal is available ---"
which gnome-terminal xterm xfce4-terminal konsole 2>/dev/null | head -1 | xargs -I{} echo "Terminal found: {}"

# Open a terminal pre-positioned on the Desktop for agent convenience
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal\|xterm"; then
    echo "Terminal already open"
else
    # Launch a terminal (gnome-terminal is standard on GNOME)
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal -- bash -i" > /dev/null 2>&1 &
    sleep 3
fi

# ─── 6. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
sleep 2
take_screenshot /tmp/${TASK}_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/${TASK}_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Database has $EVENT_COUNT event(s)."
echo "Agent must open terminal and run scbulletin to export bulletin to $OUTPUT_FILE"
echo "SeisComP bin: $SEISCOMP_ROOT/bin/scbulletin"
