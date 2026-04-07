#!/bin/bash
echo "=== Setting up API Debugging Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create application directory with proper permissions
mkdir -p /var/lib/app
chown ga:ga /var/lib/app

# Create the Python backend mock server
cat > /tmp/api_server.py << 'EOF'
import json
import sqlite3
import os
from http.server import HTTPServer, BaseHTTPRequestHandler

DB_PATH = '/var/lib/app/telemetry.db'

# Initialize SQLite database
conn = sqlite3.connect(DB_PATH)
c = conn.cursor()
c.execute('''CREATE TABLE IF NOT EXISTS requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    method TEXT,
    path TEXT,
    payload TEXT,
    user_agent TEXT,
    status_code INTEGER
)''')
conn.commit()
conn.close()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/admin':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>Admin Dashboard</title>
                <style>
                    body { font-family: sans-serif; padding: 40px; background-color: #f4f4f5; }
                    .card { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); max-width: 500px; margin: 0 auto; }
                    button { background: #0060df; color: white; border: none; padding: 12px 24px; font-size: 16px; border-radius: 4px; cursor: pointer; }
                    button:hover { background: #003eaa; }
                    #result { margin-top: 20px; padding: 15px; border-radius: 4px; display: none; }
                    .error { background: #ffebee; color: #c62828; border: 1px solid #ffcdd2; }
                    .success { background: #e8f5e9; color: #2e7d32; border: 1px solid #c8e6c9; }
                </style>
            </head>
            <body>
                <div class="card">
                    <h2>Admin Dashboard</h2>
                    <p>Trigger manual synchronization for the CRM telemetry system.</p>
                    <button id="syncBtn">Sync CRM Telemetry</button>
                    <div id="result"></div>
                </div>
                <script>
                    document.getElementById('syncBtn').addEventListener('click', () => {
                        const resultDiv = document.getElementById('result');
                        resultDiv.style.display = 'block';
                        resultDiv.className = '';
                        resultDiv.innerText = 'Syncing...';
                        
                        fetch('/api/v1/telemetry/sync', {
                            method: 'POST',
                            headers: {'Content-Type': 'application/json'},
                            body: JSON.stringify({
                                "mode": "bidirectonal", 
                                "force_refresh": false
                            })
                        }).then(async res => {
                            const text = await res.text();
                            if (res.ok) {
                                resultDiv.className = 'success';
                                resultDiv.innerText = 'Success: ' + text;
                            } else {
                                resultDiv.className = 'error';
                                resultDiv.innerText = 'Error ' + res.status + ': ' + text;
                            }
                        }).catch(err => {
                            resultDiv.className = 'error';
                            resultDiv.innerText = 'Network Error: ' + err.message;
                        });
                    });
                </script>
            </body>
            </html>
            """
            self.wfile.write(html.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        if self.path == '/api/v1/telemetry/sync':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length).decode('utf-8')

            user_agent = self.headers.get('User-Agent', '')
            status_code = 400
            
            # Default error message
            response_json = {"error": "Invalid synchronization mode. Expected 'bidirectional', got 'bidirectonal'."}
            
            try:
                data = json.loads(post_data)
                if data.get('mode') == 'bidirectional' and data.get('force_refresh') is True:
                    status_code = 200
                    response_json = {"status": "success", "message": "Telemetry synced successfully."}
                elif data.get('mode') == 'bidirectional':
                    response_json = {"error": "Mode is correct, but force_refresh must be set to true for manual syncs."}
            except json.JSONDecodeError:
                response_json = {"error": "Malformed JSON payload."}

            # Log to DB
            conn = sqlite3.connect(DB_PATH)
            c = conn.cursor()
            c.execute('INSERT INTO requests (method, path, payload, user_agent, status_code) VALUES (?, ?, ?, ?, ?)',
                      ('POST', self.path, post_data, user_agent, status_code))
            conn.commit()
            conn.close()

            self.send_response(status_code)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response_json).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

server = HTTPServer(('0.0.0.0', 8080), Handler)
server.serve_forever()
EOF

# Make sure it's owned by ga
chown ga:ga /tmp/api_server.py

# Start the mock server in the background
su - ga -c "python3 /tmp/api_server.py > /tmp/api_server.log 2>&1 &"

# Wait for the server to be responsive
echo "Waiting for local server to spin up..."
for i in {1..30}; do
    if curl -s http://localhost:8080/admin > /dev/null; then
        echo "Server is running!"
        break
    fi
    sleep 1
done

# Start Firefox and navigate directly to the admin page
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080/admin &"
    sleep 5
fi

# Ensure window is maximized for better visibility
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="