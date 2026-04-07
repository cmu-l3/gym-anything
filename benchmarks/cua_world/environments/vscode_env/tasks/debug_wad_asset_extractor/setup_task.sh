#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug WAD Asset Extractor Task ==="

WORKSPACE_DIR="/home/ga/workspace/wad_extractor"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Download a real DOOM1.WAD shareware file for authentic binary testing
echo "Downloading DOOM1.WAD..."
sudo -u ga curl -L -s -o "$WORKSPACE_DIR/DOOM1.WAD" "https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad"

# Ensure download succeeded
if [ ! -s "$WORKSPACE_DIR/DOOM1.WAD" ]; then
    echo "Warning: Download failed, generating a realistic binary-accurate mock DOOM.WAD..."
    sudo -u ga python3 -c "
import struct
with open('$WORKSPACE_DIR/DOOM1.WAD', 'wb') as f:
    f.write(struct.pack('<4sII', b'IWAD', 5, 1164))
    f.write(b'\x01\x02\x03' * 256) # PLAYPAL
    f.write(b'\x00' * 256)         # COLORMAP
    f.write(b'\x80' * 128)         # DSPISTOL
    f.write(struct.pack('<II8s', 12, 768, b'PLAYPAL\x00'))
    f.write(struct.pack('<II8s', 780, 0, b'F_START\x00'))
    f.write(struct.pack('<II8s', 780, 256, b'COLORMAP'))
    f.write(struct.pack('<II8s', 1036, 0, b'F_END\x00\x00\x00'))
    f.write(struct.pack('<II8s', 1036, 128, b'DSPISTOL'))
"
fi

# ─────────────────────────────────────────────────────────────
# Create buggy source files
# ─────────────────────────────────────────────────────────────

# 1. wad_parser.py (BUGS: Endianness, Absolute Seeking, String Decoding)
cat > "$WORKSPACE_DIR/wad_parser.py" << 'PYEOF'
import struct

class WADParser:
    def __init__(self, filepath):
        self.filepath = filepath

    def parse_header(self, f):
        """Parse the 12-byte WAD header."""
        header_data = f.read(12)
        # BUG 1: WADs use Little-Endian for integers. This uses Big-Endian.
        wad_type, num_lumps, info_table_offset = struct.unpack('>4sII', header_data)
        return wad_type.decode('ascii'), num_lumps, info_table_offset

    def read_directory(self, f, num_lumps, info_table_offset):
        """Read the directory (info table) mapping lumps to file offsets."""
        f.seek(info_table_offset)
        lumps = []
        for _ in range(num_lumps):
            data = f.read(16)
            if len(data) < 16:
                break
            
            offset, size, name_bytes = struct.unpack('<II8s', data)
            
            # BUG 3: Assumes all strings have a null byte. 
            # Exactly 8-character names (like 'COLORMAP') will throw ValueError!
            null_idx = name_bytes.index(b'\x00')
            name = name_bytes[:null_idx].decode('ascii')
            
            lumps.append({'offset': offset, 'size': size, 'name': name})
            
        return lumps

    def read_lump_data(self, f, offset, size):
        """Read the raw binary data for a specific lump."""
        # BUG 2: Seek should be absolute (from beginning of file), not relative (1)
        f.seek(offset, 1)
        return f.read(size)
PYEOF

# 2. extractor.py (BUG: Does not skip 0-byte marker lumps)
cat > "$WORKSPACE_DIR/extractor.py" << 'PYEOF'
import os
from wad_parser import WADParser
from playpal_converter import convert_playpal

def extract_wad(wad_path, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    parser = WADParser(wad_path)

    print(f"Opening WAD file: {wad_path}")
    with open(wad_path, 'rb') as f:
        wad_type, num_lumps, info_table_offset = parser.parse_header(f)
        print(f"Type: {wad_type}, Lumps: {num_lumps}, Table Offset: {info_table_offset}")
        
        lumps = parser.read_directory(f, num_lumps, info_table_offset)
        print(f"Successfully read {len(lumps)} directory entries.")

        for i, lump in enumerate(lumps):
            # BUG 4: Marker lumps (e.g. F_START, F_END) have size == 0.
            # Processing them causes downstream file I/O errors or garbage data.
            
            try:
                data = parser.read_lump_data(f, lump['offset'], lump['size'])
            except Exception as e:
                print(f"Error reading lump {lump['name']}: {e}")
                continue

            # Route to specific converters or save as raw
            if lump['name'] == 'PLAYPAL':
                convert_playpal(data, output_dir)
                print(f"Converted PLAYPAL ({lump['size']} bytes)")
            else:
                out_path = os.path.join(output_dir, f"{lump['name']}.dat")
                with open(out_path, 'wb') as out_f:
                    out_f.write(data)
                if i % 500 == 0:
                    print(f"Extracted {i} lumps...")
PYEOF

# 3. playpal_converter.py (BUG: RGB ordering swapped)
cat > "$WORKSPACE_DIR/playpal_converter.py" << 'PYEOF'
import os

def convert_playpal(data, output_dir):
    """
    Parses a WAD PLAYPAL lump. 
    A PLAYPAL contains 14 palettes, each 256 colors. Each color is 3 bytes.
    """
    # For simplicity, we'll just parse the very first palette (768 bytes)
    if len(data) < 768:
        return
        
    palette_data = data[:768]
    colors = []
    
    for i in range(0, 768, 3):
        # BUG 5: WAD colors are stored sequentially as R, G, B.
        # This implementation incorrectly reads them as B, G, R.
        b = palette_data[i]
        g = palette_data[i+1]
        r = palette_data[i+2]
        
        colors.append((r, g, b))

    # Save out as a simple text file for verification 
    # (in a real app this would write a PNG/BMP)
    out_path = os.path.join(output_dir, "PLAYPAL_0.txt")
    with open(out_path, 'w') as out_f:
        out_f.write("R,G,B\n")
        for c in colors:
            out_f.write(f"{c[0]},{c[1]},{c[2]}\n")
PYEOF

# 4. main.py (Entry point)
cat > "$WORKSPACE_DIR/main.py" << 'PYEOF'
import sys
from extractor import extract_wad

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python main.py <wad_file> <output_dir>")
        sys.exit(1)
        
    wad_file = sys.argv[1]
    output_dir = sys.argv[2]
    
    extract_wad(wad_file, output_dir)
    print("Extraction complete.")
PYEOF

# Set ownership
chown -R ga:ga "$WORKSPACE_DIR"

# Launch VS Code pointing to the workspace
if ! pgrep -f "code.*wad_extractor" > /dev/null; then
    echo "Starting VS Code..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Focus and maximize window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="