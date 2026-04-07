#!/bin/bash
echo "=== Exporting africa_development_atlas_page result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run the entire analysis in a single Python script to avoid shell/Python type mismatches
python3 << 'PYEOF'
import json
import os
import struct
import subprocess

# ----------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------
IMAGE_PATH = "/home/ga/gvsig_data/exports/africa_dev_index.png"
DBF_PATH = "/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.dbf"
TASK_START_FILE = "/tmp/task_start_time.txt"

# ----------------------------------------------------------------
# 1. Read timestamps
# ----------------------------------------------------------------
try:
    with open(TASK_START_FILE, 'r') as f:
        task_start = int(f.read().strip())
except:
    task_start = 0
task_end = int(subprocess.check_output(["date", "+%s"]).strip())

# ----------------------------------------------------------------
# 2. Analyze PNG output
# ----------------------------------------------------------------
img_exists = os.path.exists(IMAGE_PATH)
img_created_during = False
img_size = 0
img_width = 0
img_height = 0
is_valid = False

if img_exists:
    img_size = os.path.getsize(IMAGE_PATH)
    img_mtime = int(os.path.getmtime(IMAGE_PATH))
    img_created_during = img_mtime > task_start

    # Get dimensions via ImageMagick identify
    try:
        out = subprocess.check_output(
            ["identify", "-format", "%w %h", IMAGE_PATH],
            stderr=subprocess.DEVNULL
        ).decode().strip()
        parts = out.split()
        img_width = int(parts[0])
        img_height = int(parts[1])
        is_valid = True
    except:
        pass

    # Copy for verifier access
    try:
        import shutil
        shutil.copy2(IMAGE_PATH, "/tmp/exported_map.png")
        os.chmod("/tmp/exported_map.png", 0o666)
    except:
        pass

# ----------------------------------------------------------------
# 3. Check if DBF was modified
# ----------------------------------------------------------------
dbf_modified = False
if os.path.exists(DBF_PATH):
    dbf_mtime = int(os.path.getmtime(DBF_PATH))
    dbf_modified = dbf_mtime > task_start

# ----------------------------------------------------------------
# 4. Parse DBF for DEV_IDX field and spot-check values
# ----------------------------------------------------------------
def parse_dbf(filepath):
    if not os.path.exists(filepath):
        return {"error": "DBF file not found"}
    try:
        with open(filepath, 'rb') as f:
            header_data = f.read(32)
            num_records = struct.unpack('<I', header_data[4:8])[0]
            header_len = struct.unpack('<H', header_data[8:10])[0]
            record_len = struct.unpack('<H', header_data[10:12])[0]

            fields = []
            f.seek(32)
            while True:
                field_data = f.read(32)
                if len(field_data) != 32 or field_data[0] == 0x0D:
                    break
                name = field_data[:11].split(b'\x00')[0].decode('latin1').strip()
                field_type = chr(field_data[11])
                length = field_data[16]
                fields.append({"name": name, "type": field_type, "length": length})

            field_names = [ff["name"] for ff in fields]
            field_map = {ff["name"].upper(): i for i, ff in enumerate(fields)}

            # Find DEV_IDX field
            target_idx = -1
            target_name = None
            for candidate in ["DEV_IDX", "GDP_PCAP", "DEVIDX", "DEV_ID"]:
                if candidate in field_map:
                    target_idx = field_map[candidate]
                    target_name = fields[target_idx]["name"]
                    break

            gdp_idx = field_map.get("GDP_MD", -1)
            pop_idx = field_map.get("POP_EST", -1)
            name_idx = field_map.get("NAME", -1)

            f.seek(header_len)
            spot_check = {}
            spot_countries = ["Nigeria", "South Africa", "Egypt", "Kenya", "Ethiopia"]

            for _ in range(num_records):
                record_data = f.read(record_len)
                if len(record_data) != record_len:
                    break
                if record_data[0] == 0x2A:
                    continue

                def get_val(idx):
                    if idx == -1:
                        return None
                    offset = 1
                    for k in range(idx):
                        offset += fields[k]["length"]
                    raw = record_data[offset:offset + fields[idx]["length"]]
                    val_str = raw.split(b'\x00')[0].decode('latin1').strip()
                    if not val_str:
                        return None
                    if fields[idx]["type"] in ['N', 'F']:
                        try:
                            return float(val_str)
                        except:
                            return None
                    return val_str

                name_val = get_val(name_idx)
                if name_val in spot_countries:
                    entry = {"gdp_md": get_val(gdp_idx), "pop_est": get_val(pop_idx)}
                    if target_idx != -1:
                        entry["dev_idx"] = get_val(target_idx)
                    spot_check[name_val] = entry

            return {
                "field_names": field_names,
                "target_field_found": target_idx != -1,
                "target_field_name": target_name,
                "record_count": num_records,
                "spot_check": spot_check
            }
    except Exception as e:
        return {"error": str(e)}

dbf_analysis = parse_dbf(DBF_PATH)

# ----------------------------------------------------------------
# 5. Build and write result JSON
# ----------------------------------------------------------------
result = {
    "task_start": task_start,
    "task_end": task_end,
    "image_exists": img_exists,
    "image_path": IMAGE_PATH,
    "image_size_bytes": img_size,
    "image_created_during_task": img_created_during,
    "is_valid_image": is_valid,
    "image_width": img_width,
    "image_height": img_height,
    "dbf_modified": dbf_modified,
    "dbf_analysis": dbf_analysis,
    "screenshot_path": "/tmp/task_final.png"
}

output = json.dumps(result, indent=2)

# Write to temp file first, then move
import tempfile
tmp_fd, tmp_path = tempfile.mkstemp(suffix='.json', prefix='result_atlas_', dir='/tmp')
with os.fdopen(tmp_fd, 'w') as f:
    f.write(output)

# Move to standard location
try:
    os.remove("/tmp/task_result.json")
except:
    pass
os.rename(tmp_path, "/tmp/task_result.json")
try:
    os.chmod("/tmp/task_result.json", 0o666)
except:
    pass

print(output)
PYEOF

echo "Result JSON created at /tmp/task_result.json"
echo "=== Export complete ==="
