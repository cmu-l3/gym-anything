#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Calendar Scheduling Engine Task ==="

WORKSPACE_DIR="/home/ga/workspace/calendar_engine"
sudo -u ga mkdir -p "$WORKSPACE_DIR/engine"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. engine/recurrence.py (BUG: Weekday mapping off-by-one)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/recurrence.py" << 'EOF'
import datetime

# BUG: weekday() returns 0 for Monday, but DAY_MAP maps MO to 1.
DAY_MAP = {
    'MO': 1, 'TU': 2, 'WE': 3, 'TH': 4, 'FR': 5, 'SA': 6, 'SU': 7
}

def get_next_occurrence(current_date, byday_list):
    """
    Find the next date that matches one of the given weekdays.
    byday_list: list of strings like ['MO', 'WE', 'FR']
    """
    next_date = current_date + datetime.timedelta(days=1)
    
    # Limit iterations to avoid infinite loops if bad input
    for _ in range(14):
        # BUG: weekday() is 0-indexed, DAY_MAP is 1-indexed
        if next_date.weekday() in [DAY_MAP[day] for day in byday_list]:
            return next_date
        next_date += datetime.timedelta(days=1)
        
    return None
EOF

# ─────────────────────────────────────────────────────────────
# 2. engine/timezone_handler.py (BUG: timedelta(hours=24) shifts wall-clock)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/timezone_handler.py" << 'EOF'
import datetime

def advance_one_day(dt: datetime.datetime) -> datetime.datetime:
    """
    Advance the given tz-aware datetime by exactly one calendar day.
    Must preserve the wall-clock time, even across DST transitions.
    """
    # BUG: Adding 24 absolute hours shifts wall-clock time if crossing DST boundary.
    # Should use timedelta(days=1) which Python's datetime handles correctly for wall-clock.
    return dt + datetime.timedelta(hours=24)
EOF

# ─────────────────────────────────────────────────────────────
# 3. engine/event_model.py (BUG: Inclusive all-day calculation)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/event_model.py" << 'EOF'
import datetime

class AllDayEvent:
    def __init__(self, title, dtstart, dtend):
        self.title = title
        self.dtstart = dtstart  # datetime.date
        self.dtend = dtend      # datetime.date (exclusive per RFC 5545)

    def get_duration_days(self):
        """Calculate the duration of the event in days."""
        # BUG: + 1 incorrectly treats dtend as inclusive. 
        # For a 1-day event (start Jan 1, end Jan 2), this returns 2.
        return (self.dtend - self.dtstart).days + 1
EOF

# ─────────────────────────────────────────────────────────────
# 4. engine/conflict_detector.py (BUG: Inverted overlap logic)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/conflict_detector.py" << 'EOF'
import datetime

def has_overlap(start_a: datetime.datetime, end_a: datetime.datetime,
                start_b: datetime.datetime, end_b: datetime.datetime) -> bool:
    """
    Check if time interval A [start_a, end_a) overlaps with B [start_b, end_b).
    """
    # BUG: This is the condition for NO overlap. It returns True when they DO NOT overlap.
    return (start_a >= end_b) or (start_b >= end_a)
EOF

# ─────────────────────────────────────────────────────────────
# 5. engine/ical_exporter.py (BUG: Wrong datetime format)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/engine/ical_exporter.py" << 'EOF'
import datetime

def format_ical_datetime(dt: datetime.datetime) -> str:
    """
    Format a datetime into RFC 5545 iCalendar format.
    Expected format for UTC: YYYYMMDDThhmmssZ
    Example: 20240315T133000Z
    """
    if dt.tzinfo is None or dt.tzinfo.utcoffset(dt) is None:
        # Floating time, no Z
        # BUG: isoformat includes hyphens and colons
        return dt.isoformat()
    else:
        # Convert to UTC and append Z
        dt_utc = dt.astimezone(datetime.timezone.utc)
        # BUG: isoformat returns e.g. 2024-03-15T13:30:00+00:00
        return dt_utc.isoformat() + "Z"
EOF

# ─────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_all.py" << 'EOF'
import unittest
import datetime
from zoneinfo import ZoneInfo

from engine.recurrence import get_next_occurrence
from engine.timezone_handler import advance_one_day
from engine.event_model import AllDayEvent
from engine.conflict_detector import has_overlap
from engine.ical_exporter import format_ical_datetime

class TestCalendarEngine(unittest.TestCase):

    def test_recurrence_weekday_mapping(self):
        # Monday, Jan 1, 2024
        dt = datetime.date(2024, 1, 1)
        # Next should be Wednesday, Jan 3
        next_dt = get_next_occurrence(dt, ['WE', 'FR'])
        self.assertEqual(next_dt, datetime.date(2024, 1, 3))
        
        # Next should be Friday, Jan 5
        next_dt2 = get_next_occurrence(next_dt, ['WE', 'FR'])
        self.assertEqual(next_dt2, datetime.date(2024, 1, 5))

    def test_timezone_dst_spring_forward(self):
        tz = ZoneInfo("America/New_York")
        # Day before DST spring forward (March 10, 2024 is the transition)
        dt = datetime.datetime(2024, 3, 9, 10, 0, tzinfo=tz)
        next_day = advance_one_day(dt)
        # Should still be 10:00 AM wall-clock time on March 10
        self.assertEqual(next_day.hour, 10)
        self.assertEqual(next_day.day, 10)

    def test_event_duration_exclusive_end(self):
        # One day event: Jan 1 to Jan 2 (exclusive end per RFC 5545)
        event = AllDayEvent("Test", datetime.date(2024, 1, 1), datetime.date(2024, 1, 2))
        self.assertEqual(event.get_duration_days(), 1)

    def test_conflict_detection_overlap(self):
        # Overlapping intervals
        start_a = datetime.datetime(2024, 1, 1, 10, 0)
        end_a   = datetime.datetime(2024, 1, 1, 12, 0)
        start_b = datetime.datetime(2024, 1, 1, 11, 0)
        end_b   = datetime.datetime(2024, 1, 1, 13, 0)
        self.assertTrue(has_overlap(start_a, end_a, start_b, end_b))

        # Non-overlapping intervals
        start_c = datetime.datetime(2024, 1, 1, 13, 0)
        end_c   = datetime.datetime(2024, 1, 1, 14, 0)
        self.assertFalse(has_overlap(start_a, end_a, start_c, end_c))

    def test_ical_export_format(self):
        # Expected: 20240315T133000Z
        dt = datetime.datetime(2024, 3, 15, 13, 30, tzinfo=datetime.timezone.utc)
        self.assertEqual(format_ical_datetime(dt), "20240315T133000Z")
        
        # Floating time (no timezone) - Expected: 20240315T133000
        dt_float = datetime.datetime(2024, 3, 15, 13, 30)
        self.assertEqual(format_ical_datetime(dt_float), "20240315T133000")

if __name__ == '__main__':
    unittest.main()
EOF

# Create a convenience test script
cat > "$WORKSPACE_DIR/run_tests.sh" << 'EOF'
#!/bin/bash
python3 -m unittest tests/test_all.py
EOF
chmod +x "$WORKSPACE_DIR/run_tests.sh"

# Fix permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Ensure timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Start VS Code with the workspace
echo "Starting VS Code..."
if ! pgrep -f "code.*calendar_engine" > /dev/null; then
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Take initial screenshot for evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="