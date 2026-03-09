#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Selective Cookie Cleanup Task Setup ==="
echo "Task: Remove untrusted cookies while preserving trusted site logins"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true
pip3 install -q requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create cookie seeding script
cat > /tmp/seed_cookies.py << 'SEED_SCRIPT'
#!/usr/bin/env python3
"""Seed Chrome with cookies for trusted and untrusted domains"""
import requests
import json
import time
import sys

CDP_URL = "http://localhost:9222"

def get_targets():
    """Get available Chrome targets"""
    try:
        response = requests.get(f"{CDP_URL}/json", timeout=5)
        return response.json()
    except Exception as e:
        print(f"Error getting targets: {e}", file=sys.stderr)
        return []

def execute_cdp_command(ws_url, method, params=None):
    """Execute CDP command via HTTP (simplified - normally would use WebSocket)"""
    # For simplicity, we'll use the HTTP API where possible
    pass

def set_cookie_via_navigation(url, cookie_name, cookie_value):
    """Set cookie by navigating to a URL (simulated)"""
    # This is a simplified approach - in reality, we'd need to navigate and set via JS
    print(f"Would set cookie {cookie_name} for {url}")

# Trusted domains and their cookies
trusted_domains = {
    ".gmail.com": [
        ("SID", "session_id_gmail_12345"),
        ("SSID", "secure_session_gmail_67890"),
        ("APISID", "api_session_gmail_abc"),
        ("HSID", "host_session_gmail_def"),
        ("NID", "network_id_gmail_ghi"),
    ],
    ".company-dashboard.example.com": [
        ("session_token", "company_sess_xyz789"),
        ("user_id", "emp_12345"),
        ("auth_token", "Bearer_company_abc123"),
    ],
    ".secure-bank.example.com": [
        ("bank_session", "secure_bank_sess_456"),
        ("csrf_token", "csrf_bank_789xyz"),
        ("account_id", "acct_987654"),
        ("security_token", "sec_bank_def456"),
    ],
}

# Untrusted tracking/advertising domains
untrusted_domains = {
    ".doubleclick.net": [("id", "track_dc_123"), ("test_cookie", "CheckForPermission")],
    ".google-analytics.com": [("_ga", "GA1.2.12345.67890"), ("_gid", "GA1.2.98765.43210")],
    ".facebook.com": [("fr", "fb_track_abc123"), ("_fbp", "fb.1.234567890")],
    ".adserver.example.com": [("ad_id", "ad_track_xyz"), ("campaign", "summer_2024")],
    ".tracker.example.com": [("track_id", "trk_12345"), ("session", "trk_sess_abc")],
    ".tracking-pixel.com": [("pixel_id", "px_98765"), ("conv", "conversion_123")],
    ".ad-network.com": [("network_id", "net_456"), ("campaign_id", "camp_789")],
    ".analytics-provider.com": [("analytics_id", "anly_xyz123"), ("visitor_id", "vis_456789")],
    ".data-broker.com": [("broker_id", "data_abc"), ("profile", "prof_xyz")],
    ".thirdparty-tracker.com": [("third_party_id", "3p_123"), ("tracker", "track_abc")],
    ".ad-exchange.com": [("exchange_id", "exch_456"), ("bid_id", "bid_789")],
    ".marketing-platform.com": [("marketing_id", "mkt_abc"), ("segment", "seg_123")],
    ".behavioral-ads.com": [("behavior_id", "beh_xyz"), ("interest", "int_abc")],
    ".retargeting-service.com": [("retarget_id", "ret_123"), ("pixel", "px_ret_456")],
    ".conversion-tracker.com": [("conv_id", "conv_abc"), ("attribution", "attr_xyz")],
    ".social-widget.com": [("widget_id", "wdg_123"), ("social_id", "soc_456")],
    ".embed-tracker.com": [("embed_id", "emb_xyz"), ("tracker_id", "trk_emb_abc")],
}

print("Cookie seeding summary:")
print(f"  Trusted domains: {len(trusted_domains)} domains, {sum(len(v) for v in trusted_domains.values())} cookies")
print(f"  Untrusted domains: {len(untrusted_domains)} domains, {sum(len(v) for v in untrusted_domains.values())} cookies")

# Export initial state for verification
initial_state = {
    "total_count": sum(len(v) for v in trusted_domains.values()) + sum(len(v) for v in untrusted_domains.values()),
    "trusted_counts": {domain: len(cookies) for domain, cookies in trusted_domains.items()},
    "untrusted_domains": list(untrusted_domains.keys()),
    "trusted_domains": list(trusted_domains.keys())
}

with open("/tmp/initial_cookie_state.json", "w") as f:
    json.dump(initial_state, f, indent=2)

print("Initial state saved to /tmp/initial_cookie_state.json")
SEED_SCRIPT

chmod +x /tmp/seed_cookies.py

# Seed cookies using CDP or direct SQLite manipulation
echo "Seeding cookies into Chrome profile..."

# Alternative approach: Direct SQLite insertion (more reliable for this task)
COOKIES_DB="/home/ga/.config/google-chrome-cdp/Default/Cookies"

# Stop Chrome if running to ensure we can write to database
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Stopping Chrome to seed cookies..."
    pkill chrome || true
    sleep 2
fi

# Create cookie seeding SQL script
cat > /tmp/seed_cookies.sql << 'EOF'
-- Trusted domain cookies (gmail.com)
INSERT OR REPLACE INTO cookies (creation_utc, host_key, top_frame_site_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party)
VALUES 
(13360000000000000, '.gmail.com', '', 'SID', 'session_id_gmail_12345', X'', '/', 13400000000000000, 1, 1, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.gmail.com', '', 'SSID', 'secure_session_gmail_67890', X'', '/', 13400000000000000, 1, 1, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.gmail.com', '', 'APISID', 'api_session_gmail_abc', X'', '/', 13400000000000000, 1, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.gmail.com', '', 'HSID', 'host_session_gmail_def', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.gmail.com', '', 'NID', 'network_id_gmail_ghi', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0);

-- Trusted domain cookies (company-dashboard.example.com)
INSERT OR REPLACE INTO cookies (creation_utc, host_key, top_frame_site_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party)
VALUES 
(13360000000000000, '.company-dashboard.example.com', '', 'session_token', 'company_sess_xyz789', X'', '/', 13400000000000000, 1, 1, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.company-dashboard.example.com', '', 'user_id', 'emp_12345', X'', '/', 13400000000000000, 1, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.company-dashboard.example.com', '', 'auth_token', 'Bearer_company_abc123', X'', '/', 13400000000000000, 1, 1, 13360000000000000, 1, 1, 1, 0, 2, 443, 0);

-- Trusted domain cookies (secure-bank.example.com)
INSERT OR REPLACE INTO cookies (creation_utc, host_key, top_frame_site_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party)
VALUES 
(13360000000000000, '.secure-bank.example.com', '', 'bank_session', 'secure_bank_sess_456', X'', '/', 13400000000000000, 1, 1, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.secure-bank.example.com', '', 'csrf_token', 'csrf_bank_789xyz', X'', '/', 13400000000000000, 1, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.secure-bank.example.com', '', 'account_id', 'acct_987654', X'', '/', 13400000000000000, 1, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.secure-bank.example.com', '', 'security_token', 'sec_bank_def456', X'', '/', 13400000000000000, 1, 1, 13360000000000000, 1, 1, 1, 0, 2, 443, 0);

-- Untrusted tracking cookies
INSERT OR REPLACE INTO cookies (creation_utc, host_key, top_frame_site_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, last_access_utc, has_expires, is_persistent, priority, samesite, source_scheme, source_port, is_same_party)
VALUES 
(13360000000000000, '.doubleclick.net', '', 'id', 'track_dc_123', X'', '/', 13400000000000000, 1, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.doubleclick.net', '', 'test_cookie', 'CheckForPermission', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.google-analytics.com', '', '_ga', 'GA1.2.12345.67890', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.google-analytics.com', '', '_gid', 'GA1.2.98765.43210', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.facebook.com', '', 'fr', 'fb_track_abc123', X'', '/', 13400000000000000, 1, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.facebook.com', '', '_fbp', 'fb.1.234567890', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.adserver.example.com', '', 'ad_id', 'ad_track_xyz', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.adserver.example.com', '', 'campaign', 'summer_2024', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.tracker.example.com', '', 'track_id', 'trk_12345', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.tracker.example.com', '', 'session', 'trk_sess_abc', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.tracking-pixel.com', '', 'pixel_id', 'px_98765', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.tracking-pixel.com', '', 'conv', 'conversion_123', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.ad-network.com', '', 'network_id', 'net_456', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.ad-network.com', '', 'campaign_id', 'camp_789', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.analytics-provider.com', '', 'analytics_id', 'anly_xyz123', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.analytics-provider.com', '', 'visitor_id', 'vis_456789', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.data-broker.com', '', 'broker_id', 'data_abc', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.data-broker.com', '', 'profile', 'prof_xyz', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.thirdparty-tracker.com', '', 'third_party_id', '3p_123', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.thirdparty-tracker.com', '', 'tracker', 'track_abc', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.ad-exchange.com', '', 'exchange_id', 'exch_456', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.ad-exchange.com', '', 'bid_id', 'bid_789', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.marketing-platform.com', '', 'marketing_id', 'mkt_abc', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.marketing-platform.com', '', 'segment', 'seg_123', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.behavioral-ads.com', '', 'behavior_id', 'beh_xyz', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.behavioral-ads.com', '', 'interest', 'int_abc', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.retargeting-service.com', '', 'retarget_id', 'ret_123', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.retargeting-service.com', '', 'pixel', 'px_ret_456', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.conversion-tracker.com', '', 'conv_id', 'conv_abc', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.conversion-tracker.com', '', 'attribution', 'attr_xyz', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.social-widget.com', '', 'widget_id', 'wdg_123', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.social-widget.com', '', 'social_id', 'soc_456', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.embed-tracker.com', '', 'embed_id', 'emb_xyz', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0),
(13360000000000000, '.embed-tracker.com', '', 'tracker_id', 'trk_emb_abc', X'', '/', 13400000000000000, 0, 0, 13360000000000000, 1, 1, 1, 0, 2, 443, 0);
EOF

# Apply cookie seeding if database exists
if [ -f "$COOKIES_DB" ]; then
    echo "Seeding cookies into existing database..."
    sqlite3 "$COOKIES_DB" < /tmp/seed_cookies.sql 2>/dev/null || echo "Note: Some cookies may already exist"
    chown ga:ga "$COOKIES_DB"
else
    echo "Warning: Cookies database not found at $COOKIES_DB"
    # Try alternative location
    COOKIES_DB="/home/ga/.config/google-chrome/Default/Cookies"
    if [ -f "$COOKIES_DB" ]; then
        sqlite3 "$COOKIES_DB" < /tmp/seed_cookies.sql 2>/dev/null || echo "Note: Some cookies may already exist"
        chown ga:ga "$COOKIES_DB"
    fi
fi

# Count cookies to verify seeding
COOKIE_COUNT=$(sqlite3 "$COOKIES_DB" "SELECT COUNT(*) FROM cookies;" 2>/dev/null || echo "0")
echo "✓ Cookie database now contains $COOKIE_COUNT cookies"

# Create initial state metadata
cat > /tmp/initial_cookie_state.json << 'JSONEOF'
{
  "total_count": 46,
  "trusted_counts": {
    ".gmail.com": 5,
    ".company-dashboard.example.com": 3,
    ".secure-bank.example.com": 4
  },
  "untrusted_domains": [
    ".doubleclick.net",
    ".google-analytics.com",
    ".facebook.com",
    ".adserver.example.com",
    ".tracker.example.com",
    ".tracking-pixel.com",
    ".ad-network.com",
    ".analytics-provider.com",
    ".data-broker.com",
    ".thirdparty-tracker.com",
    ".ad-exchange.com",
    ".marketing-platform.com",
    ".behavioral-ads.com",
    ".retargeting-service.com",
    ".conversion-tracker.com",
    ".social-widget.com",
    ".embed-tracker.com"
  ],
  "trusted_domains": [
    ".gmail.com",
    ".company-dashboard.example.com",
    ".secure-bank.example.com"
  ]
}
JSONEOF

echo "✓ Initial cookie state saved to /tmp/initial_cookie_state.json"

# Now start Chrome with the seeded cookies
echo "Starting Chrome with seeded cookies..."
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

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

# Navigate to starting page
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo ""
echo "=== Setup complete ==="
echo "Browser has accumulated 46 cookies from 20 domains over several weeks of use."
echo ""
echo "TRUSTED sites (keep logged in):"
echo "  ✓ gmail.com (5 cookies)"
echo "  ✓ company-dashboard.example.com (3 cookies)"
echo "  ✓ secure-bank.example.com (4 cookies)"
echo ""
echo "UNTRUSTED sites (tracking/ads - should be deleted):"
echo "  ✗ 17 advertising and tracking domains (34 cookies total)"
echo ""
echo "Agent task:"
echo "  1. Navigate to chrome://settings/siteData (or Settings > Privacy > Cookies)"
echo "  2. Review cookie list"
echo "  3. Delete cookies from untrusted tracking/ad domains"
echo "  4. Keep cookies from the 3 trusted domains"
echo "  5. Result: Browser stays logged into important sites but removes tracking"