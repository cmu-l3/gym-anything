#!/bin/bash
echo "=== Setting up fix_steganography_tool ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_steganography_tool"
PROJECT_DIR="/home/ga/PycharmProjects/stego_toolkit"

# Clean up previous runs
rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_start_ts /tmp/${TASK_NAME}_result.json

# Create project structure
mkdir -p "$PROJECT_DIR/stego_toolkit"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"

# Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
numpy
Pillow
pytest
EOF

# Create utils.py (Helper functions - correct)
cat > "$PROJECT_DIR/stego_toolkit/utils.py" << 'EOF'
from PIL import Image
import numpy as np

def load_image(path):
    """Load image and return as numpy array."""
    img = Image.open(path).convert('RGB')
    return np.array(img)

def save_image(array, path):
    """Save numpy array as image."""
    img = Image.fromarray(array.astype('uint8'), 'RGB')
    img.save(path)
EOF

# Create lsb.py (The buggy file)
cat > "$PROJECT_DIR/stego_toolkit/lsb.py" << 'EOF'
import numpy as np

def to_binary(message):
    """Convert string to binary string representation."""
    binary = ''.join(format(ord(c), '08b') for c in message)
    return binary + '00000000'  # Null terminator

def from_binary(binary_str):
    """Convert binary string back to text."""
    chars = []
    for i in range(0, len(binary_str), 8):
        byte = binary_str[i:i+8]
        if len(byte) < 8:
            break
        
        # BUG 2: Incorrect base conversion
        # Using base 10 interprets "01100001" as decimal 1,100,001 instead of 97 ('a')
        try:
            char_code = int(byte, 10)
            chars.append(chr(char_code))
        except ValueError:
            pass
            
    return ''.join(chars)

def encode_message(image_array, message):
    """
    Embed message into image_array using LSB.
    Returns a new image array with the message embedded.
    """
    binary_message = to_binary(message)
    flat_image = image_array.flatten()
    
    if len(binary_message) > len(flat_image):
        raise ValueError("Message too long for this image")
    
    encoded_flat = flat_image.copy()
    
    for i, bit in enumerate(binary_message):
        val = encoded_flat[i]
        b = int(bit)
        
        # BUG 1: Destructive masking
        # This clears all bits except LSB, turning the image black/dark.
        # Should be: (val & 0xFE) | b
        val = (val & 0x00) | b
        
        encoded_flat[i] = val
        
    return encoded_flat.reshape(image_array.shape)

def decode_message(image_array):
    """
    Extract message from image_array LSBs.
    """
    flat_image = image_array.flatten()
    binary_bits = []
    
    for val in flat_image:
        # Extract LSB
        bit = val & 1
        binary_bits.append(str(bit))
        
        # BUG 3: Missing terminator check
        # The loop should check if the last 8 collected bits are '00000000'
        # and break if so. Without this, it reads the whole image.
    
    return from_binary(''.join(binary_bits))
EOF

# Create stego_toolkit/__init__.py
touch "$PROJECT_DIR/stego_toolkit/__init__.py"

# Create tests
cat > "$PROJECT_DIR/tests/test_lsb.py" << 'EOF'
import pytest
import numpy as np
from stego_toolkit.lsb import encode_message, decode_message

@pytest.fixture
def clean_image():
    # Create a 50x50 gray image
    return np.full((50, 50, 3), 128, dtype=np.uint8)

def test_image_fidelity(clean_image):
    """Test that encoding does not visibly destroy the image."""
    msg = "Secret"
    encoded = encode_message(clean_image, msg)
    
    # Calculate Mean Squared Error
    mse = np.mean((clean_image - encoded) ** 2)
    
    # If LSB only is changed, max change per pixel is 1.
    # MSE should be very small (< 1.0). 
    # Buggy implementation clears top bits, resulting in huge MSE (~16000).
    assert mse < 0.5, f"Image visual quality destroyed! MSE: {mse}"

def test_round_trip(clean_image):
    """Test that a message can be encoded and decoded back."""
    msg = "Hello World"
    encoded = encode_message(clean_image, msg)
    decoded = decode_message(encoded)
    
    assert msg in decoded, "Original message not found in decoded output"

def test_terminator(clean_image):
    """Test that decoding stops at the null terminator."""
    msg = "StopHere"
    encoded = encode_message(clean_image, msg)
    decoded = decode_message(encoded)
    
    # The decoder shouldn't return thousands of junk characters
    # A 50x50x3 image has 7500 pixels. "StopHere" is ~72 bits.
    assert len(decoded) < 20, f"Decoder returned too much garbage: {len(decoded)} chars"
    assert decoded == msg
EOF

# Create a sample image (using python to generate a gradient image)
python3 -c "
from PIL import Image
import numpy as np
w, h = 100, 100
arr = np.zeros((h, w, 3), dtype=np.uint8)
for y in range(h):
    for x in range(w):
        arr[y, x] = [x * 255 // w, y * 255 // h, (x+y) * 255 // (w+h)]
img = Image.fromarray(arr, 'RGB')
img.save('$PROJECT_DIR/data/cover_image.png')
"

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Setup PyCharm
echo "Setting up PyCharm project..."
setup_pycharm_project "$PROJECT_DIR" "stego_toolkit"

# Run tests once to show they fail (creates cache)
# su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/" || true

echo "=== Task setup complete ==="