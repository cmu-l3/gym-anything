#!/bin/bash
echo "=== Setting up fix_subtitle_processor task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_subtitle_processor"
PROJECT_DIR="/home/ga/PycharmProjects/subtitle_processor"

# Cleanup previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/processor $PROJECT_DIR/tests $PROJECT_DIR/data"

# Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
EOF

# ============================================================
# processor/__init__.py
# ============================================================
touch "$PROJECT_DIR/processor/__init__.py"

# ============================================================
# processor/timestamp.py (BUG 1)
# ============================================================
cat > "$PROJECT_DIR/processor/timestamp.py" << 'PYEOF'
import re

class Timestamp:
    def __init__(self, hours=0, minutes=0, seconds=0, milliseconds=0):
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.milliseconds = milliseconds

    @classmethod
    def from_string(cls, timestamp_str):
        """Parse timestamp in format HH:MM:SS,mmm"""
        pattern = r'(\d{2}):(\d{2}):(\d{2}),(\d{3})'
        match = re.match(pattern, timestamp_str)
        if not match:
            raise ValueError(f"Invalid timestamp format: {timestamp_str}")
        
        return cls(
            int(match.group(1)),
            int(match.group(2)),
            int(match.group(3)),
            int(match.group(4))
        )

    def to_string(self):
        """Format as HH:MM:SS,mmm"""
        return f"{self.hours:02}:{self.minutes:02}:{self.seconds:02},{self.milliseconds:03}"

    def total_milliseconds(self):
        return (self.hours * 3600000 + 
                self.minutes * 60000 + 
                self.seconds * 1000 + 
                self.milliseconds)

    def add_milliseconds(self, ms):
        """Add milliseconds to the timestamp."""
        # BUG: This implementation adds directly to components without handling
        # carry-over correctly for seconds/minutes/hours.
        # e.g., 59s + 2000ms -> 61s (Invalid) instead of 1m 01s.
        
        self.milliseconds += ms
        
        # Handle millisecond overflow
        if self.milliseconds >= 1000:
            extra_seconds = self.milliseconds // 1000
            self.milliseconds %= 1000
            self.seconds += extra_seconds
            
        # BUG: Missing check for self.seconds >= 60
        # The fix should be:
        # if self.seconds >= 60:
        #     extra_minutes = self.seconds // 60
        #     self.seconds %= 60
        #     self.minutes += extra_minutes
        # ... and so on for hours
PYEOF

# ============================================================
# processor/converter.py (BUG 2)
# ============================================================
cat > "$PROJECT_DIR/processor/converter.py" << 'PYEOF'
from processor.timestamp import Timestamp

class FramerateConverter:
    def __init__(self, source_fps, target_fps):
        self.source_fps = float(source_fps)
        self.target_fps = float(target_fps)

    def scale_timestamp(self, timestamp):
        """
        Scale a timestamp based on framerate conversion.
        
        When converting from lower FPS (e.g. 24) to higher FPS (e.g. 25),
        video plays faster, so duration/timestamps should shrink.
        
        Ratio should be: source_fps / target_fps
        """
        total_ms = timestamp.total_milliseconds()
        
        # BUG: Incorrect ratio. Currently target/source.
        # If 24 -> 25, this is 1.041 (grows), but should be 0.96 (shrinks).
        ratio = self.target_fps / self.source_fps
        
        new_ms = int(total_ms * ratio)
        
        # Convert back to components
        hours = new_ms // 3600000
        new_ms %= 3600000
        
        minutes = new_ms // 60000
        new_ms %= 60000
        
        seconds = new_ms // 1000
        new_ms %= 1000
        
        return Timestamp(hours, minutes, seconds, new_ms)
PYEOF

# ============================================================
# processor/parser.py (BUG 3)
# ============================================================
cat > "$PROJECT_DIR/processor/parser.py" << 'PYEOF'
class SubtitleParser:
    def parse(self, file_path):
        """
        Parse an SRT file into a list of subtitle blocks.
        """
        subtitles = []
        current_block = []
        
        with open(file_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                
                if not line:
                    # Empty line indicates end of a block
                    if current_block:
                        subtitles.append(current_block)
                        current_block = []
                else:
                    current_block.append(line)
        
        # BUG: If the file doesn't end with a newline, the loop finishes
        # and the last `current_block` is never appended to `subtitles`.
        # Missing code:
        # if current_block:
        #     subtitles.append(current_block)
        
        return subtitles
PYEOF

# ============================================================
# Tests
# ============================================================

# conftest.py
cat > "$PROJECT_DIR/tests/conftest.py" << 'PYEOF'
import pytest
import os

@pytest.fixture
def sample_srt_path(tmp_path):
    p = tmp_path / "test.srt"
    p.write_text("1\n00:00:01,000 --> 00:00:02,000\nHello\n\n2\n00:00:03,000 --> 00:00:04,000\nWorld", encoding='utf-8')
    return str(p)
PYEOF

# test_timestamp.py
cat > "$PROJECT_DIR/tests/test_timestamp.py" << 'PYEOF'
from processor.timestamp import Timestamp

def test_timestamp_parsing():
    ts = Timestamp.from_string("01:02:03,456")
    assert ts.hours == 1
    assert ts.minutes == 2
    assert ts.seconds == 3
    assert ts.milliseconds == 456

def test_add_milliseconds_simple():
    ts = Timestamp(0, 0, 10, 0)
    ts.add_milliseconds(500)
    assert ts.to_string() == "00:00:10,500"

def test_add_milliseconds_rollover():
    """Test Bug 1: Seconds should roll over to minutes"""
    ts = Timestamp(0, 0, 59, 0)
    ts.add_milliseconds(2000) # +2 seconds
    
    # Expect 00:01:01,000
    # Buggy code produces 00:00:61,000
    assert ts.minutes == 1, f"Minutes not incremented. Got {ts.to_string()}"
    assert ts.seconds == 1, f"Seconds not modulo'd. Got {ts.to_string()}"
    assert ts.to_string() == "00:01:01,000"

def test_add_milliseconds_large_rollover():
    ts = Timestamp(0, 59, 59, 0)
    ts.add_milliseconds(1000)
    assert ts.to_string() == "01:00:00,000"
PYEOF

# test_converter.py
cat > "$PROJECT_DIR/tests/test_converter.py" << 'PYEOF'
from processor.converter import FramerateConverter
from processor.timestamp import Timestamp

def test_convert_identity():
    conv = FramerateConverter(24, 24)
    ts = Timestamp(0, 0, 10, 0) # 10s
    new_ts = conv.scale_timestamp(ts)
    assert new_ts.total_milliseconds() == 10000

def test_convert_24_to_25_shrinks_duration():
    """Test Bug 2: 24->25 fps means video plays faster, time should shrink"""
    conv = FramerateConverter(24, 25)
    ts = Timestamp(0, 0, 24, 0) # 24 seconds source
    
    # 24s @ 24fps = 576 frames
    # 576 frames @ 25fps = 23.04 seconds
    # Ratio = 24/25 = 0.96
    
    new_ts = conv.scale_timestamp(ts)
    total_ms = new_ts.total_milliseconds()
    
    # Buggy code does 25/24 = 1.041 -> 25000ms
    assert total_ms < 24000, f"Duration increased instead of decreased! Got {total_ms}ms"
    assert abs(total_ms - 23040) < 5 # Allow small rounding diff

def test_convert_25_to_24_grows_duration():
    conv = FramerateConverter(25, 24)
    ts = Timestamp(0, 0, 23, 40) # 23.04s
    new_ts = conv.scale_timestamp(ts)
    
    # Should become 24s
    assert abs(new_ts.total_milliseconds() - 24000) < 5
PYEOF

# test_parser.py
cat > "$PROJECT_DIR/tests/test_parser.py" << 'PYEOF'
from processor.parser import SubtitleParser
import os

def test_parse_normal_file(tmp_path):
    p = tmp_path / "normal.srt"
    p.write_text("1\n00:00:01 --> 00:00:02\nA\n\n2\n00:00:03 --> 00:00:04\nB\n\n", encoding='utf-8')
    
    parser = SubtitleParser()
    subs = parser.parse(str(p))
    assert len(subs) == 2

def test_parse_file_no_trailing_newline(tmp_path):
    """Test Bug 3: File ending without blank line should still capture last block"""
    p = tmp_path / "abrupt.srt"
    # Note: No \n\n at the very end
    content = "1\n00:00:01 --> 00:00:02\nBlock1\n\n2\n00:00:03 --> 00:00:04\nBlock2"
    p.write_text(content, encoding='utf-8')
    
    parser = SubtitleParser()
    subs = parser.parse(str(p))
    
    # Buggy code returns 1 (misses Block2)
    assert len(subs) == 2, f"Failed to parse last block. Found {len(subs)} blocks"
    assert subs[1][-1] == "Block2"
PYEOF

# ============================================================
# Create Sample Real Data
# ============================================================
cat > "$PROJECT_DIR/data/sample.srt" << 'SRTEOF'
1
00:00:15,400 --> 00:00:18,200
(DRAMATIC MUSIC PLAYING)

2
00:00:58,900 --> 00:01:02,100
If we hurry, we can make the
last train to Paris.

3
00:01:02,200 --> 00:01:04,500
Wait for me!
SRTEOF

# ============================================================
# Setup PyCharm
# ============================================================

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch PyCharm
setup_pycharm_project "$PROJECT_DIR" "subtitle_processor"

# Create initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="