#!/bin/bash
set -e
echo "=== Setting up Fix HTTP API Client Task ==="

# Source VSCode task utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/api_client"
sudo -u ga mkdir -p "$WORKSPACE_DIR/client"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# 1. url_builder.py (BUG: Naive string interpolation instead of urlencode)
cat > "$WORKSPACE_DIR/client/url_builder.py" << 'EOF'
import urllib.parse

def build_url(base_url, params=None):
    """Builds a URL with query parameters."""
    if not params:
        return base_url
        
    # BUG 1: Naive string interpolation doesn't properly encode spaces or special characters
    query_string = "&".join([f"{k}={v}" for k, v in params.items()])
    
    separator = "&" if "?" in base_url else "?"
    return f"{base_url}{separator}{query_string}"
EOF

# 2. retry.py (BUG: Linear backoff, retries non-retryable 400s)
cat > "$WORKSPACE_DIR/client/retry.py" << 'EOF'
def get_backoff(base_delay, attempt):
    """Calculate backoff delay for retries."""
    # BUG 2a: Linear backoff instead of exponential backoff
    return base_delay * attempt

def should_retry(status_code):
    """Determine if a request should be retried based on HTTP status code."""
    # BUG 2b: Retries on 400, 401, 403, 404 which are non-retryable client errors
    # Should only retry on 429 and 5xx errors
    if status_code >= 400:
        return True
    return False
EOF

# 3. http_client.py (BUG: Swapped timeout tuple)
cat > "$WORKSPACE_DIR/client/http_client.py" << 'EOF'
import requests
from client.url_builder import build_url

class APIClient:
    def __init__(self, base_url, connect_timeout=3.0, read_timeout=30.0):
        self.base_url = base_url
        self.connect_timeout = connect_timeout
        self.read_timeout = read_timeout
        self.session = requests.Session()

    def request(self, method, endpoint, params=None, auth=None):
        """Execute HTTP request with configured timeouts and auth."""
        url = build_url(f"{self.base_url}{endpoint}", params)
        
        headers = {}
        if auth:
            headers = auth.apply(headers)

        # BUG 3: Timeout tuple order is swapped. requests expects (connect, read)
        timeout = (self.read_timeout, self.connect_timeout)

        response = self.session.request(
            method,
            url,
            headers=headers,
            timeout=timeout
        )
        return response
EOF

# 4. auth.py (BUG: Bearer base64 encoding, missing X-API-Key header)
cat > "$WORKSPACE_DIR/client/auth.py" << 'EOF'
import base64

class BearerAuth:
    def __init__(self, token):
        self.token = token

    def apply(self, headers):
        """Apply Bearer token authentication to headers."""
        # BUG 4a: Bearer tokens should NOT be base64 encoded
        encoded_token = base64.b64encode(self.token.encode('utf-8')).decode('utf-8')
        headers['Authorization'] = f"Bearer {encoded_token}"
        return headers

class ApiKeyAuth:
    def __init__(self, api_key):
        self.api_key = api_key

    def apply(self, headers):
        """Apply API Key authentication to headers."""
        # BUG 4b: API key should be sent in X-API-Key header, not a generic api_key header
        headers['api_key'] = self.api_key
        return headers
EOF

# 5. pagination.py (BUG: Off-by-one, missing cursor termination)
cat > "$WORKSPACE_DIR/client/pagination.py" << 'EOF'
def fetch_all_pages(client, endpoint):
    """Fetch all pages from a page-based paginated endpoint."""
    items = []
    page = 1
    total_pages = 1

    # BUG 5a: < total_pages misses the last page of results
    while page < total_pages:
        response = client.request("GET", endpoint, params={"page": page})
        data = response.json()
        items.extend(data.get("items", []))
        total_pages = data.get("total_pages", 1)
        page += 1

    return items

def fetch_all_cursor(client, endpoint):
    """Fetch all pages from a cursor-based paginated endpoint."""
    items = []
    cursor = ""

    while True:
        response = client.request("GET", endpoint, params={"cursor": cursor})
        data = response.json()
        items.extend(data.get("items", []))
        cursor = data.get("next_cursor")
        
        # BUG 5b: No check for None/empty cursor. Will infinite loop on last page!
        # Missing: if not cursor: break

    return items
EOF

# Write Test File
cat > "$WORKSPACE_DIR/tests/test_client.py" << 'EOF'
import pytest
from client.url_builder import build_url
from client.retry import get_backoff, should_retry
from client.http_client import APIClient
from client.auth import BearerAuth, ApiKeyAuth

def test_url_builder_encoding():
    url = build_url("https://api.example.com/search", {"q": "hello world & universe"})
    assert "hello%20world" in url or "hello+world" in url, "Spaces should be encoded"
    assert "world+%26+universe" in url or "world%20%26%20universe" in url, "Ampersands should be encoded"

def test_retry_backoff_exponential():
    assert get_backoff(1, 1) == 2, "Backoff should be exponential (2^1)"
    assert get_backoff(1, 3) == 8, "Backoff should be exponential (2^3)"

def test_retry_status_codes():
    assert not should_retry(400), "Should not retry Bad Request"
    assert not should_retry(401), "Should not retry Unauthorized"
    assert not should_retry(404), "Should not retry Not Found"
    assert should_retry(500), "Should retry Internal Server Error"
    assert should_retry(429), "Should retry Rate Limit"

def test_bearer_auth():
    auth = BearerAuth("my-secret-token")
    headers = auth.apply({})
    assert headers["Authorization"] == "Bearer my-secret-token", "Bearer token should not be base64 encoded"

def test_apikey_auth():
    auth = ApiKeyAuth("api-key-123")
    headers = auth.apply({})
    assert "X-API-Key" in headers, "Must use X-API-Key header"
    assert headers["X-API-Key"] == "api-key-123"
EOF

# Make module packages
sudo -u ga touch "$WORKSPACE_DIR/client/__init__.py"
sudo -u ga touch "$WORKSPACE_DIR/tests/__init__.py"

# Set ownership
chown -R ga:ga "$WORKSPACE_DIR"

# Install test dependencies
echo "Installing dependencies..."
pip install -q pytest requests

# Launch VS Code pointing to the workspace
echo "Launching VS Code..."
if ! pgrep -f "code.*api_client" > /dev/null; then
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Maximize the window using wmctrl
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Give time for the UI to stabilize and take the initial screenshot
sleep 3
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="