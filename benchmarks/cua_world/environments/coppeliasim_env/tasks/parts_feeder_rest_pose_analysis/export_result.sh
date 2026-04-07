#!/bin/bash
echo "=== Exporting parts_feeder_rest_pose_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/drop_results.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/rest_pose_stats.json"
SCRIPT="/home/ga/Documents/CoppeliaSim/scripts/run_drop_test.py"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Perform Python analysis of all files to safely extract properties
python3 -c "
import os, json, csv

start_ts = int('$TASK_START')
csv_path = '$CSV'
json_path = '$JSON'
script_path = '$SCRIPT'

def check_file(path):
    if os.path.isfile(path):
        mtime = os.path.getmtime(path)
        return True, mtime > start_ts
    return False, False

script_exists, script_new = check_file(script_path)
csv_exists, csv_new = check_file(csv_path)
json_exists, json_new = check_file(json_path)

script_has_api = False
if script_exists:
    try:
        with open(script_path, 'r', encoding='utf-8') as f:
            content = f.read()
            if 'startSimulation' in content and 'sim.' in content:
                script_has_api = True
    except:
        pass

csv_rows = 0
valid_mapping_count = 0
csv_large = 0
csv_medium = 0
csv_small = 0

if csv_exists:
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            csv_rows = len(rows)
            
            if csv_rows > 0:
                headers = [h.strip().lower() for h in rows[0].keys()]
                z_col = next((h for h in rows[0].keys() if 'z' in h.lower()), None)
                face_col = next((h for h in rows[0].keys() if 'face' in h.lower()), None)
                
                if z_col and face_col:
                    for r in rows:
                        try:
                            z = float(r[z_col])
                            face = str(r[face_col]).strip().upper()
                            
                            expected_face = None
                            if 0.010 <= z <= 0.035: expected_face = 'LARGE'
                            elif 0.036 <= z <= 0.075: expected_face = 'MEDIUM'
                            elif 0.076 <= z <= 0.125: expected_face = 'SMALL'
                            
                            if face == expected_face:
                                valid_mapping_count += 1
                                
                            if expected_face == 'LARGE': csv_large += 1
                            elif expected_face == 'MEDIUM': csv_medium += 1
                            elif expected_face == 'SMALL': csv_small += 1
                        except:
                            pass
    except Exception as e:
        print(f'CSV Parse Error: {e}')

json_large = 0
json_medium = 0
json_small = 0
json_valid = False

if json_exists:
    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            d = json.load(f)
            json_large = int(d.get('large_face_count', 0))
            json_medium = int(d.get('medium_face_count', 0))
            json_small = int(d.get('small_face_count', 0))
            if 'total_drops' in d:
                json_valid = True
    except Exception as e:
        print(f'JSON Parse Error: {e}')

result = {
    'task_start': start_ts,
    'script_exists': script_exists,
    'script_has_api': script_has_api,
    'csv_exists': csv_exists,
    'csv_is_new': csv_new,
    'csv_row_count': csv_rows,
    'valid_mapping_count': valid_mapping_count,
    'json_exists': json_exists,
    'json_is_new': json_new,
    'json_valid': json_valid,
    'json_large': json_large,
    'json_medium': json_medium,
    'json_small': json_small,
    'csv_large': csv_large,
    'csv_medium': csv_medium,
    'csv_small': csv_small
}

with open('/tmp/parts_feeder_result.json', 'w') as f:
    json.dump(result, f)
"

echo "Result JSON saved to /tmp/parts_feeder_result.json"
cat /tmp/parts_feeder_result.json
echo ""
echo "=== Export Complete ==="