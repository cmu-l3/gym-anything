#!/bin/bash
set -e
echo "=== Setting up implement_modbus_protocol task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="implement_modbus_protocol"
PROJECT_DIR="/home/ga/PycharmProjects/modbus_rtu"

# 1. Clean previous state
rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_result.json /tmp/${TASK_NAME}_start_ts

# 2. Create Project Structure
mkdir -p "$PROJECT_DIR/modbus"
mkdir -p "$PROJECT_DIR/tests"

# 3. Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
EOF

# 4. Create Implementation Stubs (The Agent's Work)

# modbus/__init__.py
touch "$PROJECT_DIR/modbus/__init__.py"

# modbus/crc.py
cat > "$PROJECT_DIR/modbus/crc.py" << 'EOF'
def compute_crc16(data: bytes) -> int:
    """
    Compute the CRC-16 (Modbus) for the given byte string.
    
    Algorithm:
    - Polynomial: 0xA001
    - Initial Value: 0xFFFF
    
    Args:
        data: The bytes to calculate CRC for.
        
    Returns:
        The calculated CRC as an integer.
    """
    raise NotImplementedError("TODO: Implement CRC-16/Modbus algorithm")
EOF

# modbus/frame.py
cat > "$PROJECT_DIR/modbus/frame.py" << 'EOF'
from typing import Tuple
from modbus.crc import compute_crc16

def build_request_frame(slave_id: int, pdu: bytes) -> bytes:
    """
    Construct a full Modbus RTU frame.
    
    Format: [Slave ID (1B)] + [PDU (N Bytes)] + [CRC (2B Little Endian)]
    
    Args:
        slave_id: Address of the slave (0-247)
        pdu: Protocol Data Unit (Function Code + Data)
        
    Returns:
        Full binary frame with CRC appended.
    """
    raise NotImplementedError("TODO: Implement frame construction")

def parse_response_frame(frame: bytes) -> Tuple[int, int, bytes]:
    """
    Parse a Modbus RTU response frame.
    
    1. Check minimum length (4 bytes: ID, FC, CRC-Lo, CRC-Hi)
    2. Validate CRC (calculated CRC of [ID+PDU] must match last 2 bytes)
    
    Args:
        frame: Received bytes
        
    Returns:
        Tuple of (slave_id, function_code, data_payload)
        
    Raises:
        ValueError: If frame is too short or CRC is invalid.
    """
    raise NotImplementedError("TODO: Implement frame parsing and validation")
EOF

# modbus/exceptions.py
cat > "$PROJECT_DIR/modbus/exceptions.py" << 'EOF'
class ModbusException(Exception):
    """Base exception for Modbus errors."""
    def __init__(self, code: int, message: str = ""):
        self.code = code
        self.message = message
        super().__init__(f"Modbus Error {code}: {message}")

def is_exception_response(function_code: int) -> bool:
    """
    Check if a function code indicates an exception response.
    Exception responses have the high bit (0x80) set.
    """
    raise NotImplementedError("TODO: Check MSB of function code")

def parse_exception_response(function_code: int, data: bytes):
    """
    Parse exception data and raise ModbusException.
    
    Args:
        function_code: The raw function code (with 0x80 set)
        data: The payload containing the exception code (1 byte)
        
    Raises:
        ModbusException: With the specific exception code.
    """
    raise NotImplementedError("TODO: Extract exception code and raise error")
EOF

# modbus/functions.py
cat > "$PROJECT_DIR/modbus/functions.py" << 'EOF'
import struct
from typing import List, Tuple

# Function Codes
READ_COILS = 0x01
READ_HOLDING_REGISTERS = 0x03
WRITE_SINGLE_REGISTER = 0x06
WRITE_MULTIPLE_REGISTERS = 0x10

def build_read_coils_request(start_address: int, quantity: int) -> bytes:
    """FC01: [FC] [StartAddr (H,L)] [Qty (H,L)]"""
    raise NotImplementedError("TODO: Implement FC01 request")

def build_read_holding_registers_request(start_address: int, quantity: int) -> bytes:
    """FC03: [FC] [StartAddr (H,L)] [Qty (H,L)]"""
    raise NotImplementedError("TODO: Implement FC03 request")

def build_write_single_register_request(address: int, value: int) -> bytes:
    """FC06: [FC] [Addr (H,L)] [Value (H,L)]"""
    raise NotImplementedError("TODO: Implement FC06 request")

def build_write_multiple_registers_request(start_address: int, values: List[int]) -> bytes:
    """FC16: [FC] [StartAddr (H,L)] [Qty (H,L)] [ByteCount] [Val1 (H,L)]..."""
    raise NotImplementedError("TODO: Implement FC16 request")

def parse_read_coils_response(data: bytes) -> List[bool]:
    """
    FC01 Response: [ByteCount] [CoilStatus...]
    Returns list of booleans.
    Note: Coils are packed LSB first.
    """
    raise NotImplementedError("TODO: Implement FC01 response parsing")

def parse_read_holding_registers_response(data: bytes) -> List[int]:
    """
    FC03 Response: [ByteCount] [Val1 (H,L)] [Val2 (H,L)]...
    Returns list of integers.
    """
    raise NotImplementedError("TODO: Implement FC03 response parsing")

def parse_write_single_register_response(data: bytes) -> Tuple[int, int]:
    """
    FC06 Response: [Addr (H,L)] [Value (H,L)]
    Returns (address, value_written)
    """
    raise NotImplementedError("TODO: Implement FC06 response parsing")

def parse_write_multiple_registers_response(data: bytes) -> Tuple[int, int]:
    """
    FC16 Response: [StartAddr (H,L)] [Qty (H,L)]
    Returns (start_address, quantity_written)
    """
    raise NotImplementedError("TODO: Implement FC16 response parsing")
EOF

# 5. Create Tests (The Verification Standard)

# tests/conftest.py
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import sys
import os

# Ensure modbus package is importable
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
EOF

# tests/test_crc.py
cat > "$PROJECT_DIR/tests/test_crc.py" << 'EOF'
import pytest
from modbus.crc import compute_crc16

def test_crc_basic_string():
    # '123456789'
    data = b'123456789'
    # CRC-16/MODBUS check value for this string is 0x4B37
    assert compute_crc16(data) == 0x4B37

def test_crc_modbus_example():
    # Example from Modbus Spec: Read Holding Registers
    # 02 07 -> CRC is 0x4112 (swapped is 12 41)
    # Note: Our compute_crc16 returns int, not bytes.
    # 0x02, 0x07 (Slave 2, Error?) - arbitrary data
    data = bytes([0x02, 0x07])
    assert compute_crc16(data) == 0x1241

def test_crc_empty():
    # Init value 0xFFFF, no updates -> 0xFFFF? 
    # Actually, standard implementation loops over bytes. If empty, returns init value 0xFFFF
    assert compute_crc16(b'') == 0xFFFF

def test_crc_null_bytes():
    # 00 00
    assert compute_crc16(b'\x00\x00') != 0x0000

def test_crc_fc03_request():
    # Spec Ex: 11 03 00 6B 00 03
    # Expected CRC: 76 87 (Low High) -> Int: 0x8776
    data = bytes([0x11, 0x03, 0x00, 0x6B, 0x00, 0x03])
    assert compute_crc16(data) == 0x8776
EOF

# tests/test_frame.py
cat > "$PROJECT_DIR/tests/test_frame.py" << 'EOF'
import pytest
import struct
from modbus.frame import build_request_frame, parse_response_frame

def test_build_request_frame():
    slave_id = 0x11
    pdu = bytes([0x03, 0x00, 0x6B, 0x00, 0x03])
    # CRC of 11 03 00 6B 00 03 is 0x8776
    # Frame should be: ID + PDU + CRC_Lo + CRC_Hi
    expected = bytes([0x11, 0x03, 0x00, 0x6B, 0x00, 0x03, 0x76, 0x87])
    
    result = build_request_frame(slave_id, pdu)
    assert result == expected

def test_parse_response_frame_valid():
    # 11 03 06 AE 41 56 52 43 40 49 AD
    # CRC of [11 03 06 AE 41 56 52 43 40] is 0xAD49
    # Frame has 49 AD at end
    frame = bytes([0x11, 0x03, 0x06, 0xAE, 0x41, 0x56, 0x52, 0x43, 0x40, 0x49, 0xAD])
    
    sid, fc, data = parse_response_frame(frame)
    assert sid == 0x11
    assert fc == 0x03
    assert data == bytes([0x06, 0xAE, 0x41, 0x56, 0x52, 0x43, 0x40])

def test_parse_response_frame_invalid_crc():
    # Corrupt last byte
    frame = bytes([0x11, 0x03, 0x06, 0xAE, 0x41, 0x56, 0x52, 0x43, 0x40, 0x49, 0xFF])
    with pytest.raises(ValueError, match="Invalid CRC"):
        parse_response_frame(frame)

def test_parse_response_frame_too_short():
    frame = b'\x01\x02\x03' # < 4 bytes
    with pytest.raises(ValueError):
        parse_response_frame(frame)

def test_build_request_frame_endianness():
    # Ensure CRC is little endian
    # 01 06 00 01 00 03 -> CRC 98 0B (0x0B98)
    # Frame: 01 06 00 01 00 03 98 0B
    res = build_request_frame(0x01, bytes([0x06, 0x00, 0x01, 0x00, 0x03]))
    assert res[-2:] == b'\x98\x0B'
EOF

# tests/test_functions.py
cat > "$PROJECT_DIR/tests/test_functions.py" << 'EOF'
import pytest
from modbus import functions

def test_build_read_coils():
    # FC01: 19(0x13) to 37 (Qty 0x19=25)
    # Req: 01 00 13 00 19
    req = functions.build_read_coils_request(0x13, 0x19)
    assert req == bytes([0x01, 0x00, 0x13, 0x00, 0x19])

def test_build_write_single_register():
    # FC06: Addr 0x01, Val 0x03
    # Req: 06 00 01 00 03
    req = functions.build_write_single_register_request(0x01, 0x03)
    assert req == bytes([0x06, 0x00, 0x01, 0x00, 0x03])

def test_build_write_multiple_registers():
    # FC16: Start 0x01, 2 Regs, Vals [0x0A, 0x0102]
    # Req: 10 00 01 00 02 04 00 0A 01 02
    req = functions.build_write_multiple_registers_request(0x01, [0x0A, 0x102])
    assert req == bytes([0x10, 0x00, 0x01, 0x00, 0x02, 0x04, 0x00, 0x0A, 0x01, 0x02])

def test_parse_read_coils_response():
    # FC01 Resp: ByteCount 3, CD 6B 05
    # CD = 1100 1101 (Coils 27-20: 1 0 1 1 0 0 1 1) -> LSB is Coil 20 (1)
    data = bytes([0x03, 0xCD, 0x6B, 0x05])
    coils = functions.parse_read_coils_response(data)
    assert len(coils) == 24 # 3 bytes * 8
    # Check first byte 0xCD (1100 1101) -> LSB First: 1, 0, 1, 1, 0, 0, 1, 1
    assert coils[0] == True
    assert coils[1] == False
    assert coils[2] == True

def test_parse_read_holding_registers():
    # FC03 Resp: ByteCount 4, 02 2B 00 00
    data = bytes([0x04, 0x02, 0x2B, 0x00, 0x00])
    regs = functions.parse_read_holding_registers_response(data)
    assert len(regs) == 2
    assert regs[0] == 0x022B # 555
    assert regs[1] == 0x0000

def test_parse_write_single_response():
    # FC06 Resp: Echo request
    data = bytes([0x00, 0x01, 0x00, 0x03])
    addr, val = functions.parse_write_single_register_response(data)
    assert addr == 0x01
    assert val == 0x03
EOF

# tests/test_exceptions.py
cat > "$PROJECT_DIR/tests/test_exceptions.py" << 'EOF'
import pytest
from modbus import exceptions

def test_is_exception_response():
    assert exceptions.is_exception_response(0x81) == True # FC01 | 0x80
    assert exceptions.is_exception_response(0x83) == True
    assert exceptions.is_exception_response(0x01) == False

def test_parse_exception_response():
    # FC 0x81, ExCode 0x02 (Illegal Data Address)
    with pytest.raises(exceptions.ModbusException) as excinfo:
        exceptions.parse_exception_response(0x81, bytes([0x02]))
    
    assert excinfo.value.code == 0x02
    assert "Modbus Error 2" in str(excinfo.value)

def test_parse_exception_empty():
    with pytest.raises(Exception):
        exceptions.parse_exception_response(0x81, b'')
EOF

# 6. Record Test File Integrity (Anti-Gaming)
# We store the hashes of the test files. If the agent modifies them to pass, we'll know.
echo "Recording test file hashes..."
md5sum "$PROJECT_DIR"/tests/*.py > /tmp/test_hashes_initial.txt

# 7. Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# 8. Open PyCharm
echo "Launching PyCharm..."
setup_pycharm_project "$PROJECT_DIR" "modbus_rtu"

# Initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="