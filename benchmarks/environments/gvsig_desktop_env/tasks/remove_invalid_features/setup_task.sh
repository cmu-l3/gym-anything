#!/bin/bash
set -e
echo "=== Setting up remove_invalid_features task ==="

source /workspace/scripts/task_utils.sh

# Install pyshp for data manipulation (if not already present)
if ! python3 -c "import shapefile" 2>/dev/null; then
    echo "Installing pyshp..."
    pip3 install --no-cache-dir pyshp
fi

# Prepare directories
DATA_DIR="/home/ga/gvsig_data/projects"
mkdir -p "$DATA_DIR"
SOURCE_SHP="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.shp"
TARGET_SHP="$DATA_DIR/countries_cleaning.shp"

# Verify source exists
if [ ! -f "$SOURCE_SHP" ]; then
    echo "ERROR: Source shapefile not found at $SOURCE_SHP"
    exit 1
fi

# Generate the "dirty" dataset using Python
echo "Generating dataset with invalid records..."
python3 << EOF
import shapefile
import random
import shutil
import os
import sys

# Paths
src = "$SOURCE_SHP"
dst = "$TARGET_SHP"
dst_base = os.path.splitext(dst)[0]

# Copy source to dest (all extensions)
src_base = os.path.splitext(src)[0]
for ext in ['.shp', '.shx', '.dbf', '.prj', '.cpg']:
    if os.path.exists(src_base + ext):
        shutil.copy(src_base + ext, dst_base + ext)

# Open the new file for modification
# We use pyshp to read, modify records, and write back
r = shapefile.Reader(dst)
w = shapefile.Writer(dst)
w.fields = r.fields[1:] # Copy fields (skip deletion flag)

# Find index of POP_EST
try:
    # Field names in pyshp are typically ['NAME', 'Type', Length, Decimals]
    # We look for the first element
    field_names = [f[0] for f in r.fields[1:]]
    pop_idx = next(i for i, name in enumerate(field_names) if name == 'POP_EST')
except StopIteration:
    print("ERROR: POP_EST field not found in shapefile!")
    sys.exit(1)

# Select random indices to corrupt (approx 15 records)
total_records = len(r.records())
indices_to_corrupt = set(random.sample(range(total_records), 15))

corrupted_count = 0
for i, shape in enumerate(r.shapes()):
    rec = r.record(i)
    if i in indices_to_corrupt:
        rec[pop_idx] = -99
        corrupted_count += 1
    w.record(*rec)
    w.shape(shape)

w.close()

# Save metadata for verification
with open('/tmp/initial_stats.json', 'w') as f:
    f.write(f'{{"initial_count": {total_records}, "corrupted_count": {corrupted_count}}}')

print(f"Created {dst} with {total_records} records, {corrupted_count} corrupted (-99).")
EOF

# Set permissions
chown -R ga:ga "$DATA_DIR"
chmod 666 "$DATA_DIR/countries_cleaning"*

# Kill gvSIG
kill_gvsig

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch gvSIG (empty project)
echo "Launching gvSIG..."
launch_gvsig ""

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="