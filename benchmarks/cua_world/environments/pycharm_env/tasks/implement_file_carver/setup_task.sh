#!/bin/bash
echo "=== Setting up implement_file_carver ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="implement_file_carver"
PROJECT_DIR="/home/ga/PycharmProjects/file_carver"
DATA_DIR="$PROJECT_DIR/data"
SRC_DIR="$PROJECT_DIR/forensics"
TEST_DIR="$PROJECT_DIR/tests"
RECOVERED_DIR="$PROJECT_DIR/recovered_files"

# Clean previous state
rm -rf "$PROJECT_DIR"
rm -f /tmp/${TASK_NAME}_result.json /tmp/${TASK_NAME}_start_ts

# Create directories
su - ga -c "mkdir -p $DATA_DIR $SRC_DIR $TEST_DIR $RECOVERED_DIR"

# Generate Project Files

# 1. requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
pytest>=7.0
EOF

# 2. forensics/__init__.py
touch "$PROJECT_DIR/forensics/__init__.py"

# 3. forensics/signatures.py (Helper constants)
cat > "$PROJECT_DIR/forensics/signatures.py" << 'EOF'
"""
File signatures (Magic Numbers) for common image formats.
"""

# JPEG: Starts with FF D8, ends with FF D9
JPEG_SOI = b'\xFF\xD8'
JPEG_EOI = b'\xFF\xD9'

# PNG: Starts with 89 50 4E 47 0D 0A 1A 0A, ends with IEND chunk (less trivial, but roughly ends with footer)
# For this simplified task, we look for the PNG signature and the IEND chunk footer.
# PNG Footer is: 00 00 00 00 49 45 4E 44 AE 42 60 82
# But often carvers just look for 49 45 4E 44 AE 42 60 82 (IEND + CRC)
PNG_SOI = b'\x89\x50\x4E\x47\x0D\x0A\x1A\x0A'
PNG_EOI = b'\x49\x45\x4E\x44\xAE\x42\x60\x82'
EOF

# 4. forensics/carver.py (Skeleton)
cat > "$PROJECT_DIR/forensics/carver.py" << 'EOF'
import os
from typing import List, Tuple
from forensics.signatures import JPEG_SOI, JPEG_EOI, PNG_SOI, PNG_EOI

class FileCarver:
    def __init__(self):
        self.signatures = [
            ('jpg', JPEG_SOI, JPEG_EOI),
            ('png', PNG_SOI, PNG_EOI)
        ]

    def find_files(self, data: bytes) -> List[Tuple[str, bytes]]:
        """
        Scan byte data for file signatures and return a list of found files.

        Args:
            data: Raw byte data from the drive dump.

        Returns:
            List of tuples: (extension, file_bytes)
            e.g. [('jpg', b'...'), ('png', b'...')]
        """
        found_files = []
        
        # TODO: Implement file carving logic here.
        # 1. Iterate through the data to find Start of Image (SOI) markers.
        # 2. When a SOI is found, look ahead for the corresponding End of Image (EOI) marker.
        # 3. Extract the bytes between SOI and EOI (inclusive).
        # 4. Append ('jpg' or 'png', extracted_bytes) to found_files.
        #
        # Note: Be careful with overlapping signatures or false positives. 
        # For this task, assume files are not fragmented.
        
        raise NotImplementedError("Carving logic not implemented")

    def carve_file(self, input_path: str, output_dir: str):
        """
        Read binary file, extract images, and save them to output_dir.
        """
        print(f"Processing {input_path}...")
        
        try:
            with open(input_path, 'rb') as f:
                data = f.read()
        except FileNotFoundError:
            print(f"Error: Input file {input_path} not found.")
            return

        recovered = self.find_files(data)
        
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
            
        print(f"Found {len(recovered)} files.")
        
        for i, (ext, content) in enumerate(recovered):
            filename = f"recovered_{i+1}.{ext}"
            out_path = os.path.join(output_dir, filename)
            with open(out_path, 'wb') as f:
                f.write(content)
            print(f"Saved {filename}")

if __name__ == '__main__':
    # Example usage
    carver = FileCarver()
    # Adjust paths as needed for testing
    carver.carve_file('../data/evidence.bin', '../recovered_files')
EOF

# 5. tests/test_carver.py
cat > "$PROJECT_DIR/tests/test_carver.py" << 'EOF'
import pytest
from forensics.carver import FileCarver
from forensics.signatures import JPEG_SOI, JPEG_EOI, PNG_SOI, PNG_EOI

@pytest.fixture
def carver():
    return FileCarver()

def test_find_single_jpg(carver):
    # Construct a fake JPG: SOI + some data + EOI
    content = b"fake_image_data"
    fake_jpg = JPEG_SOI + content + JPEG_EOI
    data = b"junk_data" + fake_jpg + b"more_junk"
    
    results = carver.find_files(data)
    assert len(results) == 1
    assert results[0][0] == 'jpg'
    assert results[0][1] == fake_jpg

def test_find_single_png(carver):
    content = b"fake_png_data"
    fake_png = PNG_SOI + content + PNG_EOI
    data = b"noise" * 10 + fake_png + b"noise"
    
    results = carver.find_files(data)
    assert len(results) == 1
    assert results[0][0] == 'png'
    assert results[0][1] == fake_png

def test_multiple_files(carver):
    jpg = JPEG_SOI + b"pic1" + JPEG_EOI
    png = PNG_SOI + b"pic2" + PNG_EOI
    data = b"garbage" + jpg + b"padding" + png + b"garbage"
    
    results = carver.find_files(data)
    assert len(results) == 2
    assert results[0][1] == jpg
    assert results[1][1] == png

def test_no_files(carver):
    data = b"just random junk data with no headers"
    results = carver.find_files(data)
    assert len(results) == 0

def test_incomplete_file(carver):
    # SOI but no EOI
    data = b"junk" + JPEG_SOI + b"incomplete_data"
    results = carver.find_files(data)
    assert len(results) == 0
EOF

# 6. Generate Real Data (evidence.bin) using Python
# We create valid small images so hashes are stable
echo "Generating evidence.bin..."
cat > /tmp/gen_data.py << 'PYEOF'
import os
import zlib
import struct

def create_png(width, height, color):
    # Minimal PNG generator
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))
    
    # Signature
    png = b'\x89PNG\r\n\x1a\n'
    # IHDR
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png += chunk(b'IHDR', ihdr)
    # IDAT (solid color)
    # Scanlines: (1 byte filter type 0) + (width * 3 bytes RGB)
    raw_data = b""
    for _ in range(height):
        raw_data += b'\x00' + (bytes(color) * width)
    png += chunk(b'IDAT', zlib.compress(raw_data))
    # IEND
    png += chunk(b'IEND', b'')
    return png

def create_jpg(content_marker):
    # Fake JPG structure for simplicity of generation, 
    # OR we just use the signatures with dummy content since the carver just needs signatures.
    # However, task description says "hidden evidence" implies "intact files". 
    # The verifier checks exact bytes. 
    # Let's create blobs that ARE valid signatures wrapping unique content.
    # The task doesn't require viewing them, just recovering bytes.
    # BUT to be realistic, the carver is usually "byte signature" based.
    # We will use the defined signatures in signatures.py + unique content.
    
    # Signatures from signatures.py
    JPEG_SOI = b'\xFF\xD8'
    JPEG_EOI = b'\xFF\xD9'
    return JPEG_SOI + content_marker + JPEG_EOI

# Create 4 "files"
# 2 valid PNGs (actually parsable structure)
img1_png = create_png(10, 10, (255, 0, 0)) # Red
img2_png = create_png(10, 10, (0, 255, 0)) # Green

# 2 "JPEGs" (just header/footer wrappers for this exercise, since encoding real JPEG in pure python is hard without PIL)
# Note: The verifier checks exact byte match, so this is fine.
img3_jpg = create_jpg(b"Evidence_Photo_A_Secret_Meeting")
img4_jpg = create_jpg(b"Evidence_Photo_B_Stolen_Goods")

# Add some randomness
import random
noise1 = os.urandom(512)
noise2 = os.urandom(1024)
noise3 = os.urandom(256)
tail = os.urandom(128)

# Construct evidence
evidence = noise1 + img3_jpg + noise2 + img1_png + noise3 + img4_jpg + img2_png + tail

# Write evidence
with open('/home/ga/PycharmProjects/file_carver/data/evidence.bin', 'wb') as f:
    f.write(evidence)

# Write ground truth hashes (hidden)
import hashlib
import json

hashes = {
    "jpg_1": hashlib.sha256(img3_jpg).hexdigest(),
    "jpg_2": hashlib.sha256(img4_jpg).hexdigest(),
    "png_1": hashlib.sha256(img1_png).hexdigest(),
    "png_2": hashlib.sha256(img2_png).hexdigest(),
    "file_sizes": {
        "jpg_1": len(img3_jpg),
        "jpg_2": len(img4_jpg),
        "png_1": len(img1_png),
        "png_2": len(img2_png)
    }
}

with open('/home/ga/.ground_truth_hashes.json', 'w') as f:
    json.dump(hashes, f)

print("Evidence generated.")
PYEOF

python3 /tmp/gen_data.py

# Fix permissions
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/${TASK_NAME}_start_ts

# Setup PyCharm
setup_pycharm_project "$PROJECT_DIR" "file_carver"

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="