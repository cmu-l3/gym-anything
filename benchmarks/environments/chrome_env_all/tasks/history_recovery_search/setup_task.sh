#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome History Recovery Search Task Setup ==="
echo "Task: Search browsing history to recover a previously visited page about REST API authentication"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip sqlite3 || true

# Install Python packages for history manipulation
pip3 install -q requests 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the target article HTML file that will be "recovered" from history
echo "Creating target article HTML..."
ARTICLE_DIR="/home/ga/Documents"
mkdir -p "$ARTICLE_DIR"

cat > "$ARTICLE_DIR/rest_api_auth_guide.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>REST API Authentication Best Practices - Developer Guide</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            margin: 40px auto;
            max-width: 900px;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background-color: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 { 
            color: #2c3e50; 
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        h2 { 
            color: #34495e; 
            margin-top: 30px;
        }
        .highlight {
            background-color: #ecf0f1;
            padding: 20px;
            border-left: 4px solid #3498db;
            margin: 20px 0;
        }
        code {
            background-color: #f8f8f8;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }
        .method {
            margin: 15px 0;
            padding: 15px;
            background-color: #fff;
            border: 1px solid #ddd;
            border-radius: 4px;
        }
        .method-title {
            font-weight: bold;
            color: #2980b9;
            font-size: 1.1em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>REST API Authentication Best Practices</h1>
        <p><em>A Comprehensive Developer Guide to Securing RESTful APIs</em></p>

        <h2>Introduction</h2>
        <p>Authentication is a critical component of REST API security. This guide covers industry-standard authentication methods and best practices for implementing secure API authentication in production systems.</p>

        <div class="highlight">
            <strong>Key Principle:</strong> Always use HTTPS/TLS for API communication. Authentication tokens and credentials should never be transmitted over unencrypted connections.
        </div>

        <h2>Common Authentication Methods</h2>

        <div class="method">
            <div class="method-title">1. API Keys</div>
            <p>Simple authentication using a unique identifier passed in headers or query parameters. Best for server-to-server communication and rate limiting.</p>
            <p><strong>Pros:</strong> Simple to implement, easy to revoke</p>
            <p><strong>Cons:</strong> No user context, vulnerable if exposed</p>
            <p><strong>Usage:</strong> <code>Authorization: ApiKey YOUR_API_KEY</code></p>
        </div>

        <div class="method">
            <div class="method-title">2. Basic Authentication</div>
            <p>Uses Base64-encoded username and password in the Authorization header. Must be used with HTTPS.</p>
            <p><strong>Pros:</strong> Built into HTTP standard, widely supported</p>
            <p><strong>Cons:</strong> Credentials sent with every request, vulnerable to replay attacks</p>
            <p><strong>Usage:</strong> <code>Authorization: Basic base64(username:password)</code></p>
        </div>

        <div class="method">
            <div class="method-title">3. Bearer Tokens (JWT)</div>
            <p>JSON Web Tokens are self-contained tokens that encode user identity and claims. Most popular for modern APIs.</p>
            <p><strong>Pros:</strong> Stateless, scalable, contains user context, expirable</p>
            <p><strong>Cons:</strong> Cannot be revoked before expiration without additional infrastructure</p>
            <p><strong>Usage:</strong> <code>Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...</code></p>
        </div>

        <div class="method">
            <div class="method-title">4. OAuth 2.0</div>
            <p>Industry-standard protocol for authorization, allowing third-party applications limited access to user resources.</p>
            <p><strong>Pros:</strong> Secure delegation, fine-grained permissions, refresh tokens</p>
            <p><strong>Cons:</strong> Complex to implement, requires additional infrastructure</p>
            <p><strong>Flow:</strong> Authorization Code Grant, Client Credentials, Implicit Flow</p>
        </div>

        <div class="method">
            <div class="method-title">5. HMAC Signatures</div>
            <p>Request signing using Hash-based Message Authentication Code to verify integrity and authenticity.</p>
            <p><strong>Pros:</strong> Strong security, prevents tampering, no token storage</p>
            <p><strong>Cons:</strong> Complex implementation, clock synchronization required</p>
            <p><strong>Usage:</strong> Sign request payload with shared secret</p>
        </div>

        <h2>Best Practices</h2>

        <div class="highlight">
            <h3>Security Recommendations</h3>
            <ul>
                <li><strong>Always use HTTPS:</strong> Encrypt all API traffic with TLS 1.2 or higher</li>
                <li><strong>Token Expiration:</strong> Implement short-lived access tokens with refresh token rotation</li>
                <li><strong>Rate Limiting:</strong> Prevent brute force attacks with request throttling</li>
                <li><strong>Input Validation:</strong> Validate all authentication parameters to prevent injection attacks</li>
                <li><strong>Secure Storage:</strong> Never store tokens or credentials in client-side code or version control</li>
                <li><strong>Logging:</strong> Log authentication attempts and failures for security monitoring</li>
                <li><strong>Multi-Factor Authentication:</strong> Implement MFA for sensitive operations</li>
                <li><strong>Token Revocation:</strong> Provide mechanisms to invalidate compromised tokens</li>
            </ul>
        </div>

        <h2>JWT Token Structure</h2>
        <p>A JWT consists of three parts separated by dots:</p>
        <p><code>header.payload.signature</code></p>
        
        <p><strong>Header:</strong> Contains token type and hashing algorithm</p>
        <p><strong>Payload:</strong> Contains claims (user ID, expiration, permissions)</p>
        <p><strong>Signature:</strong> Ensures token hasn't been tampered with</p>

        <h2>Common Vulnerabilities to Avoid</h2>
        <ul>
            <li><strong>Weak Secrets:</strong> Use cryptographically strong random keys (256+ bits)</li>
            <li><strong>Token Exposure:</strong> Never include tokens in URLs or browser history</li>
            <li><strong>Missing Expiration:</strong> Always set reasonable token expiration times</li>
            <li><strong>Algorithm Confusion:</strong> Explicitly specify and validate JWT algorithms</li>
            <li><strong>Insecure Transport:</strong> Enforce HTTPS for all authentication endpoints</li>
            <li><strong>Insufficient Validation:</strong> Verify token signature, expiration, and issuer on every request</li>
        </ul>

        <h2>Implementation Checklist</h2>
        <div class="highlight">
            <ol>
                <li>✓ Choose authentication method appropriate for your use case</li>
                <li>✓ Implement HTTPS/TLS for all API endpoints</li>
                <li>✓ Use strong, random secrets for token signing</li>
                <li>✓ Set appropriate token expiration times (15-60 minutes for access tokens)</li>
                <li>✓ Implement refresh token rotation for long-lived sessions</li>
                <li>✓ Add rate limiting and request throttling</li>
                <li>✓ Log authentication events for security monitoring</li>
                <li>✓ Provide token revocation mechanisms</li>
                <li>✓ Implement CORS policies correctly</li>
                <li>✓ Add comprehensive error handling without leaking sensitive information</li>
            </ol>
        </div>

        <h2>Code Example: Bearer Token Validation</h2>
        <pre style="background-color: #f8f8f8; padding: 15px; border-radius: 4px; overflow-x: auto;"><code>// Node.js example using jsonwebtoken
const jwt = require('jsonwebtoken');

function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];
    
    if (!token) {
        return res.status(401).json({ error: 'Access token required' });
    }
    
    jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ error: 'Invalid or expired token' });
        }
        req.user = user;
        next();
    });
}</code></pre>

        <h2>Conclusion</h2>
        <p>Proper API authentication is essential for building secure applications. Choose the authentication method that best fits your security requirements and use case, always prioritize security best practices, and regularly review and update your authentication implementation to address emerging threats.</p>

        <p><em>Last updated: Three days ago</em></p>
    </div>
</body>
</html>
EOF

chown ga:ga "$ARTICLE_DIR/rest_api_auth_guide.html"
echo "✓ Target article HTML created at: $ARTICLE_DIR/rest_api_auth_guide.html"

# Create Python script to seed Chrome history
cat > /tmp/seed_chrome_history.py << 'EOFPYTHON'
#!/usr/bin/env python3
"""
Seed Chrome history with a specific URL dated 2-3 days ago
"""

import sqlite3
import sys
import os
from datetime import datetime, timedelta
from pathlib import Path

def chrome_timestamp(dt):
    """
    Convert Python datetime to Chrome's microseconds since 1601-01-01
    Chrome uses Windows FILETIME format
    """
    # Chrome epoch: January 1, 1601
    chrome_epoch = datetime(1601, 1, 1)
    delta = dt - chrome_epoch
    # Convert to microseconds
    return int(delta.total_seconds() * 1_000_000)

def seed_history_entry(history_db_path, url, title, days_ago=2):
    """
    Add an entry to Chrome history database
    
    Args:
        history_db_path: Path to Chrome History database
        url: URL to add to history
        title: Page title
        days_ago: How many days ago the visit occurred
    """
    if not os.path.exists(history_db_path):
        print(f"Error: History database not found at {history_db_path}")
        return False
    
    # Calculate visit time
    visit_datetime = datetime.now() - timedelta(days=days_ago)
    chrome_time = chrome_timestamp(visit_datetime)
    
    try:
        conn = sqlite3.connect(history_db_path)
        cursor = conn.cursor()
        
        # Check if URL already exists
        cursor.execute("SELECT id FROM urls WHERE url = ?", (url,))
        existing = cursor.fetchone()
        
        if existing:
            url_id = existing[0]
            print(f"URL already exists with id={url_id}, updating...")
            # Update existing entry
            cursor.execute("""
                UPDATE urls 
                SET title = ?, visit_count = visit_count + 1, last_visit_time = ?
                WHERE id = ?
            """, (title, chrome_time, url_id))
        else:
            # Insert new URL entry
            cursor.execute("""
                INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden)
                VALUES (?, ?, 1, 0, ?, 0)
            """, (url, title, chrome_time))
            url_id = cursor.lastrowid
            print(f"Inserted new URL with id={url_id}")
        
        # Insert visit record
        cursor.execute("""
            INSERT INTO visits (url, visit_time, from_visit, transition, segment_id, visit_duration)
            VALUES (?, ?, 0, 805306368, 0, 0)
        """, (url_id, chrome_time))
        
        visit_id = cursor.lastrowid
        print(f"Inserted visit record with id={visit_id}")
        
        conn.commit()
        conn.close()
        
        print(f"✓ Successfully seeded history: {url}")
        print(f"  Title: {title}")
        print(f"  Date: {visit_datetime.strftime('%Y-%m-%d %H:%M:%S')} ({days_ago} days ago)")
        
        return True
        
    except sqlite3.Error as e:
        print(f"Database error: {e}")
        return False
    except Exception as e:
        print(f"Error seeding history: {e}")
        return False

if __name__ == "__main__":
    # Configuration
    TARGET_URL = "file:///home/ga/Documents/rest_api_auth_guide.html"
    TARGET_TITLE = "REST API Authentication Best Practices - Developer Guide"
    DAYS_AGO = 2
    
    # Chrome profile paths to try
    profile_paths = [
        "/home/ga/.config/google-chrome-cdp/Default/History",
        "/home/ga/.config/google-chrome/Default/History"
    ]
    
    success = False
    for history_path in profile_paths:
        if os.path.exists(history_path):
            print(f"Found History database at: {history_path}")
            success = seed_history_entry(history_path, TARGET_URL, TARGET_TITLE, DAYS_AGO)
            if success:
                break
        else:
            print(f"History database not found at: {history_path}")
    
    if not success:
        print("Failed to seed history in any profile location")
        sys.exit(1)
    else:
        print("History seeding complete!")
        sys.exit(0)
EOFPYTHON

chmod +x /tmp/seed_chrome_history.py

# Check if Chrome is running and stop it temporarily to seed history
echo "Checking Chrome status..."
if pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome is running, stopping it to seed history..."
    pkill -f "google-chrome" || true
    sleep 2
fi

# Ensure Chrome profile directory exists
CHROME_PROFILE_DIR="/home/ga/.config/google-chrome-cdp/Default"
mkdir -p "$CHROME_PROFILE_DIR"
chown -R ga:ga "/home/ga/.config/google-chrome-cdp"

# Run Chrome briefly to create History database if it doesn't exist
if [ ! -f "$CHROME_PROFILE_DIR/History" ]; then
    echo "Creating initial Chrome profile and History database..."
    su - ga -c "DISPLAY=:1 timeout 5 google-chrome-stable --headless --disable-gpu --user-data-dir=/home/ga/.config/google-chrome-cdp about:blank" || true
    sleep 2
fi

# Seed the history database
echo "Seeding Chrome history with target page..."
python3 /tmp/seed_chrome_history.py
sleep 1

# Now start Chrome properly for the task
echo "Starting Chrome for task..."
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Starting Chrome..."
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

# Navigate to starting page (Google)
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

echo "=== Setup complete ==="
echo "Target page seeded in history: file:///home/ga/Documents/rest_api_auth_guide.html"
echo "Agent should:"
echo "  1. Press Ctrl+H to open history (or navigate to chrome://history/)"
echo "  2. Search for keywords like 'API', 'authentication', or 'REST'"
echo "  3. Identify the correct page from search results (2 days ago)"
echo "  4. Click on the history entry to navigate to the recovered page"