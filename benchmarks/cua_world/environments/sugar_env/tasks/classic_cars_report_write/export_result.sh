#!/bin/bash
echo "=== Exporting classic_cars_report_write task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/task_final.png" 2>/dev/null || true

ODT_FILE="/home/ga/Documents/classic_cars_report.odt"
TASK_START=$(cat /tmp/classic_cars_start_ts 2>/dev/null || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
FILE_MTIME=0
FILE_MODIFIED="false"

if [ -f "$ODT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat --format=%s "$ODT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat --format=%Y "$ODT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Run python script to dynamically process the CSV and the ODT, and output json
cat << 'PYEOF' > /tmp/analyze_cars_report.py
import json
import csv
import zipfile
import re
import os
import sys

def extract_text_from_odt(filepath):
    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            with z.open('content.xml') as f:
                content = f.read().decode('utf-8')
        # Strip XML tags to get plain text
        plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
        plain_text = plain_text.replace('&amp;', '&').replace('&lt;', '<').replace('&gt;', '>')
        return plain_text, True
    except Exception as e:
        return str(e), False

def analyze():
    result = {
        "file_exists": sys.argv[1] == "true",
        "file_modified": sys.argv[2] == "true",
        "valid_odt": False,
        "headings": {"hp": False, "mpg": False},
        "found_hp_cars": [],
        "found_mpg_cars": [],
        "anti_dump_failed": False,
        "error": None
    }
    
    csv_path = "/home/ga/Documents/mpg.csv"
    odt_path = "/home/ga/Documents/classic_cars_report.odt"
    
    # 1. Parse CSV to find ground truth
    cars = []
    try:
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                cars.append(row)
    except Exception as e:
        result["error"] = f"CSV read error: {str(e)}"
        return result

    # Compute HP Threshold (top 5)
    valid_hp = []
    for c in cars:
        try:
            val = float(c.get('horsepower', ''))
            valid_hp.append((val, c.get('name', '').strip().lower()))
        except ValueError:
            pass
    valid_hp.sort(key=lambda x: x[0], reverse=True)
    
    top_hp_names = set()
    if len(valid_hp) >= 5:
        hp_threshold = valid_hp[4][0]
        top_hp_names = {name for val, name in valid_hp if val >= hp_threshold}
    else:
        top_hp_names = {name for val, name in valid_hp}

    # Compute MPG Threshold (top 5)
    valid_mpg = []
    for c in cars:
        try:
            val = float(c.get('mpg', ''))
            valid_mpg.append((val, c.get('name', '').strip().lower()))
        except ValueError:
            pass
    valid_mpg.sort(key=lambda x: x[0], reverse=True)
    
    top_mpg_names = set()
    if len(valid_mpg) >= 5:
        mpg_threshold = valid_mpg[4][0]
        top_mpg_names = {name for val, name in valid_mpg if val >= mpg_threshold}
    else:
        top_mpg_names = {name for val, name in valid_mpg}

    # Compute Anti-Dump (median mpg cars)
    anti_dump_names = set()
    if len(valid_mpg) > 20:
        mid_idx = len(valid_mpg) // 2
        anti_dump_names = {name for val, name in valid_mpg[mid_idx-5 : mid_idx+5]}

    # 2. Parse ODT
    if result["file_exists"]:
        text, valid = extract_text_from_odt(odt_path)
        result["valid_odt"] = valid
        
        if valid:
            # Check Headings
            result["headings"]["hp"] = "top 5 horsepower" in text
            result["headings"]["mpg"] = "top 5 mpg" in text
            
            # Check HP Cars
            found_hp = []
            for name in top_hp_names:
                if name in text:
                    found_hp.append(name)
            result["found_hp_cars"] = found_hp
            
            # Check MPG Cars
            found_mpg = []
            for name in top_mpg_names:
                if name in text:
                    found_mpg.append(name)
            result["found_mpg_cars"] = found_mpg
            
            # Check Anti-dump
            for name in anti_dump_names:
                if name in text:
                    result["anti_dump_failed"] = True
                    break

    print(json.dumps(result))

if __name__ == "__main__":
    analyze()
PYEOF

python3 /tmp/analyze_cars_report.py "$FILE_EXISTS" "$FILE_MODIFIED" > /tmp/task_result.json

chmod 666 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="