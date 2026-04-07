#!/bin/bash
set -e

echo "=== Setting up MARC21 Parser Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/marc_parser"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/output"
sudo mkdir -p "/var/lib/app/ground_truth"

# 1. Generate realistic binary MARC21 data and ground truth
echo "Generating binary MARC21 dataset..."
python3 << 'PYDATA'
import json
import os

records = []
binary_data = bytearray()

for i in range(100):
    # Leader pos 9: 'a' means UTF-8, ' ' means MARC-8 (we'll treat as ascii)
    leader_9 = 'a' if i % 2 == 0 else ' '
    
    id_field = f"{i:05d}".encode('ascii')
    
    if leader_9 == 'a':
        title = "Les Misérables"
        title_bytes = b"\x1fa" + title.encode('utf-8')
    else:
        title = "The Hobbit"
        title_bytes = b"\x1fa" + title.encode('ascii')
        
    sub1_bytes = b"\x1faFiction\x1fxHistory"
    sub2_bytes = b"\x1faLiterature"
    
    fields = [
        ("001", id_field),
        ("245", title_bytes),
        ("650", sub1_bytes),
        ("650", sub2_bytes)
    ]
    
    var_data = bytearray()
    directory = bytearray()
    offset = 0
    for tag, val in fields:
        field_data = val + b"\x1e"
        length = len(field_data)
        directory += tag.encode('ascii') + f"{length:04d}".encode('ascii') + f"{offset:05d}".encode('ascii')
        var_data += field_data
        offset += length
        
    directory += b"\x1e"
    base_address = 24 + len(directory)
    record_length = base_address + len(var_data) + 1
    leader = f"{record_length:05d}nam {leader_9}22{base_address:05d}4500".encode('ascii')
    
    record_bytes = leader + directory + var_data + b"\x1d"
    binary_data.extend(record_bytes)
    
    # Ground truth json (expected structure when perfectly parsed)
    record_dict = {
        "leader": leader.decode('ascii'),
        "001": f"{i:05d}",
        "245": ["a" + title],
        "650": ["aFictionxHistory", "aLiterature"]
    }
    records.append(record_dict)

# Write binary test file
with open("/home/ga/workspace/marc_parser/data/loc_sample.mrc", "wb") as f:
    f.write(binary_data)

# Write hidden ground truth
with open("/var/lib/app/ground_truth/expected_catalog.json", "w") as f:
    json.dump(records, f)

PYDATA
chown ga:ga "$WORKSPACE_DIR/data/loc_sample.mrc"
chmod 700 /var/lib/app/ground_truth

# 2. Write the buggy parser.py
cat > "$WORKSPACE_DIR/parser.py" << 'EOF'
import json

def parse_marc(file_path):
    records = []
    with open(file_path, 'rb') as f:
        data = f.read()

    idx = 0
    while idx < len(data):
        record_end = data.find(b'\x1d', idx)
        if record_end == -1:
            break

        record_data = data[idx:record_end+1]
        idx = record_end + 1

        if len(record_data) < 24:
            continue

        leader = record_data[:24].decode('ascii', errors='ignore')
        base_address = int(leader[12:17])

        dir_data = record_data[24:base_address-1]
        var_data = record_data[base_address:-1]

        record_dict = {"leader": leader}
        fields = []

        i = 0
        while i < len(dir_data):
            if len(dir_data) - i < 12:
                break
            tag = dir_data[i:i+3].decode('ascii', errors='ignore')
            
            # BUG 1: Slicing lengths incorrectly (MARC dir entries are 12 bytes: 3 tag, 4 length, 5 offset)
            try:
                field_length = int(dir_data[i+3:i+6])
                start_char = int(dir_data[i+6:i+11])
            except ValueError:
                i += 12
                continue
                
            fields.append((tag, field_length, start_char))
            i += 12

        for tag, length, start in fields:
            raw_field = var_data[start:start+length-1]

            if tag.startswith('00'):
                value = raw_field.decode('ascii', errors='ignore')
            else:
                # BUG 2: Hardcoding ascii instead of checking Leader position 9 ('a' = utf-8)
                text = raw_field.decode('ascii', errors='ignore')

                # BUG 3: Splitting by '^' instead of standard ASCII Unit Separator (\x1f)
                subfields = text.split('^')
                value = [sf for sf in subfields if sf]

            # BUG 4: Overwriting repeatable fields (e.g., 650 Subject) instead of making a list
            record_dict[tag] = value

        records.append(record_dict)

    return records
EOF

# 3. Write test file
cat > "$WORKSPACE_DIR/test_parser.py" << 'EOF'
import pytest
from parser import parse_marc

def test_parsed_record_count():
    records = parse_marc('data/loc_sample.mrc')
    assert len(records) == 100, "Should parse exactly 100 records"

def test_fields_extracted():
    records = parse_marc('data/loc_sample.mrc')
    assert "245" in records[0], "Title field 245 missing (check directory parsing)"
    assert "001" in records[0], "Control field 001 missing"

def test_utf8_encoding():
    records = parse_marc('data/loc_sample.mrc')
    # Record 0 has leader[9] == 'a' (UTF-8) and contains 'Les Misérables'
    title = records[0]["245"][0]
    assert "Misérables" in title, "UTF-8 characters not decoded correctly"

def test_subfield_parsing():
    records = parse_marc('data/loc_sample.mrc')
    subject = records[0]["650"]
    if isinstance(subject, list) and len(subject) > 0:
        assert "^" not in subject[0], "Subfields not split correctly"
        assert "\x1f" not in subject[0], "Unit separator not removed"

def test_repeatable_fields():
    records = parse_marc('data/loc_sample.mrc')
    assert isinstance(records[0]["650"], list), "Repeatable field 650 should be a list"
    assert len(records[0]["650"]) >= 2, "Data loss: secondary 650 field overwrote the first"
EOF

# 4. Write run script
cat > "$WORKSPACE_DIR/run_conversion.py" << 'EOF'
import json
from parser import parse_marc

if __name__ == "__main__":
    print("Parsing LOC MARC21 sample data...")
    records = parse_marc('data/loc_sample.mrc')
    print(f"Parsed {len(records)} records.")
    
    with open('output/parsed_catalog.json', 'w') as f:
        json.dump(records, f, indent=2, ensure_ascii=False)
    print("Saved to output/parsed_catalog.json")
EOF

# Fix permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Launch VS Code
echo "Launching VS Code..."
sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR" &
sleep 5

# Maximize and Focus VS Code
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="