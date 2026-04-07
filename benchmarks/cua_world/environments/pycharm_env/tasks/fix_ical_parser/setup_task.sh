#!/bin/bash
echo "=== Setting up fix_ical_parser task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/PycharmProjects/pycal_importer"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/pycal_importer"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/samples"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# --- 1. Create Data Class (event.py) ---
cat > "$PROJECT_DIR/pycal_importer/event.py" << 'EOF'
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

@dataclass
class Event:
    summary: str
    description: Optional[str]
    start: datetime
    end: Optional[datetime]
    location: Optional[str]
    all_day: bool = False
EOF

# --- 2. Create Buggy Parser (parser.py) ---
cat > "$PROJECT_DIR/pycal_importer/parser.py" << 'EOF'
from typing import List, Optional
from datetime import datetime
from .event import Event

def parse_ics(content: str) -> List[Event]:
    """
    Parses iCalendar (RFC 5545) content and returns a list of Events.
    """
    events = []
    current_event = {}
    in_event = False
    
    # BUG 1: Naive splitlines. Does not handle line unfolding (RFC 5545 3.1).
    # Long lines that are split with CRLF + space will be treated as separate lines.
    lines = content.splitlines()
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # BUG 2: Naive splitting on first colon.
        # Fails on properties with parameters like "DTSTART;TZID=America/New_York:2023..."
        if ':' in line:
            key, value = line.split(':', 1)
        else:
            continue
            
        if key == 'BEGIN' and value == 'VEVENT':
            in_event = True
            current_event = {}
        elif key == 'END' and value == 'VEVENT':
            in_event = False
            if 'SUMMARY' in current_event and 'DTSTART' in current_event:
                events.append(_create_event_from_dict(current_event))
            current_event = {}
        elif in_event:
            current_event[key] = value

    return events

def _create_event_from_dict(data: dict) -> Event:
    # BUG 3: Date parsing assumes fixed format %Y%m%dT%H%M%S
    # Crashes on VALUE=DATE (e.g. 20230101) or Timezones
    
    dt_start_str = data.get('DTSTART', '')
    dt_end_str = data.get('DTEND')
    
    # This will fail for date-only strings (len 8) or if params are in the key
    start_dt = datetime.strptime(dt_start_str, "%Y%m%dT%H%M%S")
    
    end_dt = None
    if dt_end_str:
        end_dt = datetime.strptime(dt_end_str, "%Y%m%dT%H%M%S")
        
    return Event(
        summary=data.get('SUMMARY', ''),
        description=data.get('DESCRIPTION'),
        start=start_dt,
        end=end_dt,
        location=data.get('LOCATION'),
        all_day=False
    )
EOF

# --- 3. Create Tests (tests/test_parser.py) ---
cat > "$PROJECT_DIR/tests/test_parser.py" << 'EOF'
import pytest
from datetime import datetime
from pycal_importer.parser import parse_ics

def test_simple_event():
    ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:Simple Meeting
DTSTART:20230101T100000
DTEND:20230101T110000
END:VEVENT
END:VCALENDAR"""
    events = parse_ics(ics)
    assert len(events) == 1
    assert events[0].summary == "Simple Meeting"
    assert events[0].start == datetime(2023, 1, 1, 10, 0, 0)

def test_line_unfolding_description():
    # RFC 5545: Lines folded with CRLF + space should be unfolded
    ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:Folded Description
DTSTART:20230101T120000
DESCRIPTION:This is a very long description that h
 as been folded onto multiple lines
  starting with a space.
END:VEVENT
END:VCALENDAR"""
    events = parse_ics(ics)
    assert len(events) == 1
    # The parser should merge the lines and remove the leading space of continuation lines
    expected = "This is a very long description that has been folded onto multiple lines starting with a space."
    assert events[0].description == expected

def test_property_parameters_and_timezone():
    # Properties can have parameters separated by semicolons
    ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:Timezone Event
DTSTART;TZID=America/New_York:20230101T090000
END:VEVENT
END:VCALENDAR"""
    events = parse_ics(ics)
    assert len(events) == 1
    # Ensure date is parsed (naive or aware is fine, as long as it parses)
    assert events[0].start.year == 2023
    assert events[0].start.hour == 9

def test_all_day_event():
    # All day events have VALUE=DATE and YYYYMMDD format (no Time component)
    ics = """BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:Birthday
DTSTART;VALUE=DATE:20230520
END:VEVENT
END:VCALENDAR"""
    events = parse_ics(ics)
    assert len(events) == 1
    assert events[0].all_day is True
    assert events[0].start.year == 2023
    assert events[0].start.month == 5
    assert events[0].start.day == 20
EOF

# --- 4. Create Init files ---
touch "$PROJECT_DIR/pycal_importer/__init__.py"
touch "$PROJECT_DIR/tests/__init__.py"

# --- 5. Sample Files ---
cat > "$PROJECT_DIR/samples/google_meeting.ics" << 'EOF'
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Google Inc//Google Calendar 70.9054//EN
BEGIN:VEVENT
DTSTART:20231015T143000Z
DTEND:20231015T153000Z
DTSTAMP:20231001T100000Z
UID:123456@google.com
SUMMARY:Project Sync
DESCRIPTION:Agenda:\n1. Update on Q4 goals\n2. B
 udget review\n3. Team building event planning
LOCATION:Conference Room A
END:VEVENT
END:VCALENDAR
EOF

# --- 6. Set Permissions ---
chown -R ga:ga "$PROJECT_DIR"

# --- 7. Setup IDE ---
# Launch PyCharm with the project
if ! pgrep -f "pycharm" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh '$PROJECT_DIR' > /tmp/pycharm_log.txt 2>&1 &"
    
    # Wait for project to load
    wait_for_project_loaded "pycal_importer" 120
    
    # Maximize
    focus_pycharm_window
fi

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="