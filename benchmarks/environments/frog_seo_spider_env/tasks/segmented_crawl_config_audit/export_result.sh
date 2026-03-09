#!/bin/bash
# Export result script for Segmented Crawl Config Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# 2. Define paths
EXPORT_FILE="/home/ga/Documents/SEO/exports/segmented_crawl.csv"
REPORT_FILE="/home/ga/Documents/SEO/reports/segment_counts.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 3. Analyze Output Files (using Python for CSV parsing reliability)
python3 << PYEOF
import json
import csv
import os
import sys
import time

result = {
    "export_exists": False,
    "export_created_during_task": False,
    "report_exists": False,
    "report_content": "",
    "has_segment_column": False,
    "segments_found": [],
    "travel_correct": False,
    "mystery_correct": False,
    "poetry_correct": False,
    "total_rows": 0,
    "sf_running": False
}

# Check SF process
try:
    if os.system("pgrep -f 'ScreamingFrogSEOSpider' > /dev/null") == 0:
        result["sf_running"] = True
except:
    pass

# Check Report File
report_path = "$REPORT_FILE"
if os.path.exists(report_path):
    result["report_exists"] = True
    try:
        with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
            result["report_content"] = f.read()
    except:
        pass

# Check Export CSV
csv_path = "$EXPORT_FILE"
task_start = float($TASK_START_EPOCH)

if os.path.exists(csv_path):
    result["export_exists"] = True
    mtime = os.path.getmtime(csv_path)
    if mtime > task_start:
        result["export_created_during_task"] = True
    
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            # Handle potential BOM or first few lines garbage
            # Screaming Frog CSVs usually start with headers on line 2 if there's a summary, 
            # or line 1. Let's try to sniff headers.
            reader = csv.reader(f)
            headers = None
            rows = []
            
            # Read first few lines to find header
            for i, line in enumerate(reader):
                if not line: continue
                # Look for standard columns + Segment
                # SF Internal tab usually has "Address", "Content", "Status Code"
                if "Address" in line and ("Segment" in line or "Segments" in line):
                    headers = line
                    break
                elif "Address" in line: # header found but maybe no segment col
                    headers = line
                    break
            
            if headers:
                # Map column indices
                try:
                    addr_idx = headers.index("Address")
                    # Segment column might be named "Segment" or "Segments"
                    seg_idx = -1
                    if "Segment" in headers:
                        seg_idx = headers.index("Segment")
                    elif "Segments" in headers:
                        seg_idx = headers.index("Segments")
                    
                    if seg_idx != -1:
                        result["has_segment_column"] = True
                        
                        # Validate data rows
                        # We need to verify that specific URL patterns match the segments
                        travel_ok = False
                        mystery_ok = False
                        poetry_ok = False
                        
                        found_segments = set()
                        
                        for row in reader:
                            if len(row) <= max(addr_idx, seg_idx): continue
                            
                            url = row[addr_idx]
                            segment = row[seg_idx]
                            
                            if segment:
                                found_segments.add(segment)
                            
                            # Verify specific logic
                            if "travel_2" in url:
                                if "Travel" in segment: travel_ok = True
                            if "mystery_3" in url:
                                if "Mystery" in segment: mystery_ok = True
                            if "poetry_23" in url:
                                if "Poetry" in segment: poetry_ok = True
                                
                            result["total_rows"] += 1
                            
                        result["travel_correct"] = travel_ok
                        result["mystery_correct"] = mystery_ok
                        result["poetry_correct"] = poetry_ok
                        result["segments_found"] = list(found_segments)
                        
                except ValueError:
                    pass # Columns not found
                    
    except Exception as e:
        print(f"Error parsing CSV: {e}")

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

cat /tmp/task_result.json
echo "=== Export Complete ==="