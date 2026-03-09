#!/bin/bash
echo "=== Setting up Extract Volume Properties task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
SAMPLE_DIR=$(get_sample_data_dir)
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

mkdir -p "$EXPORT_DIR"
mkdir -p "$GROUND_TRUTH_DIR"
chown -R ga:ga "$EXPORT_DIR" 2>/dev/null || true
chown -R ga:ga "/home/ga/Documents/SlicerData" 2>/dev/null || true

# Ensure sample data exists
SAMPLE_FILE="$SAMPLE_DIR/MRHead.nrrd"

if [ ! -f "$SAMPLE_FILE" ]; then
    echo "Downloading MRHead sample data..."
    mkdir -p "$SAMPLE_DIR"
    
    # Try primary URL
    curl -L -o "$SAMPLE_FILE" --connect-timeout 30 --max-time 120 \
        "https://github.com/Slicer/SlicerTestingData/releases/download/SHA256/cc211f0dfd9a05ca3841ce1141b292898b2dd2d3f08286c4b0c71defe6e4f5f8" 2>/dev/null
    
    # Verify download
    if [ ! -f "$SAMPLE_FILE" ] || [ $(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0) -lt 1000000 ]; then
        echo "Primary download failed, trying alternative URL..."
        wget -O "$SAMPLE_FILE" --timeout=120 \
            "https://data.kitware.com/api/v1/file/5c4d2eac8d777f072bf6cdba/download" 2>/dev/null || true
    fi
    
    chown ga:ga "$SAMPLE_FILE" 2>/dev/null || true
fi

# Verify sample file exists
if [ ! -f "$SAMPLE_FILE" ]; then
    echo "ERROR: Could not obtain sample file at $SAMPLE_FILE"
    exit 1
fi

SAMPLE_SIZE=$(stat -c%s "$SAMPLE_FILE" 2>/dev/null || echo 0)
echo "Sample file: $SAMPLE_FILE ($SAMPLE_SIZE bytes)"

# Remove any previous output to ensure clean state
rm -f "$EXPORT_DIR/volume_properties.json" 2>/dev/null || true
rm -f /tmp/volume_properties_task_result.json 2>/dev/null || true

# Extract ground truth volume properties from the NRRD file
echo "Extracting ground truth volume properties..."
python3 << 'PYEOF'
import os
import sys
import json

sample_file = "/home/ga/Documents/SlicerData/SampleData/MRHead.nrrd"
gt_path = "/var/lib/slicer/ground_truth/mrhead_properties.json"

# Parse NRRD header to get properties
def parse_nrrd_header(filepath):
    """Parse NRRD header without requiring nrrd library."""
    properties = {
        "volume_name": "MRHead",
        "dimensions": [0, 0, 0],
        "spacing_mm": [1.0, 1.0, 1.0],
        "scalar_type": "unknown",
        "num_components": 1
    }
    
    # Type mapping
    type_map = {
        'int8': 'char',
        'uint8': 'unsigned char',
        'int16': 'short',
        'uint16': 'unsigned short',
        'int32': 'int',
        'uint32': 'unsigned int',
        'int64': 'long',
        'uint64': 'unsigned long',
        'float32': 'float',
        'float64': 'double',
        'float': 'float',
        'double': 'double',
        'short': 'short',
        'ushort': 'unsigned short',
        'int': 'int',
        'uint': 'unsigned int',
        'uchar': 'unsigned char',
        'signed char': 'char',
        'unsigned char': 'unsigned char',
        'signed short': 'short',
        'unsigned short': 'unsigned short',
    }
    
    try:
        with open(filepath, 'rb') as f:
            # Read header (until empty line or data)
            header_lines = []
            while True:
                line = f.readline()
                if not line:
                    break
                try:
                    line_str = line.decode('ascii').strip()
                except:
                    break
                if not line_str:
                    break
                header_lines.append(line_str)
            
            for line in header_lines:
                if ':' not in line:
                    continue
                key, value = line.split(':', 1)
                key = key.strip().lower()
                value = value.strip()
                
                if key == 'sizes':
                    parts = value.split()
                    if len(parts) >= 3:
                        properties["dimensions"] = [int(p) for p in parts[:3]]
                
                elif key == 'spacings' or key == 'space directions':
                    if key == 'spacings':
                        parts = value.split()
                        if len(parts) >= 3:
                            properties["spacing_mm"] = [float(p) for p in parts[:3]]
                    else:
                        # Parse space directions like: (1,0,0) (0,1,0) (0,0,1.3)
                        import re
                        vectors = re.findall(r'\(([^)]+)\)', value)
                        if len(vectors) >= 3:
                            spacings = []
                            for v in vectors[:3]:
                                components = [float(x) for x in v.split(',')]
                                # Spacing is the magnitude of each direction vector
                                magnitude = sum(c**2 for c in components) ** 0.5
                                spacings.append(round(magnitude, 6))
                            if all(s > 0 for s in spacings):
                                properties["spacing_mm"] = spacings
                
                elif key == 'type':
                    value_lower = value.lower()
                    properties["scalar_type"] = type_map.get(value_lower, value_lower)
                
                elif key == 'dimension':
                    # If dimension is 4, first dimension might be components
                    pass
                    
    except Exception as e:
        print(f"Error parsing NRRD: {e}", file=sys.stderr)
    
    return properties

# Get properties
props = parse_nrrd_header(sample_file)

# For MRHead, we know the expected values (standard test dataset)
# Override with known correct values for MRHead.nrrd
# MRHead is typically: 256x256x130, spacing around 1x1x1.3mm, short type
if props["dimensions"] == [0, 0, 0]:
    # Use known MRHead defaults
    props["dimensions"] = [256, 256, 130]
    props["spacing_mm"] = [1.0, 1.0, 1.3]
    props["scalar_type"] = "short"

print(f"Ground truth properties: {json.dumps(props, indent=2)}")

# Save ground truth
os.makedirs(os.path.dirname(gt_path), exist_ok=True)
with open(gt_path, 'w') as f:
    json.dump(props, f, indent=2)

print(f"Ground truth saved to {gt_path}")
PYEOF

# Verify ground truth was created
if [ -f "/var/lib/slicer/ground_truth/mrhead_properties.json" ]; then
    echo "Ground truth properties:"
    cat /var/lib/slicer/ground_truth/mrhead_properties.json
else
    echo "WARNING: Ground truth file not created"
fi

# Set permissions on ground truth (read-only, hidden from agent)
chmod 700 "$GROUND_TRUTH_DIR" 2>/dev/null || true

# Launch 3D Slicer with the sample file pre-loaded
echo "Launching 3D Slicer with MRHead data..."

# Kill any existing Slicer
pkill -f "Slicer" 2>/dev/null || true
sleep 2

# Launch Slicer with the file
su - ga -c "DISPLAY=:1 /opt/Slicer/Slicer '$SAMPLE_FILE' > /tmp/slicer_launch.log 2>&1 &"

# Wait for Slicer to start and load data
echo "Waiting for 3D Slicer to start and load data..."
sleep 10

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "slicer"; then
        echo "3D Slicer window detected"
        break
    fi
    sleep 2
done

# Wait for data to load (check window title for filename)
for i in {1..30}; do
    TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "slicer" | head -1)
    if echo "$TITLE" | grep -qi "MRHead\|nrrd"; then
        echo "Data loaded: $TITLE"
        break
    fi
    sleep 2
done

# Maximize Slicer window
DISPLAY=:1 wmctrl -r "Slicer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Slicer" 2>/dev/null || true
sleep 2

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
fi

echo ""
echo "=== Task Setup Complete ==="
echo ""
echo "TASK: Extract the spatial properties of the loaded MRHead volume"
echo ""
echo "The MRHead volume is already loaded. You need to:"
echo "1. Navigate to the Volumes module"
echo "2. View the Volume Information section"
echo "3. Record the properties to: $EXPORT_DIR/volume_properties.json"
echo ""
echo "Expected output format:"
echo '{'
echo '  "volume_name": "MRHead",'
echo '  "dimensions": [X, Y, Z],'
echo '  "spacing_mm": [X.XX, Y.YY, Z.ZZ],'
echo '  "scalar_type": "type_name",'
echo '  "num_components": N'
echo '}'