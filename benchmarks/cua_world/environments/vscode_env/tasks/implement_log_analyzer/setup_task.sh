#!/bin/bash
set -e

echo "=== Setting up Implement Log Analyzer Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record timestamps for anti-gaming
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/log_analyzer"
sudo -u ga mkdir -p "$WORKSPACE_DIR/log_analyzer"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests/fixtures"

# Ensure pytest is installed
pip3 install -q pytest || true

# ──────────────────────────────────────────────────────────
# 1. Generate README.md and init
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Log Analyzer Library

Please implement the 5 modules in `log_analyzer/` to make the test suite pass.
Run `python3 -m pytest tests/ -v` to check your work.

### Expected Data Format
The `parser.parse_line` function should return a dictionary with these keys:
- `host` (str): e.g., '199.72.81.55'
- `timestamp` (str): e.g., '01/Jul/1995:00:00:01 -0400'
- `method` (str): e.g., 'GET'
- `path` (str): e.g., '/history/apollo/'
- `status` (int): e.g., 200
- `size` (int): e.g., 6245 (Note: if size is '-', it should be 0)
EOF
chown ga:ga "$WORKSPACE_DIR/README.md"

cat > "$WORKSPACE_DIR/log_analyzer/__init__.py" << 'EOF'
# log_analyzer package
EOF

# ──────────────────────────────────────────────────────────
# 2. Generate Stubs (The Task for the Agent)
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/log_analyzer/parser.py" << 'EOF'
import re

def parse_line(line: str) -> dict:
    """
    Parses a single Apache Combined Log Format line.
    Returns a dict with keys: host, timestamp, method, path, status, size.
    If parsing fails, return an empty dict {}.
    Remember to convert status and size to integers. If size is '-', treat it as 0.
    """
    raise NotImplementedError("Implement me!")

def parse_file(filepath: str) -> list:
    """Reads a file and parses all valid lines using parse_line."""
    raise NotImplementedError("Implement me!")
EOF

cat > "$WORKSPACE_DIR/log_analyzer/analyzer.py" << 'EOF'
def get_top_ips(logs: list, n: int = 5) -> list:
    """Returns a list of tuples (host, count) of the top n hosts/IPs."""
    raise NotImplementedError("Implement me!")

def get_status_distribution(logs: list) -> dict:
    """Returns a dict of status_code -> count."""
    raise NotImplementedError("Implement me!")
EOF

cat > "$WORKSPACE_DIR/log_analyzer/filter.py" << 'EOF'
import re

def filter_by_status(logs: list, status: int) -> list:
    """Returns a list of log dicts matching the exact status code."""
    raise NotImplementedError("Implement me!")

def filter_by_path(logs: list, path_regex: str) -> list:
    """Returns a list of log dicts where the path matches the given regex."""
    raise NotImplementedError("Implement me!")
EOF

cat > "$WORKSPACE_DIR/log_analyzer/alerter.py" << 'EOF'
def detect_error_spikes(logs: list, threshold_percent: float = 10.0) -> bool:
    """
    Returns True if the percentage of errors (status codes 400-599) 
    is strictly greater than threshold_percent.
    """
    raise NotImplementedError("Implement me!")
EOF

cat > "$WORKSPACE_DIR/log_analyzer/reporter.py" << 'EOF'
def generate_text_report(logs: list) -> str:
    """
    Generates a multiline text summary containing at least:
    - 'Total Requests: X'
    - 'Unique Hosts: Y'
    """
    raise NotImplementedError("Implement me!")
EOF

# ──────────────────────────────────────────────────────────
# 3. Generate Tests and Fixtures
# ──────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/fixtures/nasa_sample.log" << 'EOF'
199.72.81.55 - - [01/Jul/1995:00:00:01 -0400] "GET /history/apollo/ HTTP/1.0" 200 6245
unicomp6.unicomp.net - - [01/Jul/1995:00:00:06 -0400] "GET /shuttle/countdown/ HTTP/1.0" 200 3985
199.120.110.21 - - [01/Jul/1995:00:00:09 -0400] "GET /shuttle/missions/sts-73/mission-sts-73.html HTTP/1.0" 200 4085
burger.letters.com - - [01/Jul/1995:00:00:11 -0400] "GET /shuttle/countdown/liftoff.html HTTP/1.0" 304 0
199.120.110.21 - - [01/Jul/1995:00:00:11 -0400] "GET /shuttle/missions/sts-73/sts-73-patch-small.gif HTTP/1.0" 200 4179
burger.letters.com - - [01/Jul/1995:00:00:12 -0400] "GET /images/NASA-logosmall.gif HTTP/1.0" 304 0
burger.letters.com - - [01/Jul/1995:00:00:12 -0400] "GET /shuttle/countdown/video/livevideo.gif HTTP/1.0" 200 0
205.212.115.106 - - [01/Jul/1995:00:00:12 -0400] "GET /shuttle/countdown/countdown.html HTTP/1.0" 200 3985
d104.aa.net - - [01/Jul/1995:00:00:13 -0400] "GET /shuttle/countdown/ HTTP/1.0" 200 3985
129.94.144.152 - - [01/Jul/1995:00:00:13 -0400] "GET / HTTP/1.0" 200 7074
bad_log_line_here_with_no_format
129.94.144.152 - - [01/Jul/1995:00:00:14 -0400] "GET /images/ksclogo-medium.gif HTTP/1.0" 200 -
EOF

cat > "$WORKSPACE_DIR/tests/conftest.py" << 'EOF'
import pytest
import os

@pytest.fixture
def sample_logs():
    return [
        {'host': '199.72.81.55', 'timestamp': '01/Jul/1995:00:00:01 -0400', 'method': 'GET', 'path': '/history/apollo/', 'status': 200, 'size': 6245},
        {'host': 'unicomp6.unicomp.net', 'timestamp': '01/Jul/1995:00:00:06 -0400', 'method': 'GET', 'path': '/shuttle/countdown/', 'status': 200, 'size': 3985},
        {'host': '199.120.110.21', 'timestamp': '01/Jul/1995:00:00:09 -0400', 'method': 'GET', 'path': '/shuttle/missions/sts-73/mission-sts-73.html', 'status': 200, 'size': 4085},
        {'host': 'burger.letters.com', 'timestamp': '01/Jul/1995:00:00:11 -0400', 'method': 'GET', 'path': '/shuttle/countdown/liftoff.html', 'status': 304, 'size': 0},
        {'host': '199.120.110.21', 'timestamp': '01/Jul/1995:00:00:11 -0400', 'method': 'GET', 'path': '/shuttle/missions/sts-73/sts-73-patch-small.gif', 'status': 200, 'size': 4179},
        {'host': 'burger.letters.com', 'timestamp': '01/Jul/1995:00:00:12 -0400', 'method': 'GET', 'path': '/images/NASA-logosmall.gif', 'status': 304, 'size': 0},
        {'host': 'burger.letters.com', 'timestamp': '01/Jul/1995:00:00:12 -0400', 'method': 'GET', 'path': '/shuttle/countdown/video/livevideo.gif', 'status': 200, 'size': 0},
        {'host': '205.212.115.106', 'timestamp': '01/Jul/1995:00:00:12 -0400', 'method': 'GET', 'path': '/shuttle/countdown/countdown.html', 'status': 200, 'size': 3985},
        {'host': 'd104.aa.net', 'timestamp': '01/Jul/1995:00:00:13 -0400', 'method': 'GET', 'path': '/shuttle/countdown/', 'status': 200, 'size': 3985},
        {'host': '129.94.144.152', 'timestamp': '01/Jul/1995:00:00:13 -0400', 'method': 'GET', 'path': '/', 'status': 200, 'size': 7074},
        {'host': '129.94.144.152', 'timestamp': '01/Jul/1995:00:00:14 -0400', 'method': 'GET', 'path': '/images/ksclogo.gif', 'status': 404, 'size': 0}
    ]

@pytest.fixture
def fixture_path():
    return os.path.join(os.path.dirname(__file__), "fixtures", "nasa_sample.log")
EOF

cat > "$WORKSPACE_DIR/tests/test_parser.py" << 'EOF'
from log_analyzer.parser import parse_line, parse_file

def test_parse_valid_line():
    line = '199.72.81.55 - - [01/Jul/1995:00:00:01 -0400] "GET /history/apollo/ HTTP/1.0" 200 6245'
    res = parse_line(line)
    assert res['host'] == '199.72.81.55'
    assert res['method'] == 'GET'
    assert res['path'] == '/history/apollo/'
    assert res['status'] == 200
    assert res['size'] == 6245

def test_parse_invalid_line():
    assert parse_line("this is completely invalid") == {}

def test_parse_file_with_dash_size(fixture_path):
    logs = parse_file(fixture_path)
    assert len(logs) == 11
    # Check the last one which had '-' for size
    assert logs[-1]['size'] == 0
EOF

cat > "$WORKSPACE_DIR/tests/test_analyzer.py" << 'EOF'
from log_analyzer.analyzer import get_top_ips, get_status_distribution

def test_get_top_ips(sample_logs):
    top = get_top_ips(sample_logs, 2)
    assert len(top) == 2
    assert top[0][0] == "burger.letters.com"
    assert top[0][1] == 3

def test_get_status_distribution(sample_logs):
    dist = get_status_distribution(sample_logs)
    assert dist[200] == 8
    assert dist[304] == 2
    assert dist[404] == 1
EOF

cat > "$WORKSPACE_DIR/tests/test_filter.py" << 'EOF'
from log_analyzer.filter import filter_by_status, filter_by_path

def test_filter_by_status(sample_logs):
    res = filter_by_status(sample_logs, 304)
    assert len(res) == 2

def test_filter_by_path(sample_logs):
    res = filter_by_path(sample_logs, r"/shuttle/countdown/.*")
    assert len(res) == 5
EOF

cat > "$WORKSPACE_DIR/tests/test_alerter.py" << 'EOF'
from log_analyzer.alerter import detect_error_spikes

def test_detect_error_spikes_below_threshold(sample_logs):
    # 1 error out of 11 is ~9%
    assert not detect_error_spikes(sample_logs, 10.0)

def test_detect_error_spikes_above_threshold(sample_logs):
    logs = sample_logs + [{'status': 500}] * 2
    # 3 errors out of 13 is ~23%
    assert detect_error_spikes(logs, 10.0)
EOF

cat > "$WORKSPACE_DIR/tests/test_reporter.py" << 'EOF'
from log_analyzer.reporter import generate_text_report

def test_generate_text_report(sample_logs):
    rep = generate_text_report(sample_logs)
    assert "Total Requests: 11" in rep
    assert "Unique Hosts: 6" in rep
EOF

# Fix permissions
chown -R ga:ga "$WORKSPACE_DIR"

# ──────────────────────────────────────────────────────────
# 4. Hide original tests for Verifier Anti-gaming
# ──────────────────────────────────────────────────────────
sudo mkdir -p /var/lib/log_analyzer_tests
sudo cp -r "$WORKSPACE_DIR/tests/"* /var/lib/log_analyzer_tests/
sudo chown -R root:root /var/lib/log_analyzer_tests
sudo chmod -R 755 /var/lib/log_analyzer_tests

# ──────────────────────────────────────────────────────────
# 5. Start Application
# ──────────────────────────────────────────────────────────
# Start VSCode if not running
if ! pgrep -f "code" > /dev/null; then
    echo "Starting VSCode..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Wait and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="