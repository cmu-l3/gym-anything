#!/bin/bash
set -e
echo "=== Setting up Deduplicate Overlapping Features Task ==="

# Define paths
# Note: In this environment, adb is available to talk to the emulator
ANDROID_GPKG="/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/world_survey.gpkg"
LOCAL_GPKG="/tmp/world_survey.gpkg"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Ensure QField is stopped
adb shell am force-stop ch.opengis.qfield

# 2. Pull the GeoPackage to local container to inject the duplicate
echo "Pulling GeoPackage from device..."
# Ensure the directory exists on device first (in case it's a fresh run)
adb shell "mkdir -p '/sdcard/Android/data/ch.opengis.qfield/files/Imported Datasets/'"
# If file doesn't exist in target, copy from backup
adb shell "if [ ! -f '$ANDROID_GPKG' ]; then cp /sdcard/QFieldData/world_survey.gpkg '$ANDROID_GPKG'; fi"

adb pull "$ANDROID_GPKG" "$LOCAL_GPKG"

# 3. Inject Duplicate Rome with Python (running in container)
echo "Injecting duplicate feature..."
python3 -c "
import sqlite3
import sys

try:
    conn = sqlite3.connect('$LOCAL_GPKG')
    conn.enable_load_extension(True)
    cursor = conn.cursor()
    
    # Find table name for capitals
    cursor.execute(\"SELECT table_name FROM gpkg_contents WHERE identifier LIKE '%capital%'\")
    res = cursor.fetchone()
    if not res:
        print('Error: Capital cities table not found')
        sys.exit(1)
    table_name = res[0]
    
    # Check if duplicate already exists (idempotency)
    cursor.execute(f\"SELECT count(*) FROM {table_name} WHERE name='Rome' AND description='LEGACY_DUPLICATE'\")
    if cursor.fetchone()[0] > 0:
        print('Duplicate already exists, skipping injection')
    else:
        # Get original Rome data
        cursor.execute(f\"SELECT * FROM {table_name} WHERE name='Rome'\")
        rome_row = cursor.fetchone()
        
        if not rome_row:
            print('Error: Rome not found')
            sys.exit(1)
            
        # Get column names
        col_names = [description[0] for description in cursor.description]
        
        # Prepare insert
        insert_cols = []
        insert_vals = []
        
        for col, val in zip(col_names, rome_row):
            # Skip Primary Key (usually fid or id) to let it auto-increment
            if col.lower() in ['fid', 'id', 'ogc_fid']: 
                continue
            
            insert_cols.append(col)
            if col.lower() == 'description':
                insert_vals.append('LEGACY_DUPLICATE')
            else:
                insert_vals.append(val)
                
        placeholders = ','.join(['?'] * len(insert_vals))
        cols_str = ','.join(insert_cols)
        
        query = f\"INSERT INTO {table_name} ({cols_str}) VALUES ({placeholders})\"
        cursor.execute(query, insert_vals)
        conn.commit()
        print(f'Successfully injected duplicate Rome into {table_name}')
        
    conn.close()
except Exception as e:
    print(f'Setup failed: {e}')
    sys.exit(1)
"

# 4. Push modified GeoPackage back to device
echo "Pushing modified GeoPackage..."
adb push "$LOCAL_GPKG" "$ANDROID_GPKG"

# 5. Launch QField via Intent to open this specific project
echo "Launching QField..."
adb shell am start -a android.intent.action.VIEW \
    -d "file://$ANDROID_GPKG" \
    -t "application/geopackage+sqlite3" \
    -n "ch.opengis.qfield/.QFieldActivity"

# 6. Wait for app to load
sleep 10
echo "Capturing initial state..."
adb shell screencap -p /sdcard/task_initial.png
adb pull /sdcard/task_initial.png /tmp/task_initial.png

echo "=== Setup complete ==="