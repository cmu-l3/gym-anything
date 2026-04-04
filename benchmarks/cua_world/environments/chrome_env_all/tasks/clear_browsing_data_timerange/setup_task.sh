#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Clear Browsing Data with Time Range Task Setup ==="
echo "Task: Selectively clear cookies and cache from last 24 hours while preserving history"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true
pip3 install -q requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Ensure Chrome is running
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 3

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to Google to ensure we have a clean starting page
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Create test data with timestamps
echo "Creating test data (cookies, history, cache)..."

# Create Python script to populate test data
cat > /tmp/create_test_data.py << 'EOFPYTHON'
#!/usr/bin/env python3
"""
Create test browsing data with specific timestamps for verification.
Creates cookies and history entries at different time points.
"""
import sqlite3
import time
import os
from pathlib import Path

# Chrome epoch: January 1, 1601 (in microseconds)
# Unix epoch: January 1, 1970
EPOCH_DELTA_SECONDS = 11644473600

def unix_to_chrome_time(unix_timestamp):
    """Convert Unix timestamp to Chrome timestamp (microseconds since 1601-01-01)"""
    return int((unix_timestamp + EPOCH_DELTA_SECONDS) * 1000000)

def create_test_cookies():
    """Create test cookies with various timestamps"""
    chrome_profile = Path("/home/ga/.config/google-chrome-cdp/Default")
    cookies_db = chrome_profile / "Cookies"
    
    if not cookies_db.exists():
        print(f"Cookies database not found at {cookies_db}")
        return False
    
    try:
        conn = sqlite3.connect(str(cookies_db))
        cursor = conn.cursor()
        
        current_time = time.time()
        
        # Test data:
        # 1. Recent cookies (within 24h) - should be DELETED
        recent_30min = unix_to_chrome_time(current_time - 30*60)  # 30 minutes ago
        recent_12h = unix_to_chrome_time(current_time - 12*3600)  # 12 hours ago
        recent_23h = unix_to_chrome_time(current_time - 23*3600)  # 23 hours ago
        
        # 2. Old cookies (>24h) - should be PRESERVED
        old_2days = unix_to_chrome_time(current_time - 2*24*3600)  # 2 days ago
        old_5days = unix_to_chrome_time(current_time - 5*24*3600)  # 5 days ago
        old_10days = unix_to_chrome_time(current_time - 10*24*3600)  # 10 days ago
        
        # Insert recent cookies (to be deleted)
        test_cookies_recent = [
            ("test_cookie_30min", "test-recent-30min.com", "value1", "/", recent_30min, recent_30min),
            ("test_cookie_12h", "test-recent-12h.com", "value2", "/", recent_12h, recent_12h),
            ("test_cookie_23h", "test-recent-23h.com", "value3", "/", recent_23h, recent_23h),
        ]
        
        # Insert old cookies (to be preserved)
        test_cookies_old = [
            ("test_cookie_2d", "test-old-2days.com", "value4", "/", old_2days, old_2days),
            ("test_cookie_5d", "test-old-5days.com", "value5", "/", old_5days, old_5days),
            ("test_cookie_10d", "test-old-10days.com", "value6", "/", old_10days, old_10days),
        ]
        
        all_test_cookies = test_cookies_recent + test_cookies_old
        
        for name, host, value, path, creation_time, last_access in all_test_cookies:
            try:
                cursor.execute("""
                    INSERT INTO cookies (
                        creation_utc, host_key, top_frame_site_key, name, value, 
                        encrypted_value, path, expires_utc, is_secure, 
                        is_httponly, last_access_utc, has_expires, is_persistent,
                        priority, samesite, source_scheme, source_port, is_same_party
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    creation_time, host, "", name, value,
                    b"", path, creation_time + 31536000000000,  # expires in 1 year
                    0, 0, last_access, 1, 1, 1, -1, 2, -1, 0
                ))
                print(f"  ✓ Created cookie: {name} on {host}")
            except sqlite3.IntegrityError:
                print(f"  ⚠ Cookie {name} already exists, skipping")
            except Exception as e:
                print(f"  ✗ Failed to create cookie {name}: {e}")
        
        conn.commit()
        conn.close()
        
        print(f"✓ Created {len(all_test_cookies)} test cookies")
        return True
        
    except Exception as e:
        print(f"✗ Error creating test cookies: {e}")
        return False

def create_test_history():
    """Create test history entries with various timestamps"""
    chrome_profile = Path("/home/ga/.config/google-chrome-cdp/Default")
    history_db = chrome_profile / "History"
    
    if not history_db.exists():
        print(f"History database not found at {history_db}")
        return False
    
    try:
        conn = sqlite3.connect(str(history_db))
        cursor = conn.cursor()
        
        current_time = time.time()
        
        # Create history entries at different times
        # All should be PRESERVED (history is not deleted in this task)
        test_history = [
            ("https://example.com/recent-2h", "Example Recent 2h", current_time - 2*3600),
            ("https://example.com/recent-20h", "Example Recent 20h", current_time - 20*3600),
            ("https://example.com/old-3d", "Example Old 3 days", current_time - 3*24*3600),
            ("https://example.com/old-7d", "Example Old 7 days", current_time - 7*24*3600),
        ]
        
        for url, title, timestamp in test_history:
            chrome_time = unix_to_chrome_time(timestamp)
            try:
                cursor.execute("""
                    INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden)
                    VALUES (?, ?, 1, 0, ?, 0)
                """, (url, title, chrome_time))
                
                url_id = cursor.lastrowid
                
                cursor.execute("""
                    INSERT INTO visits (url, visit_time, from_visit, transition, segment_id)
                    VALUES (?, ?, 0, 0, 0)
                """, (url_id, chrome_time))
                
                print(f"  ✓ Created history entry: {title}")
            except sqlite3.IntegrityError:
                print(f"  ⚠ History entry for {url} already exists, skipping")
            except Exception as e:
                print(f"  ✗ Failed to create history entry: {e}")
        
        conn.commit()
        conn.close()
        
        print(f"✓ Created {len(test_history)} test history entries")
        return True
        
    except Exception as e:
        print(f"✗ Error creating test history: {e}")
        return False

def populate_cache():
    """Create some cache files to ensure cache clearing is detectable"""
    chrome_profile = Path("/home/ga/.config/google-chrome-cdp/Default")
    cache_dir = chrome_profile / "Cache" / "Cache_Data"
    
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        
        # Create several dummy cache files
        for i in range(10):
            cache_file = cache_dir / f"test_cache_{i}"
            cache_file.write_bytes(b"X" * (1024 * 100))  # 100 KB each
        
        print(f"✓ Populated cache with test files")
        return True
        
    except Exception as e:
        print(f"✗ Error populating cache: {e}")
        return False

if __name__ == "__main__":
    print("Creating test data...")
    
    # Note: Chrome must be closed to modify databases directly
    success_cookies = create_test_cookies()
    success_history = create_test_history()
    success_cache = populate_cache()
    
    if success_cookies and success_history and success_cache:
        print("✅ All test data created successfully")
        exit(0)
    else:
        print("⚠ Some test data creation failed")
        exit(1)
EOFPYTHON

chmod +x /tmp/create_test_data.py

# Close Chrome to modify databases
echo "Stopping Chrome temporarily to create test data..."
pkill -f "chrome.*remote-debugging-port" || true
sleep 2

# Run test data creation script
echo "Populating test data..."
python3 /tmp/create_test_data.py

# Create baseline recording script
cat > /tmp/create_baseline.py << 'EOFBASELINE'
#!/usr/bin/env python3
"""
Record baseline state of Chrome data before task execution.
Saves cookie IDs, history URLs, and cache metrics.
"""
import json
import sqlite3
import time
from pathlib import Path

def get_dir_size(path):
    """Calculate total size of directory in bytes"""
    total = 0
    try:
        for item in Path(path).rglob('*'):
            if item.is_file():
                total += item.stat().st_size
    except Exception as e:
        print(f"Error calculating size: {e}")
    return total

def count_files(path):
    """Count files in directory recursively"""
    try:
        return sum(1 for _ in Path(path).rglob('*') if _.is_file())
    except Exception as e:
        print(f"Error counting files: {e}")
        return 0

def record_baseline():
    """Record initial Chrome state"""
    chrome_profile = Path("/home/ga/.config/google-chrome-cdp/Default")
    
    current_time = time.time()
    chrome_epoch_delta = 11644473600
    cutoff_chrome_time = int((current_time - 24*3600 + chrome_epoch_delta) * 1000000)
    
    baseline = {
        "timestamp": current_time,
        "cutoff_24h_chrome_time": cutoff_chrome_time,
        "cookies": {
            "recent": [],  # (name, host_key) tuples for cookies within 24h
            "old": [],     # (name, host_key) tuples for cookies older than 24h
            "total_count": 0
        },
        "history": {
            "all_urls": [],  # All history URLs
            "total_count": 0
        },
        "cache": {
            "size_bytes": 0,
            "file_count": 0
        }
    }
    
    # Record cookies
    cookies_db = chrome_profile / "Cookies"
    if cookies_db.exists():
        try:
            conn = sqlite3.connect(str(cookies_db))
            cursor = conn.cursor()
            
            # Get all cookies with timestamps
            cursor.execute("SELECT name, host_key, creation_utc FROM cookies")
            all_cookies = cursor.fetchall()
            
            for name, host_key, creation_utc in all_cookies:
                if creation_utc > cutoff_chrome_time:
                    baseline["cookies"]["recent"].append((name, host_key))
                else:
                    baseline["cookies"]["old"].append((name, host_key))
            
            baseline["cookies"]["total_count"] = len(all_cookies)
            conn.close()
            
            print(f"✓ Recorded {len(baseline['cookies']['recent'])} recent cookies")
            print(f"✓ Recorded {len(baseline['cookies']['old'])} old cookies")
        except Exception as e:
            print(f"✗ Error recording cookies: {e}")
    
    # Record history
    history_db = chrome_profile / "History"
    if history_db.exists():
        try:
            conn = sqlite3.connect(str(history_db))
            cursor = conn.cursor()
            
            cursor.execute("SELECT url FROM urls")
            urls = cursor.fetchall()
            baseline["history"]["all_urls"] = [url[0] for url in urls]
            baseline["history"]["total_count"] = len(baseline["history"]["all_urls"])
            
            conn.close()
            
            print(f"✓ Recorded {baseline['history']['total_count']} history entries")
        except Exception as e:
            print(f"✗ Error recording history: {e}")
    
    # Record cache metrics
    cache_dir = chrome_profile / "Cache"
    if cache_dir.exists():
        baseline["cache"]["size_bytes"] = get_dir_size(cache_dir)
        baseline["cache"]["file_count"] = count_files(cache_dir)
        print(f"✓ Recorded cache: {baseline['cache']['size_bytes']} bytes, {baseline['cache']['file_count']} files")
    
    # Save baseline
    baseline_path = Path("/tmp/chrome_baseline.json")
    with open(baseline_path, "w") as f:
        json.dump(baseline, f, indent=2)
    
    print(f"✅ Baseline saved to {baseline_path}")
    return True

if __name__ == "__main__":
    record_baseline()
EOFBASELINE

chmod +x /tmp/create_baseline.py

# Record baseline state
echo "Recording baseline state..."
python3 /tmp/create_baseline.py

# Restart Chrome
echo "Restarting Chrome..."
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
sleep 5

# Focus Chrome again
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -n "$wid" ]; then
    wmctrl -i -a $wid || true
    sleep 1
fi

# Final activation
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

echo "=== Setup complete ==="
echo "Chrome is ready with test data:"
echo "  - Recent cookies (within 24h): should be deleted"
echo "  - Old cookies (>24h): should be preserved"
echo "  - History entries: should ALL be preserved"
echo "  - Cache: should be cleared"
echo ""
echo "Agent should:"
echo "  1. Press Ctrl+Shift+Delete to open Clear Browsing Data"
echo "  2. Click 'Advanced' tab"
echo "  3. Select time range: 'Last 24 hours'"
echo "  4. Check ONLY: 'Cookies and other site data' + 'Cached images and files'"
echo "  5. Ensure 'Browsing history' is UNCHECKED"
echo "  6. Click 'Clear data' button"