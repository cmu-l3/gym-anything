#!/bin/bash
echo "=== Setting up fix_barcode_encoder task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_barcode_encoder"
PROJECT_DIR="/home/ga/PycharmProjects/barcode_encoder"

# 1. Clean up previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_result.json 2>/dev/null || true

# 2. Create project structure
mkdir -p "$PROJECT_DIR/encoder"
mkdir -p "$PROJECT_DIR/tests"

# 3. Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
EOF

# 4. Create source files

# --- encoder/__init__.py ---
touch "$PROJECT_DIR/encoder/__init__.py"

# --- encoder/tables.py (Lookup tables - Correct) ---
cat > "$PROJECT_DIR/encoder/tables.py" << 'EOF'
"""
Lookup tables for barcode patterns.
Represented as binary strings where '1' is a bar and '0' is a space.
"""

# UPC-A L-patterns (Left side digits)
# Digit: Pattern (7 modules)
UPC_L_PATTERNS = {
    0: "0001101", 1: "0011001", 2: "0010011", 3: "0111101", 4: "0100011",
    5: "0110001", 6: "0101111", 7: "0111011", 8: "0110111", 9: "0001011"
}

# UPC-A R-patterns (Right side digits) are logical NOT of L-patterns (inverted)
# (Logic handles this dynamically, or we could list them)

# Code 128 Patterns (Table B subset for simplicity)
# Value: Pattern (11 modules)
CODE128_PATTERNS = {
    0: "11011001100", # Space
    # ... truncated for brevity, providing only needed chars for tests ...
    33: "10000110010", # A
    34: "10010011000", # B
    35: "10010001100", # C
    # Start Code B (Value 104)
    104: "11010010000",
    # Stop Character (Value 106)
    106: "11000111010",
}

# Helper to map ASCII to Code 128 Values (Subset)
ASCII_TO_128_VAL = {
    " ": 0, "A": 33, "B": 34, "C": 35
    # In a real lib this covers all ASCII
}
EOF

# --- encoder/upc.py (Contains BUG 1) ---
cat > "$PROJECT_DIR/encoder/upc.py" << 'EOF'
"""
UPC-A Encoding Logic.
"""
from .tables import UPC_L_PATTERNS

def calculate_check_digit(digits: list[int]) -> int:
    """
    Calculate the UPC-A check digit for a list of 11 integers.
    
    Standard:
    1. Sum digits at odd-numbered positions (1st, 3rd...). Multiply by 3.
    2. Sum digits at even-numbered positions (2nd, 4th...).
    3. Add results.
    4. Check digit is the number needed to round up to nearest multiple of 10.
    
    Note: Input 'digits' is 0-indexed.
    Index 0 is the 1st digit (odd position).
    Index 1 is the 2nd digit (even position).
    """
    if len(digits) != 11:
        raise ValueError("Must provide exactly 11 digits")
    
    # BUG 1: The weighting is swapped.
    # Current (Buggy): Evens * 3, Odds * 1
    # Correct: Odds * 3, Evens * 1
    
    sum_odd_pos = sum(digits[1::2])  # Indices 1, 3, 5... (These are EVEN positions in 1-based)
    sum_even_pos = sum(digits[0::2]) # Indices 0, 2, 4... (These are ODD positions in 1-based)
    
    # The bug is here: multiplying the wrong sum by 3
    total = (sum_odd_pos * 3) + sum_even_pos
    
    remainder = total % 10
    if remainder == 0:
        return 0
    return 10 - remainder

def encode_upc_a(number_str: str) -> str:
    """Encode a 11 or 12 digit string into binary UPC-A pattern."""
    if not number_str.isdigit():
        raise ValueError("Input must be digits")
        
    digits = [int(d) for d in number_str]
    
    if len(digits) == 11:
        digits.append(calculate_check_digit(digits))
    elif len(digits) == 12:
        # Validate existing check digit
        expected = calculate_check_digit(digits[:-1])
        if digits[-1] != expected:
            raise ValueError(f"Invalid check digit. Expected {expected}, got {digits[-1]}")
    else:
        raise ValueError("Length must be 11 or 12")
        
    # Start Guard: 101
    pattern = "101"
    
    # Left 6 digits
    for i in range(6):
        pattern += UPC_L_PATTERNS[digits[i]]
        
    # Center Guard: 01010
    pattern += "01010"
    
    # Right 6 digits (Inverted L-patterns)
    for i in range(6, 12):
        l_pat = UPC_L_PATTERNS[digits[i]]
        # Invert: 0->1, 1->0
        r_pat = "".join("1" if c == "0" else "0" for c in l_pat)
        pattern += r_pat
        
    # End Guard: 101
    pattern += "101"
    
    return pattern
EOF

# --- encoder/code128.py (Contains BUG 2 and BUG 3) ---
cat > "$PROJECT_DIR/encoder/code128.py" << 'EOF'
"""
Code 128 Encoding Logic (Subset B).
"""
from .tables import CODE128_PATTERNS, ASCII_TO_128_VAL

def calculate_checksum(values: list[int]) -> int:
    """
    Calculate Code 128 Checksum.
    Formula: (StartValue + Sum(Value * Position)) % 103
    Position starts at 1 for the first data character.
    """
    if not values:
        return 0
        
    # Start Code B value is 104
    total = 104
    
    for i, val in enumerate(values):
        # Position is i + 1
        total += val * (i + 1)
        
    # BUG 2: Using modulo 100 instead of 103
    return total % 100

def encode_code128_b(text: str) -> str:
    """
    Encode text using Code 128 Set B.
    """
    # Convert text to values
    try:
        values = [ASCII_TO_128_VAL[c] for c in text]
    except KeyError:
        # Fallback/Mock for characters not in our tiny table
        values = [33 for _ in text] # Treat unknown as 'A' for this mock
        
    checksum_val = calculate_checksum(values)
    
    # Construct Pattern
    # 1. Start Code B (104)
    pattern = CODE128_PATTERNS[104]
    
    # 2. Data Characters
    for val in values:
        if val in CODE128_PATTERNS:
            pattern += CODE128_PATTERNS[val]
        else:
            # Mock fallback
            pattern += CODE128_PATTERNS[33]
            
    # 3. Checksum
    # Mocking checksum pattern lookup if not in table
    pattern += CODE128_PATTERNS.get(checksum_val, "10000000000")
    
    # 4. Stop Character
    # BUG 3: Missing the final termination bar.
    # The stop pattern in Code 128 is the Stop Character (106) PLUS a termination bar (11).
    # The lookup table only has the 11-module stop character "11000111010".
    # We should append "11" here.
    pattern += CODE128_PATTERNS[106]
    
    return pattern
EOF

# 5. Create Tests

# --- tests/conftest.py ---
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
EOF

# --- tests/test_upc.py ---
cat > "$PROJECT_DIR/tests/test_upc.py" << 'EOF'
import pytest
from encoder.upc import calculate_check_digit, encode_upc_a

def test_upc_check_digit_standard_case():
    # 03600029145 -> Expected Check Digit: 2
    # Odd positions (0,6,0,2,1,5): 0+6+0+2+1+5 = 14. 14 * 3 = 42.
    # Even positions (3,0,0,9,4): 3+0+0+9+4 = 16.
    # Total: 42 + 16 = 58. Next multiple of 10 is 60. Check digit = 2.
    digits = [0, 3, 6, 0, 0, 0, 2, 9, 1, 4, 5]
    assert calculate_check_digit(digits) == 2

def test_upc_check_digit_zero_case():
    # 00000000000 -> 0
    digits = [0] * 11
    assert calculate_check_digit(digits) == 0

def test_upc_check_digit_another_sample():
    # 72527273070 -> Expected Check Digit: 6
    # Odds (7,5,7,7,0,0): 26 * 3 = 78
    # Evens (2,2,2,3,7): 16
    # Total 94 -> Next 100 -> Check 6
    digits = [7, 2, 5, 2, 7, 2, 7, 3, 0, 7, 0]
    assert calculate_check_digit(digits) == 6

def test_upc_encoding_length():
    # Should produce 95 modules (3 + 6*7 + 5 + 6*7 + 3)
    res = encode_upc_a("036000291452")
    assert len(res) == 95

def test_upc_encoding_start_guard():
    res = encode_upc_a("036000291452")
    assert res.startswith("101")

def test_upc_encoding_end_guard():
    res = encode_upc_a("036000291452")
    assert res.endswith("101")

def test_upc_throws_on_invalid_check_digit():
    with pytest.raises(ValueError):
        encode_upc_a("036000291459") # Wrong check digit
EOF

# --- tests/test_code128.py ---
cat > "$PROJECT_DIR/tests/test_code128.py" << 'EOF'
import pytest
from encoder.code128 import calculate_checksum, encode_code128_b

def test_code128_checksum_simple():
    # Start B (104). Data: 'A' (33).
    # Checksum = (104 + 33*1) % 103 = 137 % 103 = 34
    # If bug exists (% 100), result is 37.
    values = [33]
    assert calculate_checksum(values) == 34

def test_code128_checksum_complex():
    # Start B (104). Data: 'A', 'B' (33, 34).
    # Checksum = (104 + 33*1 + 34*2) % 103
    # = (104 + 33 + 68) % 103 = 205 % 103 = 102
    values = [33, 34]
    assert calculate_checksum(values) == 102

def test_code128_stop_pattern_termination():
    # The encoded string must end with the Stop Character (106) followed by termination bar (11)
    # Pattern for 106 is "11000111010"
    # Total end sequence should be "1100011101011"
    
    # We use a simple input 'A'
    res = encode_code128_b("A")
    
    # Check the last 13 characters
    expected_end = "1100011101011"
    assert res.endswith(expected_end), f"Barcode does not end with valid stop pattern + termination bar. Got suffix: {res[-13:]}"

def test_code128_length_consistency():
    # Start(11) + Char(11) + Check(11) + Stop(13 with term bar)
    # Total = 46 modules for 1 char input
    res = encode_code128_b("A")
    assert len(res) == 46
EOF

# 6. Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# 7. Start PyCharm
# Use nohup to ensure it stays running
nohup su - ga -c "DISPLAY=:1 /opt/pycharm/bin/pycharm.sh $PROJECT_DIR" > /tmp/pycharm_launch.log 2>&1 &

# Wait for PyCharm
wait_for_pycharm 60

# Maximize
DISPLAY=:1 wmctrl -r "PyCharm" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/${TASK_NAME}_start.png

echo "=== Setup complete ==="