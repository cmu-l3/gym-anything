#!/bin/bash
set -e
echo "=== Setting up implement_packet_parser task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/packet_parser"
mkdir -p "$PROJECT_DIR/parser"
mkdir -p "$PROJECT_DIR/tests"

# Clean previous run artifacts
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/parser" "$PROJECT_DIR/tests"
rm -f /tmp/packet_parser_result.json /tmp/packet_parser_hashes.txt

# --- Generate Project Files ---

# 1. requirements.txt
echo "pytest>=7.0" > "$PROJECT_DIR/requirements.txt"

# 2. parser/__init__.py
touch "$PROJECT_DIR/parser/__init__.py"

# 3. parser/exceptions.py (Complete)
cat > "$PROJECT_DIR/parser/exceptions.py" << 'EOF'
class PacketParseError(Exception):
    """Base exception for packet parsing errors."""
    pass

class TruncatedPacketError(PacketParseError):
    """Raised when the packet data is shorter than the expected header length."""
    pass

class InvalidHeaderError(PacketParseError):
    """Raised when header fields contain invalid or unsupported values."""
    pass
EOF

# 4. parser/ethernet.py (Stub)
cat > "$PROJECT_DIR/parser/ethernet.py" << 'EOF'
import struct
from dataclasses import dataclass
from typing import Tuple
from .exceptions import TruncatedPacketError

@dataclass
class EthernetFrame:
    dest_mac: str
    src_mac: str
    ethertype: int
    payload: bytes

def format_mac(mac_bytes: bytes) -> str:
    """Convert 6 bytes into a string like 'aa:bb:cc:dd:ee:ff'."""
    raise NotImplementedError("format_mac not implemented")

def parse_ethernet_frame(data: bytes) -> EthernetFrame:
    """
    Parse an Ethernet II frame.
    Header is 14 bytes: Dest MAC (6), Src MAC (6), Ethertype (2).
    Raises TruncatedPacketError if data < 14 bytes.
    """
    raise NotImplementedError("parse_ethernet_frame not implemented")
EOF

# 5. parser/ipv4.py (Stub)
cat > "$PROJECT_DIR/parser/ipv4.py" << 'EOF'
import struct
from dataclasses import dataclass
from typing import List
from .exceptions import TruncatedPacketError, InvalidHeaderError

@dataclass
class IPv4Header:
    version: int
    ihl: int
    dscp: int
    ecn: int
    total_length: int
    identification: int
    flags: int  # raw flags + fragment offset
    ttl: int
    protocol: int
    checksum: int
    src_ip: str
    dst_ip: str
    options: bytes
    payload: bytes

def format_ipv4(addr_bytes: bytes) -> str:
    """Convert 4 bytes into a string like '192.168.1.1'."""
    raise NotImplementedError("format_ipv4 not implemented")

def parse_ipv4_header(data: bytes) -> IPv4Header:
    """
    Parse IPv4 header.
    Raises TruncatedPacketError if data is too short.
    Raises InvalidHeaderError if version != 4 or IHL < 5.
    """
    raise NotImplementedError("parse_ipv4_header not implemented")
EOF

# 6. parser/tcp.py (Stub)
cat > "$PROJECT_DIR/parser/tcp.py" << 'EOF'
import struct
from dataclasses import dataclass
from .exceptions import TruncatedPacketError

@dataclass
class TCPHeader:
    src_port: int
    dst_port: int
    seq_num: int
    ack_num: int
    data_offset: int
    reserved: int
    flags: int  # Raw 9-bit flags
    window_size: int
    checksum: int
    urg_ptr: int
    options: bytes
    payload: bytes

    @property
    def syn(self) -> bool:
        return bool(self.flags & 0x002)

    @property
    def ack(self) -> bool:
        return bool(self.flags & 0x010)

    @property
    def fin(self) -> bool:
        return bool(self.flags & 0x001)

def parse_tcp_header(data: bytes) -> TCPHeader:
    """
    Parse TCP header.
    Raises TruncatedPacketError if data is too short.
    """
    raise NotImplementedError("parse_tcp_header not implemented")
EOF

# 7. parser/udp.py (Stub)
cat > "$PROJECT_DIR/parser/udp.py" << 'EOF'
import struct
from dataclasses import dataclass
from .exceptions import TruncatedPacketError

@dataclass
class UDPHeader:
    src_port: int
    dst_port: int
    length: int
    checksum: int
    payload: bytes

def parse_udp_header(data: bytes) -> UDPHeader:
    """
    Parse UDP header (8 bytes).
    Raises TruncatedPacketError if data < 8 bytes.
    """
    raise NotImplementedError("parse_udp_header not implemented")
EOF

# 8. parser/packet.py (Stub - Integration)
cat > "$PROJECT_DIR/parser/packet.py" << 'EOF'
from dataclasses import dataclass
from typing import Optional
from .ethernet import EthernetFrame, parse_ethernet_frame
from .ipv4 import IPv4Header, parse_ipv4_header
from .tcp import TCPHeader, parse_tcp_header
from .udp import UDPHeader, parse_udp_header
from .exceptions import PacketParseError

@dataclass
class Packet:
    ethernet: EthernetFrame
    ipv4: Optional[IPv4Header] = None
    tcp: Optional[TCPHeader] = None
    udp: Optional[UDPHeader] = None

def parse_packet(data: bytes) -> Packet:
    """
    Parse raw bytes into a full Packet object.
    1. Parse Ethernet.
    2. If Ethertype is 0x0800 (IPv4), parse IPv4.
    3. If IPv4 protocol is 6 (TCP), parse TCP.
    4. If IPv4 protocol is 17 (UDP), parse UDP.
    """
    raise NotImplementedError("parse_packet not implemented")
EOF

# --- Generate Test Files (With Real Data) ---

# 9. tests/conftest.py (Fixtures)
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest

# Real packet captures (hex dump converted to bytes)

# HTTP Packet (Eth/IP/TCP)
# Frame 1: 74 bytes on wire (592 bits), 74 bytes captured (592 bits)
# Ethernet II, Src: PcsCompu_20:b1:6a (08:00:27:20:b1:6a), Dst: RealtekU_12:35:02 (52:54:00:12:35:02)
# Internet Protocol Version 4, Src: 10.0.2.15, Dst: 104.16.124.96
# Transmission Control Protocol, Src Port: 44264, Dst Port: 80, Seq: 1, Ack: 1, Len: 0
HTTP_PACKET = bytes.fromhex(
    "52540012350208002720b16a0800"  # Ethernet
    "4500003c3069400040069a7c0a00020f68107c60"  # IPv4
    "acd8005085d3934d00000000a00272106e230000"  # TCP
    "020405b40402080a001a9d820000000001030307"  # TCP Options
)

# DNS Packet (Eth/IP/UDP)
# Standard query 0xda20 A www.google.com
DNS_PACKET = bytes.fromhex(
    "52540012350208002720b16a0800"  # Ethernet
    "4500003b8e72000040113c6b0a00020f08080808"  # IPv4
    "a6ea003500279d3e"  # UDP
    "da20010000010000000000000377777706676f6f676c6503636f6d0000010001"  # DNS Payload
)

@pytest.fixture
def http_packet_bytes():
    return HTTP_PACKET

@pytest.fixture
def dns_packet_bytes():
    return DNS_PACKET
EOF

# 10. tests/test_ethernet.py
cat > "$PROJECT_DIR/tests/test_ethernet.py" << 'EOF'
import pytest
from parser.ethernet import parse_ethernet_frame, format_mac
from parser.exceptions import TruncatedPacketError

def test_format_mac():
    assert format_mac(b'\x08\x00\x27\x20\xb1\x6a') == "08:00:27:20:b1:6a"
    assert format_mac(b'\xff\xff\xff\xff\xff\xff') == "ff:ff:ff:ff:ff:ff"

def test_parse_ethernet_http(http_packet_bytes):
    eth = parse_ethernet_frame(http_packet_bytes)
    assert eth.dest_mac == "52:54:00:12:35:02"
    assert eth.src_mac == "08:00:27:20:b1:6a"
    assert eth.ethertype == 0x0800
    # Payload starts after 14 bytes
    assert len(eth.payload) == len(http_packet_bytes) - 14

def test_parse_ethernet_truncated():
    with pytest.raises(TruncatedPacketError):
        parse_ethernet_frame(b'\x00' * 13)

def test_parse_ethernet_exact_size():
    data = b'\x00' * 14
    eth = parse_ethernet_frame(data)
    assert len(eth.payload) == 0
EOF

# 11. tests/test_ipv4.py
cat > "$PROJECT_DIR/tests/test_ipv4.py" << 'EOF'
import pytest
from parser.ipv4 import parse_ipv4_header, format_ipv4
from parser.exceptions import TruncatedPacketError, InvalidHeaderError

def test_format_ipv4():
    assert format_ipv4(b'\x0a\x00\x02\x0f') == "10.0.2.15"
    assert format_ipv4(b'\x7f\x00\x00\x01') == "127.0.0.1"

def test_parse_ipv4_http(http_packet_bytes):
    # Skip eth header (14 bytes)
    ip_data = http_packet_bytes[14:]
    ipv4 = parse_ipv4_header(ip_data)
    
    assert ipv4.version == 4
    assert ipv4.ihl == 5
    assert ipv4.total_length == 60
    assert ipv4.ttl == 64
    assert ipv4.protocol == 6 # TCP
    assert ipv4.src_ip == "10.0.2.15"
    assert ipv4.dst_ip == "104.16.124.96"
    assert len(ipv4.options) == 0
    assert len(ipv4.payload) == 60 - 20 # Total length - header length

def test_parse_ipv4_truncated():
    with pytest.raises(TruncatedPacketError):
        parse_ipv4_header(b'\x45' + b'\x00' * 18) # 19 bytes

def test_parse_ipv4_invalid_version():
    # Version 6
    with pytest.raises(InvalidHeaderError):
        parse_ipv4_header(b'\x65' + b'\x00' * 19)

def test_parse_ipv4_with_options():
    # IHL = 6 (24 bytes header)
    data = bytes.fromhex("4600001800000000400100007f0000017f000001deadbeef")
    ipv4 = parse_ipv4_header(data)
    assert ipv4.ihl == 6
    assert ipv4.options == b'\xde\xad\xbe\xef'
    assert len(ipv4.payload) == 0
EOF

# 12. tests/test_tcp.py
cat > "$PROJECT_DIR/tests/test_tcp.py" << 'EOF'
import pytest
from parser.tcp import parse_tcp_header
from parser.exceptions import TruncatedPacketError

def test_parse_tcp_http(http_packet_bytes):
    # Skip Eth (14) + IP (20)
    tcp_data = http_packet_bytes[34:]
    tcp = parse_tcp_header(tcp_data)
    
    assert tcp.src_port == 44264
    assert tcp.dst_port == 80
    assert tcp.seq_num == 2236961613
    assert tcp.ack_num == 0
    assert tcp.data_offset == 10 # 40 bytes header
    assert tcp.syn is True
    assert tcp.ack is False
    assert len(tcp.options) == 20 # 40 - 20 fixed

def test_parse_tcp_truncated():
    with pytest.raises(TruncatedPacketError):
        parse_tcp_header(b'\x00' * 19)

def test_parse_tcp_flags():
    # Flags = 0x012 (SYN, ACK)
    data = bytes.fromhex("0050005000000000000000005012000000000000")
    tcp = parse_tcp_header(data)
    assert tcp.syn is True
    assert tcp.ack is True
    assert tcp.fin is False
EOF

# 13. tests/test_udp.py
cat > "$PROJECT_DIR/tests/test_udp.py" << 'EOF'
import pytest
from parser.udp import parse_udp_header
from parser.exceptions import TruncatedPacketError

def test_parse_udp_dns(dns_packet_bytes):
    # Skip Eth (14) + IP (20)
    udp_data = dns_packet_bytes[34:]
    udp = parse_udp_header(udp_data)
    
    assert udp.src_port == 42730
    assert udp.dst_port == 53
    assert udp.length == 39
    assert len(udp.payload) == 39 - 8

def test_parse_udp_truncated():
    with pytest.raises(TruncatedPacketError):
        parse_udp_header(b'\x00' * 7)
EOF

# 14. tests/test_packet.py (Integration)
cat > "$PROJECT_DIR/tests/test_packet.py" << 'EOF'
import pytest
from parser.packet import parse_packet
from parser.exceptions import PacketParseError

def test_parse_full_http_packet(http_packet_bytes):
    pkt = parse_packet(http_packet_bytes)
    
    assert pkt.ethernet.dest_mac == "52:54:00:12:35:02"
    assert pkt.ipv4.src_ip == "10.0.2.15"
    assert pkt.ipv4.protocol == 6
    assert pkt.tcp is not None
    assert pkt.udp is None
    assert pkt.tcp.dst_port == 80

def test_parse_full_dns_packet(dns_packet_bytes):
    pkt = parse_packet(dns_packet_bytes)
    
    assert pkt.ipv4.protocol == 17
    assert pkt.udp is not None
    assert pkt.tcp is None
    assert pkt.udp.dst_port == 53

def test_parse_unknown_ethertype():
    # Ethertype 0x88CC (LLDP)
    data = bytes.fromhex("ffffffffffff00000000000088cc000000")
    pkt = parse_packet(data)
    assert pkt.ethernet.ethertype == 0x88cc
    assert pkt.ipv4 is None

def test_malformed_inner_header(http_packet_bytes):
    # Truncate to cut off part of TCP header
    truncated = http_packet_bytes[:35]
    with pytest.raises(PacketParseError):
        parse_packet(truncated)
EOF

# --- Set Permissions ---
chown -R ga:ga "$PROJECT_DIR"

# --- Record Anti-Gaming Baselines ---
# Store SHA256 hashes of test files to detect tampering
sha256sum "$PROJECT_DIR"/tests/*.py > /tmp/packet_parser_hashes.txt

# Store start time
date +%s > /tmp/task_start_time.txt

# --- Launch PyCharm ---
echo "Launching PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "packet_parser" 180

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="