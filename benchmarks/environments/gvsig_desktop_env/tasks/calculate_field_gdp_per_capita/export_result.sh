#!/bin/bash
echo "=== Exporting calculate_field_gdp_per_capita result ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Path to modified data
DBF_FILE="/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.dbf"
BACKUP_FILE="${DBF_FILE}.bak"

# File stats
DBF_MTIME=$(stat -c %Y "$DBF_FILE" 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$DBF_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Run python script to parse DBF and extract relevant data
# We extract GDP_MD_EST, POP_EST, and GDP_PCAP (if it exists)
# This avoids needing complex libraries on the verifier side
python3 << 'EOF' > /tmp/dbf_analysis.json
import struct
import json
import os
import datetime

dbf_path = "/home/ga/gvsig_data/countries/ne_110m_admin_0_countries.dbf"

def parse_dbf(filepath):
    if not os.path.exists(filepath):
        return {"error": "File not found"}
    
    try:
        with open(filepath, 'rb') as f:
            # Read header
            header_data = f.read(32)
            num_records = struct.unpack('<I', header_data[4:8])[0]
            header_len = struct.unpack('<H', header_data[8:10])[0]
            record_len = struct.unpack('<H', header_data[10:12])[0]
            
            # Read field descriptors
            fields = []
            f.seek(32)
            while True:
                field_data = f.read(32)
                if len(field_data) != 32 or field_data[0] == 0x0D:
                    break
                name = field_data[:11].split(b'\x00')[0].decode('latin1').strip()
                field_type = chr(field_data[11])
                length = field_data[16]
                decimal_count = field_data[17]
                fields.append({
                    "name": name, 
                    "type": field_type, 
                    "length": length, 
                    "decimal": decimal_count
                })
            
            # Find indices
            target_field = "GDP_PCAP"
            gdp_field = "GDP_MD_EST"
            pop_field = "POP_EST"
            name_field = "NAME"
            
            # Handle potential truncation or case issues
            field_map = {f["name"].upper(): i for i, f in enumerate(fields)}
            
            # Locate target field (allow partial match if truncated by DBF limits)
            target_idx = -1
            for fname in field_map:
                if fname == target_field or fname.startswith("GDP_PCAP"):
                    target_idx = field_map[fname]
                    target_field = fname # Update to actual name
                    break
            
            gdp_idx = field_map.get(gdp_field, -1)
            pop_idx = field_map.get(pop_field, -1)
            name_idx = field_map.get(name_field, -1)
            
            # Read records
            f.seek(header_len)
            records = []
            
            # Limit to first 100 to save space, or sample
            # We will read all but only store necessary data
            
            for i in range(num_records):
                record_data = f.read(record_len)
                if len(record_data) != record_len:
                    break
                    
                # Skip deleted records
                if record_data[0] == 0x2A: # Asterisk means deleted
                    continue
                
                # Parse specific fields
                def get_val(idx):
                    if idx == -1: return None
                    offset = 1 # Skip deletion flag
                    for k in range(idx):
                        offset += fields[k]["length"]
                    
                    raw = record_data[offset : offset + fields[idx]["length"]]
                    val_str = raw.decode('latin1').strip()
                    
                    if not val_str: return None
                    
                    ftype = fields[idx]["type"]
                    if ftype in ['N', 'F']:
                        try:
                            return float(val_str)
                        except:
                            return 0.0
                    return val_str

                rec = {
                    "name": get_val(name_idx),
                    "gdp_md": get_val(gdp_idx),
                    "pop": get_val(pop_idx),
                    "target": get_val(target_idx) if target_idx != -1 else None
                }
                records.append(rec)
                
            return {
                "fields": [f["name"] for f in fields],
                "target_field_found": (target_idx != -1),
                "target_field_name": target_field,
                "record_count": len(records),
                "data": records
            }
            
    except Exception as e:
        return {"error": str(e)}

result = parse_dbf(dbf_path)
print(json.dumps(result))
EOF

# Combine everything into final result JSON
python3 << EOF > /tmp/task_result.json
import json
import os

try:
    with open('/tmp/dbf_analysis.json', 'r') as f:
        dbf_data = json.load(f)
except:
    dbf_data = {"error": "Failed to load DBF analysis"}

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_modified": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_end.png",
    "dbf_analysis": dbf_data
}

print(json.dumps(result, indent=2))
EOF

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON content:"
head -n 20 /tmp/task_result.json
echo "..."
echo "=== Export complete ==="