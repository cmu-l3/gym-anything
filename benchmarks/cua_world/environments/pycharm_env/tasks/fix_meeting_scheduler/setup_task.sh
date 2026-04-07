#!/bin/bash
echo "=== Setting up fix_meeting_scheduler task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_meeting_scheduler"
PROJECT_DIR="/home/ga/PycharmProjects/meeting_scheduler"

# Clean previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json /tmp/${TASK_NAME}_start_ts 2>/dev/null || true

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Create directories
su - ga -c "mkdir -p $PROJECT_DIR/scheduler $PROJECT_DIR/tests $PROJECT_DIR/data"

# --- requirements.txt ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
tzdata
EOF

# --- scheduler/__init__.py ---
touch "$PROJECT_DIR/scheduler/__init__.py"

# --- scheduler/models.py ---
cat > "$PROJECT_DIR/scheduler/models.py" << 'PYEOF'
from dataclasses import dataclass, field
from datetime import datetime
from typing import List

@dataclass
class Meeting:
    title: str
    start: datetime
    end: datetime

@dataclass
class User:
    username: str
    timezone: str  # e.g., "America/New_York"
    meetings: List[Meeting] = field(default_factory=list)
PYEOF

# --- scheduler/core.py (BUGGY) ---
cat > "$PROJECT_DIR/scheduler/core.py" << 'PYEOF'
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from typing import Optional
from .models import User, Meeting

class MeetingScheduler:
    def schedule_meeting(self, user: User, title: str, start: datetime, end: datetime) -> Optional[Meeting]:
        """
        Attempts to schedule a meeting for a user.
        Validates future time, working hours, and overlap.
        """
        self.validate_future_time(start)
        
        if not self.is_working_hours(user, start, end):
            raise ValueError(f"Meeting is outside working hours (9-17) for {user.timezone}")
            
        if self.check_overlap(user, start, end):
            raise ValueError("Meeting overlaps with an existing commitment")
            
        meeting = Meeting(title=title, start=start, end=end)
        user.meetings.append(meeting)
        return meeting

    def check_overlap(self, user: User, start: datetime, end: datetime) -> bool:
        """
        Checks if the proposed interval [start, end) overlaps with any existing meetings.
        """
        for meeting in user.meetings:
            # BUG 1: Overlap Logic
            # This logic checks if the NEW meeting starts or ends inside an existing meeting.
            # It fails to detect if the NEW meeting completely ENCLOSES an existing meeting.
            # Example: Existing 1:30-2:00. New 1:00-3:00.
            # 1:00 is not in [1:30, 2:00]. 3:00 is not in [1:30, 2:00]. Returns False (No Overlap).
            if (meeting.start <= start < meeting.end) or \
               (meeting.start < end <= meeting.end):
                return True
        return False

    def is_working_hours(self, user: User, start: datetime, end: datetime) -> bool:
        """
        Checks if the meeting is within 9 AM to 5 PM (17:00) in the USER's timezone.
        """
        # BUG 2: Timezone Ignorance
        # This uses the hour from the datetime object directly.
        # If 'start' is UTC (which it usually is in apps), this checks 9-17 UTC.
        # For a user in Tokyo (UTC+9), 10 AM local is 1 AM UTC. 
        # 1 AM UTC < 9, so it incorrectly rejects valid morning meetings in Tokyo.
        
        # Should convert to user's timezone: start.astimezone(ZoneInfo(user.timezone))
        if 9 <= start.hour < 17 and 9 <= end.hour <= 17:
            return True
        return False

    def validate_future_time(self, start: datetime):
        """Ensures the meeting is in the future."""
        # BUG 3: Offset-naive vs Offset-aware comparison
        # datetime.now() returns a naive datetime (local system time).
        # 'start' is typically timezone-aware.
        # This raises TypeError: can't compare offset-naive and offset-aware datetimes.
        if start < datetime.now():
            raise ValueError("Cannot schedule meetings in the past")
PYEOF

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
from datetime import datetime
from zoneinfo import ZoneInfo
from scheduler.models import User, Meeting
from scheduler.core import MeetingScheduler

@pytest.fixture
def scheduler():
    return MeetingScheduler()

@pytest.fixture
def nyc_user():
    return User(username="alice", timezone="America/New_York")

@pytest.fixture
def tokyo_user():
    return User(username="hiro", timezone="Asia/Tokyo")

@pytest.fixture
def london_user():
    return User(username="bob", timezone="Europe/London")
PYEOF

# --- tests/test_availability.py ---
cat > "$PROJECT_DIR/tests/test_availability.py" << 'PYEOF'
import pytest
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from scheduler.models import Meeting

UTC = ZoneInfo("UTC")

def test_overlap_exact_match(scheduler, nyc_user):
    start = datetime(2025, 10, 10, 14, 0, tzinfo=UTC)
    end = datetime(2025, 10, 10, 15, 0, tzinfo=UTC)
    nyc_user.meetings = [Meeting("Existing", start, end)]
    
    assert scheduler.check_overlap(nyc_user, start, end) is True

def test_overlap_partial_start(scheduler, nyc_user):
    # Existing: 14:00-15:00
    # New: 13:30-14:30
    existing_start = datetime(2025, 10, 10, 14, 0, tzinfo=UTC)
    existing_end = datetime(2025, 10, 10, 15, 0, tzinfo=UTC)
    nyc_user.meetings = [Meeting("Existing", existing_start, existing_end)]
    
    new_start = datetime(2025, 10, 10, 13, 30, tzinfo=UTC)
    new_end = datetime(2025, 10, 10, 14, 30, tzinfo=UTC)
    
    assert scheduler.check_overlap(nyc_user, new_start, new_end) is True

def test_overlap_partial_end(scheduler, nyc_user):
    # Existing: 14:00-15:00
    # New: 14:30-15:30
    existing_start = datetime(2025, 10, 10, 14, 0, tzinfo=UTC)
    existing_end = datetime(2025, 10, 10, 15, 0, tzinfo=UTC)
    nyc_user.meetings = [Meeting("Existing", existing_start, existing_end)]
    
    new_start = datetime(2025, 10, 10, 14, 30, tzinfo=UTC)
    new_end = datetime(2025, 10, 10, 15, 30, tzinfo=UTC)
    
    assert scheduler.check_overlap(nyc_user, new_start, new_end) is True

def test_overlap_enclosing(scheduler, nyc_user):
    # CRITICAL BUG TEST
    # Existing: 14:00-14:30
    # New: 13:00-15:00 (Completely encloses existing)
    existing_start = datetime(2025, 10, 10, 14, 0, tzinfo=UTC)
    existing_end = datetime(2025, 10, 10, 14, 30, tzinfo=UTC)
    nyc_user.meetings = [Meeting("Existing", existing_start, existing_end)]
    
    new_start = datetime(2025, 10, 10, 13, 0, tzinfo=UTC)
    new_end = datetime(2025, 10, 10, 15, 0, tzinfo=UTC)
    
    assert scheduler.check_overlap(nyc_user, new_start, new_end) is True

def test_no_overlap_adjacent(scheduler, nyc_user):
    # Existing: 14:00-15:00
    # New: 15:00-16:00 (Abutting is allowed)
    existing_start = datetime(2025, 10, 10, 14, 0, tzinfo=UTC)
    existing_end = datetime(2025, 10, 10, 15, 0, tzinfo=UTC)
    nyc_user.meetings = [Meeting("Existing", existing_start, existing_end)]
    
    new_start = datetime(2025, 10, 10, 15, 0, tzinfo=UTC)
    new_end = datetime(2025, 10, 10, 16, 0, tzinfo=UTC)
    
    assert scheduler.check_overlap(nyc_user, new_start, new_end) is False

def test_validate_future_time_bug(scheduler):
    # CRITICAL BUG TEST: TypeError on comparison
    future_time = datetime.now(timezone.utc) + timedelta(hours=1)
    # Should not raise TypeError or ValueError
    scheduler.validate_future_time(future_time)

def test_validate_past_time_raises(scheduler):
    past_time = datetime.now(timezone.utc) - timedelta(hours=1)
    with pytest.raises(ValueError):
        scheduler.validate_future_time(past_time)
PYEOF

# --- tests/test_timezones.py ---
cat > "$PROJECT_DIR/tests/test_timezones.py" << 'PYEOF'
import pytest
from datetime import datetime
from zoneinfo import ZoneInfo

UTC = ZoneInfo("UTC")

def test_working_hours_nyc_simple(scheduler, nyc_user):
    # NYC is UTC-4 or UTC-5
    # 10 AM NYC is 14:00 UTC (approx). Should be allowed.
    dt = datetime(2025, 10, 10, 14, 0, tzinfo=UTC) # 10 AM EDT
    end = datetime(2025, 10, 10, 15, 0, tzinfo=UTC)
    assert scheduler.is_working_hours(nyc_user, dt, end) is True

def test_working_hours_tokyo_morning(scheduler, tokyo_user):
    # CRITICAL BUG TEST
    # Tokyo is UTC+9.
    # 10 AM Tokyo = 01:00 UTC.
    # Buggy code sees "1" < 9 and rejects it.
    start = datetime(2025, 10, 10, 1, 0, tzinfo=UTC) # 10 AM JST
    end = datetime(2025, 10, 10, 2, 0, tzinfo=UTC)
    
    # Should be True (it is working hours in Tokyo)
    assert scheduler.is_working_hours(tokyo_user, start, end) is True

def test_working_hours_tokyo_night(scheduler, tokyo_user):
    # 10 PM Tokyo = 13:00 UTC.
    # Buggy code sees "13" (1 PM) which is 9 < 13 < 17, so accepts it.
    # CORRECT code should reject it (22:00 JST is outside 9-17).
    start = datetime(2025, 10, 10, 13, 0, tzinfo=UTC) # 22:00 JST
    end = datetime(2025, 10, 10, 14, 0, tzinfo=UTC)
    
    assert scheduler.is_working_hours(tokyo_user, start, end) is False

def test_working_hours_london_boundary(scheduler, london_user):
    # London is UTC+1 (BST in Oct if before switch, or UTC). Let's assume standard 9-5.
    # 16:59 London time should be OK.
    # If DST active (BST=UTC+1): 16:59 BST = 15:59 UTC.
    tz = ZoneInfo("Europe/London")
    start_local = datetime(2025, 7, 10, 16, 0, tzinfo=tz) # 4 PM local
    end_local = datetime(2025, 7, 10, 17, 0, tzinfo=tz)   # 5 PM local
    
    start_utc = start_local.astimezone(UTC)
    end_utc = end_local.astimezone(UTC)
    
    assert scheduler.is_working_hours(london_user, start_utc, end_utc) is True

def test_working_hours_cross_day_boundary(scheduler, tokyo_user):
    # 8 AM Tokyo = 23:00 UTC (previous day).
    # Buggy code sees 23, rejects.
    # 8 AM is outside 9-17 anyway, so should reject, but for right reason.
    # Let's try 9 AM Tokyo = 00:00 UTC.
    start = datetime(2025, 10, 10, 0, 0, tzinfo=UTC) # 09:00 JST
    end = datetime(2025, 10, 10, 1, 0, tzinfo=UTC)
    
    assert scheduler.is_working_hours(tokyo_user, start, end) is True
PYEOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Wait for PyCharm
wait_for_pycharm 120

# Open the project
setup_pycharm_project "$PROJECT_DIR" "meeting_scheduler"

echo "=== Task setup complete ==="