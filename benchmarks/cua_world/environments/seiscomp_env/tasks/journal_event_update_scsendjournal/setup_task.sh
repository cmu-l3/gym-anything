#!/bin/bash
echo "=== Setting up journal_event_update_scsendjournal task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure scmaster is running (required for scsendjournal)
ensure_scmaster_running

# Verify event exists in database
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events in database: $EVENT_COUNT"
if [ "$EVENT_COUNT" = "0" ]; then
    echo "ERROR: No events in database. Re-importing from SCML fallback..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
    fi
fi

# Record the event public ID for later verification
EVENT_ID=$(seiscomp_db_query "SELECT publicID FROM PublicObject po JOIN Event e ON po._oid = e._oid LIMIT 1" 2>/dev/null)
echo "$EVENT_ID" > /tmp/expected_event_id.txt
echo "Event public ID: $EVENT_ID"

# Record initial journal entry count
INITIAL_JOURNAL=$(seiscomp_db_query "SELECT COUNT(*) FROM JournalEntry" 2>/dev/null || echo "0")
echo "$INITIAL_JOURNAL" > /tmp/initial_journal_count.txt

# Remove any existing report file
rm -f /home/ga/journal_report.txt 2>/dev/null || true

# Open a terminal for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 &" 2>/dev/null || \
    su - ga -c "DISPLAY=:1 xterm -geometry 120x40+0+0 -title 'SeisComP Terminal' -e bash &" 2>/dev/null || true
    sleep 3
fi

# Focus terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="