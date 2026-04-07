#!/bin/bash
set -e
echo "=== Setting up build_log_analyzer task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/log_analyzer"
ANALYZER_DIR="$PROJECT_DIR/analyzer"
TESTS_DIR="$PROJECT_DIR/tests"
DATA_DIR="$PROJECT_DIR/sample_logs"

# Clean previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/build_log_analyzer_result.json /tmp/task_start_time 2>/dev/null || true

# Create directories
mkdir -p "$ANALYZER_DIR"
mkdir -p "$TESTS_DIR"
mkdir -p "$DATA_DIR"

# Set permissions
chown -R ga:ga "/home/ga/PycharmProjects"

# --- 1. Create Data (Access Logs) ---
# Generate a realistic Apache Combined Log Format file
cat > "$DATA_DIR/access.log" << 'EOF'
192.168.1.105 - - [10/Oct/2023:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326 "https://www.google.com/" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"
192.168.1.105 - - [10/Oct/2023:13:55:36 -0700] "GET /css/styles.css HTTP/1.1" 200 784 "http://www.example.com/index.html" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
192.168.1.105 - - [10/Oct/2023:13:55:37 -0700] "GET /images/logo.png HTTP/1.1" 200 12453 "http://www.example.com/index.html" "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
10.0.0.42 - - [10/Oct/2023:14:02:11 -0700] "POST /api/login HTTP/1.1" 401 45 "http://www.example.com/login" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
10.0.0.42 - - [10/Oct/2023:14:02:15 -0700] "POST /api/login HTTP/1.1" 401 45 "http://www.example.com/login" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
10.0.0.42 - - [10/Oct/2023:14:02:22 -0700] "POST /api/login HTTP/1.1" 401 45 "http://www.example.com/login" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
10.0.0.42 - - [10/Oct/2023:14:02:30 -0700] "POST /api/login HTTP/1.1" 200 124 "http://www.example.com/login" "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
45.33.22.11 - - [10/Oct/2023:14:10:05 -0700] "GET /robots.txt HTTP/1.1" 404 153 "-" "Googlebot/2.1 (+http://www.google.com/bot.html)"
192.168.1.105 - - [10/Oct/2023:14:15:22 -0700] "GET /api/v1/users HTTP/1.1" 200 4522 "http://www.example.com/dashboard" "Mozilla/5.0"
192.168.1.105 - - [10/Oct/2023:14:15:25 -0700] "GET /api/v1/stats HTTP/1.1" 500 0 "http://www.example.com/dashboard" "Mozilla/5.0"
EOF
# (In a real scenario, this would be much longer, but this suffices for the file reading test)

# --- 2. Create Implementation Stubs ---

# requirements.txt
echo "pytest>=7.0" > "$PROJECT_DIR/requirements.txt"

# analyzer/__init__.py
touch "$ANALYZER_DIR/__init__.py"

# analyzer/parser.py
cat > "$ANALYZER_DIR/parser.py" << 'EOF'
import re
from datetime import datetime
from typing import Dict, Any, Optional, List

# Apache Combined Log Format Regex (Hint: You might need to adjust this)
# Format: %h %l %u %t "%r" %>s %b "%{Referer}i" "%{User-Agent}i"
LOG_PATTERN = re.compile(r'') 

def parse_log_line(line: str) -> Optional[Dict[str, Any]]:
    """
    Parse a single Apache Combined Log Format line.

    Args:
        line: Raw log line string

    Returns:
        Dict with keys:
            ip (str): Remote IP
            user (str): Remote user (or '-')
            timestamp (datetime): Parsed datetime object (use format %d/%b/%Y:%H:%M:%S %z)
            method (str): HTTP method (e.g., GET)
            path (str): Request path (e.g., /index.html)
            protocol (str): HTTP protocol (e.g., HTTP/1.1)
            status (int): HTTP status code
            size (int): Response size in bytes (0 if '-')
            referer (str): Referer header
            user_agent (str): User-Agent header
        Returns None if line does not match format.
    """
    raise NotImplementedError("Implement parse_log_line")

def parse_log_file(filepath: str) -> List[Dict[str, Any]]:
    """
    Parse a log file and return a list of parsed entry dicts.
    Should skip empty or malformed lines.
    """
    raise NotImplementedError("Implement parse_log_file")
EOF

# analyzer/stats.py
cat > "$ANALYZER_DIR/stats.py" << 'EOF'
from typing import List, Dict, Tuple, Any
from collections import Counter, defaultdict

def status_code_summary(entries: List[Dict[str, Any]]) -> Dict[str, int]:
    """
    Return a summary of status codes grouped by category.
    Returns dictionary with keys '2xx', '3xx', '4xx', '5xx'.
    All keys must be present even if count is 0.
    """
    raise NotImplementedError("Implement status_code_summary")

def top_endpoints(entries: List[Dict[str, Any]], n: int = 10) -> List[Tuple[str, int]]:
    """
    Return the top N endpoints (paths) by request count.
    Returns list of (path, count) tuples, sorted by count desc, then path asc.
    """
    raise NotImplementedError("Implement top_endpoints")

def bandwidth_by_endpoint(entries: List[Dict[str, Any]]) -> Dict[str, int]:
    """
    Calculate total bandwidth (sum of size) used per endpoint path.
    Returns dictionary mapping path -> total_bytes.
    """
    raise NotImplementedError("Implement bandwidth_by_endpoint")
EOF

# analyzer/anomaly.py
cat > "$ANALYZER_DIR/anomaly.py" << 'EOF'
from typing import List, Dict, Any
from datetime import timedelta

def detect_brute_force(entries: List[Dict[str, Any]], 
                       threshold: int = 10, 
                       window_minutes: int = 5) -> List[Dict[str, Any]]:
    """
    Detect IPs with excessive 401 Unauthorized responses within a sliding time window.
    
    Args:
        entries: List of parsed log entries
        threshold: Minimum number of 401s to trigger detection
        window_minutes: Sliding window size in minutes
        
    Returns:
        List of dicts containing:
        {
            'ip': str,
            'count': int (number of 401s in the window),
            'first_seen': datetime (of first 401 in window),
            'last_seen': datetime (of last 401 in window)
        }
        Sorted by count descending.
    """
    raise NotImplementedError("Implement detect_brute_force")
EOF

# --- 3. Create Tests ---

# tests/__init__.py
touch "$TESTS_DIR/__init__.py"

# tests/conftest.py
cat > "$TESTS_DIR/conftest.py" << 'EOF'
import pytest
from datetime import datetime, timezone, timedelta

@pytest.fixture
def sample_log_line():
    return '127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326 "http://www.example.com/start.html" "Mozilla/4.08 [en] (Win98; I ;Nav)"'

@pytest.fixture
def parsed_entries():
    # Helper to generate mock entries
    base_time = datetime(2023, 10, 10, 12, 0, 0, tzinfo=timezone.utc)
    return [
        {
            'ip': '192.168.1.1', 'status': 200, 'path': '/home', 'size': 100,
            'timestamp': base_time, 'method': 'GET'
        },
        {
            'ip': '192.168.1.1', 'status': 404, 'path': '/missing', 'size': 50,
            'timestamp': base_time + timedelta(seconds=1), 'method': 'GET'
        },
        {
            'ip': '10.0.0.1', 'status': 200, 'path': '/home', 'size': 100,
            'timestamp': base_time + timedelta(seconds=2), 'method': 'GET'
        },
        {
            'ip': '10.0.0.1', 'status': 500, 'path': '/api', 'size': 0,
            'timestamp': base_time + timedelta(seconds=3), 'method': 'POST'
        }
    ]
EOF

# tests/test_parser.py
cat > "$TESTS_DIR/test_parser.py" << 'EOF'
import pytest
from datetime import datetime
from analyzer.parser import parse_log_line

def test_parse_standard_line(sample_log_line):
    result = parse_log_line(sample_log_line)
    assert result is not None
    assert result['ip'] == '127.0.0.1'
    assert result['user'] == 'frank'
    assert result['timestamp'].year == 2000
    assert result['method'] == 'GET'
    assert result['path'] == '/apache_pb.gif'
    assert result['status'] == 200
    assert result['size'] == 2326
    assert result['referer'] == 'http://www.example.com/start.html'
    assert 'Mozilla' in result['user_agent']

def test_parse_line_dash_size():
    line = '127.0.0.1 - - [10/Oct/2000:13:55:36 -0700] "GET / HTTP/1.0" 304 - "-" "-"'
    result = parse_log_line(line)
    assert result['status'] == 304
    assert result['size'] == 0

def test_parse_malformed_line():
    assert parse_log_line("This is junk") is None

def test_parse_timestamp_timezone():
    line = '127.0.0.1 - - [10/Oct/2023:13:55:36 +0000] "GET / HTTP/1.1" 200 123 "-" "-"'
    result = parse_log_line(line)
    assert result['timestamp'].tzinfo is not None
EOF

# tests/test_stats.py
cat > "$TESTS_DIR/test_stats.py" << 'EOF'
import pytest
from analyzer.stats import status_code_summary, top_endpoints, bandwidth_by_endpoint

def test_status_code_summary(parsed_entries):
    summary = status_code_summary(parsed_entries)
    assert summary['2xx'] == 2
    assert summary['3xx'] == 0
    assert summary['4xx'] == 1
    assert summary['5xx'] == 1

def test_top_endpoints(parsed_entries):
    # /home: 2, /missing: 1, /api: 1
    top = top_endpoints(parsed_entries, n=1)
    assert len(top) == 1
    assert top[0] == ('/home', 2)

    top_all = top_endpoints(parsed_entries, n=5)
    # Check tie breaking (alphabetical if counts equal)
    # /api and /missing both have 1. /api should come first.
    paths = [p for p, c in top_all]
    assert paths == ['/home', '/api', '/missing']

def test_bandwidth_by_endpoint(parsed_entries):
    bw = bandwidth_by_endpoint(parsed_entries)
    assert bw['/home'] == 200  # 100 + 100
    assert bw['/missing'] == 50
    assert bw['/api'] == 0
EOF

# tests/test_anomaly.py
cat > "$TESTS_DIR/test_anomaly.py" << 'EOF'
import pytest
from datetime import datetime, timedelta, timezone
from analyzer.anomaly import detect_brute_force

def test_detect_brute_force_basic():
    base = datetime.now(timezone.utc)
    entries = []
    # IP 1: 5 failures in 1 minute (threshold 3)
    for i in range(5):
        entries.append({
            'ip': '1.2.3.4', 'status': 401, 
            'timestamp': base + timedelta(seconds=i*10)
        })
    # IP 2: 2 failures (threshold 3)
    entries.append({'ip': '5.6.7.8', 'status': 401, 'timestamp': base})
    entries.append({'ip': '5.6.7.8', 'status': 401, 'timestamp': base})
    
    anomalies = detect_brute_force(entries, threshold=3, window_minutes=5)
    assert len(anomalies) == 1
    assert anomalies[0]['ip'] == '1.2.3.4'
    assert anomalies[0]['count'] == 5

def test_detect_brute_force_sliding_window():
    base = datetime.now(timezone.utc)
    entries = []
    # 3 failures, but spread over 10 minutes (window 5)
    entries.append({'ip': '1.1.1.1', 'status': 401, 'timestamp': base})
    entries.append({'ip': '1.1.1.1', 'status': 401, 'timestamp': base + timedelta(minutes=4)})
    entries.append({'ip': '1.1.1.1', 'status': 401, 'timestamp': base + timedelta(minutes=9)})
    
    # Threshold 3, Window 5
    # Window [0-5]: count 2
    # Window [4-9]: count 2
    # Should detect NOTHING
    anomalies = detect_brute_force(entries, threshold=3, window_minutes=5)
    assert len(anomalies) == 0

def test_detect_brute_force_success_ignored():
    base = datetime.now(timezone.utc)
    entries = [
        {'ip': '1.1.1.1', 'status': 200, 'timestamp': base},
        {'ip': '1.1.1.1', 'status': 200, 'timestamp': base},
        {'ip': '1.1.1.1', 'status': 200, 'timestamp': base},
    ]
    anomalies = detect_brute_force(entries, threshold=2, window_minutes=5)
    assert len(anomalies) == 0
EOF

# --- 4. Launch PyCharm ---

# Record timestamp
date +%s > /tmp/task_start_time

setup_pycharm_project "$PROJECT_DIR" "log_analyzer" 120

# Create initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="