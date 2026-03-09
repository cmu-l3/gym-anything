#!/bin/bash
set -e
echo "=== Setting up Configure Reverse Proxy task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Record initial state (check if proxy config already exists)
INITIAL_PROXY_COUNT=$(grep -r "ProxyPass" /etc/apache2/sites-available/ 2>/dev/null | grep -c "acmecorp" || echo "0")
echo "$INITIAL_PROXY_COUNT" > /tmp/initial_proxy_count.txt

# 3. Ensure acmecorp.test resolves locally (needed for curl testing)
if ! grep -q "acmecorp.test" /etc/hosts; then
    echo "127.0.0.1 acmecorp.test" >> /etc/hosts
fi

# 4. Start a backend HTTP server on port 3001
# This simulates the internal Node.js app
echo "Starting backend HTTP server on port 3001..."
pkill -f "backend_server.py" || true

cat > /tmp/backend_server.py << 'PYEOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import sys

class BackendHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'BACKEND_RESPONSE_OK')
    
    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 3001), BackendHandler)
    print("Backend server running on port 3001")
    sys.stdout.flush()
    server.serve_forever()
PYEOF

nohup python3 /tmp/backend_server.py > /tmp/backend_server.log 2>&1 &
echo $! > /tmp/backend_server.pid

# Verify backend is up
for i in {1..10}; do
    if curl -s http://localhost:3001/ | grep -q "BACKEND_RESPONSE_OK"; then
        echo "Backend server is responding."
        break
    fi
    sleep 1
done

# 5. Ensure Virtualmin is ready and open in Firefox
ensure_virtualmin_ready
sleep 2

# Navigate to acmecorp.test domain summary
DOMAIN_ID=$(get_domain_id "acmecorp.test")
if [ -n "$DOMAIN_ID" ]; then
    navigate_to "${VIRTUALMIN_URL}/virtual-server/summary_domain.cgi?dom=${DOMAIN_ID}"
else
    # Fallback if domain doesn't exist (unlikely in this env)
    navigate_to "${VIRTUALMIN_URL}/virtual-server/index.cgi"
fi
sleep 3

# 6. Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="