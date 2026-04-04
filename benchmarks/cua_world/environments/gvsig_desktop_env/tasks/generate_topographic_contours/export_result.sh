#!/bin/bash
echo "=== Exporting generate_topographic_contours result ==="

source /workspace/scripts/task_utils.sh

OUTPUT_SHP="/home/ga/gvsig_data/exports/helsinki_contours.shp"
OUTPUT_DBF="/home/ga/gvsig_data/exports/helsinki_contours.dbf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Analyze Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
FEATURE_COUNT=0
INTERVAL_CHECK="fail"
ELEVATION_VALUES="[]"

if [ -f "$OUTPUT_SHP" ] && [ -f "$OUTPUT_DBF" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_SHP" 2>/dev/null || echo "0")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_SHP" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Python script to analyze shapefile content (running inside container)
    # We use basic python struct unpacking for DBF if pyshp/gdal is not available, 
    # but we'll try a robust heuristic approach.
    
    echo "Analyzing shapefile content..."
    python3 -c "
import sys
import struct
import os

dbf_path = '$OUTPUT_DBF'
try:
    with open(dbf_path, 'rb') as f:
        # Read DBF Header
        header = f.read(32)
        if len(header) < 32: raise Exception('Invalid DBF header')
        
        num_records = struct.unpack('<I', header[4:8])[0]
        header_len = struct.unpack('<H', header[8:10])[0]
        record_len = struct.unpack('<H', header[10:12])[0]
        
        # Read Field Descriptors
        f.seek(32)
        fields = []
        while f.tell() < header_len - 1:
            field_data = f.read(32)
            if len(field_data) < 32: break
            if field_data[0] == 0x0D: break # Terminator
            name = field_data[:11].replace(b'\x00', b'').decode('latin1', 'ignore').strip()
            typ = chr(field_data[11])
            length = field_data[16]
            fields.append({'name': name, 'type': typ, 'len': length})

        # Identify Elevation Field (look for 'ELEV', 'CONTOUR', 'LEVEL', 'HEIGHT', 'ID')
        # gvSIG often names it 'ELEV' or 'ID'
        elev_idx = -1
        elev_field = None
        for i, fld in enumerate(fields):
            if any(x in fld['name'].upper() for x in ['ELEV', 'CONTOUR', 'Z', 'LEVEL', 'VAL']):
                elev_idx = i
                elev_field = fld
                break
        
        # If no obvious name, try the first numeric field
        if elev_idx == -1:
            for i, fld in enumerate(fields):
                if fld['type'] in ['N', 'F', 'I', 'O']:
                    elev_idx = i
                    elev_field = fld
                    break

        print(f'FEATURE_COUNT={num_records}')
        
        if elev_idx != -1 and num_records > 0:
            # Read records to check interval
            # Skip to records
            f.seek(header_len)
            values = []
            
            # Read first 50 records to sample
            sample_count = min(num_records, 50)
            
            valid_interval_count = 0
            
            for _ in range(sample_count):
                rec_data = f.read(record_len)
                if len(rec_data) < record_len: break
                
                # Extract field value
                # Calculate offset
                offset = 1 # Delete flag
                for i in range(elev_idx):
                    offset += fields[i]['len']
                
                raw_val = rec_data[offset : offset + elev_field['len']].decode('latin1', 'ignore').strip()
                try:
                    val = float(raw_val)
                    values.append(val)
                    if abs(val % 5.0) < 0.01:
                        valid_interval_count += 1
                except:
                    pass
            
            print(f'SAMPLED_VALUES={values}')
            if len(values) > 0 and (valid_interval_count / len(values)) > 0.8:
                print('INTERVAL_CHECK=pass')
            else:
                print('INTERVAL_CHECK=fail')
        else:
            print('INTERVAL_CHECK=fail_no_field')
            print('SAMPLED_VALUES=[]')

except Exception as e:
    print(f'ERROR: {str(e)}')
    print('FEATURE_COUNT=0')
    print('INTERVAL_CHECK=error')
    " > /tmp/shp_analysis.txt

    # Parse analysis results
    if grep -q "FEATURE_COUNT=" /tmp/shp_analysis.txt; then
        FEATURE_COUNT=$(grep "FEATURE_COUNT=" /tmp/shp_analysis.txt | cut -d= -f2)
    fi
    if grep -q "INTERVAL_CHECK=pass" /tmp/shp_analysis.txt; then
        INTERVAL_CHECK="pass"
    fi
    if grep -q "SAMPLED_VALUES=" /tmp/shp_analysis.txt; then
        ELEVATION_VALUES=$(grep "SAMPLED_VALUES=" /tmp/shp_analysis.txt | cut -d= -f2)
    fi
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "feature_count": ${FEATURE_COUNT:-0},
    "interval_check": "$INTERVAL_CHECK",
    "sampled_values": "$ELEVATION_VALUES",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 4. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="