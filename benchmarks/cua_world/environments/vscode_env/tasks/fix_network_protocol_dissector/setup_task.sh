#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Network Protocol Dissector Task ==="

WORKSPACE_DIR="/home/ga/workspace/packet_dissector"
sudo -u ga mkdir -p "$WORKSPACE_DIR/parsers"
sudo -u ga mkdir -p "$WORKSPACE_DIR/core"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# ─── parsers/ip_parser.py (BUG: Missing carry fold in checksum) ─────────
cat > "$WORKSPACE_DIR/parsers/ip_parser.py" << 'EOF'
"""IPv4 Header Parser"""

def validate_checksum(header_bytes):
    """
    Validates an IPv4 header checksum per RFC 791.
    Returns True if valid, False otherwise.
    """
    if len(header_bytes) % 2 != 0:
        return False
        
    total = 0
    for i in range(0, len(header_bytes), 2):
        word = (header_bytes[i] << 8) + header_bytes[i+1]
        total += word

    # BUG: One's complement carries are not folded back into the lower 16 bits.
    # If total exceeds 0xFFFF, this will incorrectly fail valid packets.
    return (total & 0xFFFF) == 0xFFFF
EOF

# ─── parsers/tcp_tracker.py (BUG: Seq wraparound) ─────────────────────────
cat > "$WORKSPACE_DIR/parsers/tcp_tracker.py" << 'EOF'
"""TCP Connection State Tracker"""

def is_next_expected(seq_num, last_ack):
    """
    Returns True if seq_num is the next expected sequence number or later.
    Must correctly account for TCP sequence number wraparound (RFC 1323).
    """
    # BUG: A plain integer comparison fails when seq_num wraps past 2^32.
    # RFC 1323 defines 'greater than' using modular arithmetic.
    return seq_num >= last_ack
EOF

# ─── parsers/dns_parser.py (BUG: Compression offset relative to wrong base)
cat > "$WORKSPACE_DIR/parsers/dns_parser.py" << 'EOF'
"""DNS Message Parser"""

def decompress_name(packet_bytes, offset, dns_msg_start):
    """
    Decompresses a DNS domain name from the packet bytes.
    DNS compression pointers are relative to the start of the DNS message.
    Returns (domain_string, next_offset).
    """
    labels = []
    while True:
        if offset >= len(packet_bytes):
            break
            
        byte = packet_bytes[offset]
        if byte == 0:
            offset += 1
            break
            
        if (byte & 0xC0) == 0xC0:
            # Compression pointer
            pointer = ((byte & 0x3F) << 8) | packet_bytes[offset + 1]
            
            # BUG: The pointer is passed directly as an offset into packet_bytes.
            # It needs to be offset by dns_msg_start!
            ptr_name, _ = decompress_name(packet_bytes, pointer, dns_msg_start)
            labels.append(ptr_name)
            offset += 2
            break
        else:
            length = byte
            offset += 1
            labels.append(packet_bytes[offset:offset+length].decode('utf-8'))
            offset += length
            
    return ".".join(labels), offset
EOF

# ─── parsers/http_parser.py (BUG: String comparison for Content-Length) ──
cat > "$WORKSPACE_DIR/parsers/http_parser.py" << 'EOF'
"""HTTP Message Parser"""

def classify_response_size(headers):
    """
    Classify the HTTP response size based on Content-Length.
    Returns 'large' if > 1000 bytes, 'small' otherwise.
    """
    content_length = headers.get("Content-Length", "0")
    
    # BUG: String comparison evaluates "9" > "1000" as True
    if content_length > "1000":
        return "large"
        
    return "small"
EOF

# ─── parsers/tls_parser.py (BUG: Checking record version instead of ext) ──
cat > "$WORKSPACE_DIR/parsers/tls_parser.py" << 'EOF'
"""TLS Record Parser"""

TLS_VERSIONS = {
    0x0301: "TLS 1.0",
    0x0302: "TLS 1.1",
    0x0303: "TLS 1.2",
    0x0304: "TLS 1.3"
}

def detect_tls_version(record_bytes):
    """
    Detects the TLS version from a ClientHello/ServerHello record.
    Note: TLS 1.3 mandates the record layer version be 0x0301 (TLS 1.0) 
    for backward compatibility, placing the true version in the 
    'supported_versions' extension (type 0x002B).
    """
    if len(record_bytes) < 5:
        return "Unknown"
        
    record_version = (record_bytes[1] << 8) | record_bytes[2]
    
    # BUG: Only checks the record layer version. 
    # For TLS 1.3, this incorrectly returns "TLS 1.0".
    return TLS_VERSIONS.get(record_version, "Unknown")
EOF

# ─── tests/test_all.py (Basic Test Suite) ──────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_all.py" << 'EOF'
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from parsers.ip_parser import validate_checksum
from parsers.tcp_tracker import is_next_expected
from parsers.dns_parser import decompress_name
from parsers.http_parser import classify_response_size
from parsers.tls_parser import detect_tls_version

def test_ip_checksum():
    # RFC 1071 valid checksum example needing carry folds
    header = bytes.fromhex("45000073000040004011b861c0a80001c0a800c7")
    assert validate_checksum(header) == True, "IP Checksum failed on valid packet!"

def test_tcp_wraparound():
    # Sequence numbers wrapping around 2^32
    assert is_next_expected(100, 4294967290) == True, "TCP Wraparound failed!"
    assert is_next_expected(4294967200, 100) == False, "TCP Wraparound logic flawed!"

def test_dns_compression():
    # Fake packet with Ethernet, IP, UDP headers (42 bytes), then DNS msg
    packet = (b'\x00' * 42) + bytes.fromhex("0000000000000000000000000377777706676f6f676c6503636f6d00c00c")
    # dns_msg_start = 42. Offset 57 is the pointer c0 0c (points to offset 12 in DNS msg = 42 + 12 = 54)
    name, _ = decompress_name(packet, 57, 42)
    assert name == "google.com", f"DNS decompression failed: got {name}"

def test_http_size():
    assert classify_response_size({"Content-Length": "9"}) == "small", "HTTP size failed on '9'"
    assert classify_response_size({"Content-Length": "2000"}) == "large", "HTTP size failed on '2000'"

def test_tls_version():
    # TLS 1.3 ClientHello (Record layer says 0301, supported_versions extension says 0304)
    # Simulated structure: RecType(1)|RecVer(0301)|Len(2)|ExtType(002B)|...
    record = bytes.fromhex("1603010006002b00020304")
    assert detect_tls_version(record) == "TLS 1.3", "TLS 1.3 detection failed!"

if __name__ == "__main__":
    tests = [test_ip_checksum, test_tcp_wraparound, test_dns_compression, test_http_size, test_tls_version]
    passed = 0
    for t in tests:
        try:
            t()
            print(f"✅ {t.__name__} passed")
            passed += 1
        except AssertionError as e:
            print(f"❌ {t.__name__} failed: {e}")
        except Exception as e:
            print(f"❌ {t.__name__} crashed: {e}")
            
    print(f"\n{passed}/{len(tests)} tests passed.")
EOF

# Ensure correct permissions
chown -R ga:ga "$WORKSPACE_DIR"
chmod -R 755 "$WORKSPACE_DIR"

# Launch VSCode
echo "Starting VSCode..."
su - ga -c "code $WORKSPACE_DIR" &
sleep 5

# Wait for VSCode to initialize
wait_for_vscode 30
focus_vscode_window 2>/dev/null || true

# Maximize the window
WID=$(get_vscode_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
echo "Taking initial screenshot..."
take_screenshot /tmp/task_initial_state.png ga

# Timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="