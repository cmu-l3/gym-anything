#!/bin/bash
echo "=== Exporting Season Performance Report Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define output path
OUTPUT_FILE="/home/ga/Documents/ValleyCats_MidSeason_2024.odt"
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 3. Analyze the ODT file using Python
# We extract metadata directly on the agent side to send lightweight JSON to verifier
python3 << 'PYEOF'
import zipfile
import json
import os
import re
import time

output_file = "/home/ga/Documents/ValleyCats_MidSeason_2024.odt"
task_start_time = int(os.environ.get('TASK_START_TIME', 0))

result = {
    "file_exists": False,
    "file_size": 0,
    "is_newly_created": False,
    "has_toc": False,
    "has_page_numbers": False,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "paragraph_count": 0,
    "player_names_found": [],
    "stat_values_found": [],
    "raw_text_preview": ""
}

if os.path.exists(output_file):
    result["file_exists"] = True
    stats = os.stat(output_file)
    result["file_size"] = stats.st_size
    
    # Check modification time against task start
    if stats.st_mtime > task_start_time:
        result["is_newly_created"] = True

    try:
        with zipfile.ZipFile(output_file, 'r') as zf:
            # READ CONTENT.XML
            content = zf.read('content.xml').decode('utf-8', errors='replace')
            
            # Structural Checks
            result["has_toc"] = 'text:table-of-content' in content
            
            # Count Headings (Proper ODF styles)
            result["heading1_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="1"', content))
            result["heading2_count"] = len(re.findall(r'<text:h[^>]*text:outline-level="2"', content))
            
            # Count Tables
            result["table_count"] = len(re.findall(r'<table:table\b', content))
            
            # Count Paragraphs
            result["paragraph_count"] = len(re.findall(r'<text:p\b', content))

            # Extract Text for Content Verification
            # Simple regex strip of XML tags
            plain_text = re.sub(r'<[^>]+>', ' ', content)
            plain_text = re.sub(r'\s+', ' ', plain_text)
            result["raw_text_preview"] = plain_text[:500]

            # READ STYLES.XML (often contains footer definitions)
            styles_xml = ""
            if 'styles.xml' in zf.namelist():
                styles_xml = zf.read('styles.xml').decode('utf-8', errors='replace')
            
            # Check Page Numbers (can be in content or styles/master-pages)
            result["has_page_numbers"] = ('text:page-number' in content) or ('text:page-number' in styles_xml)

            # Content Checks (Specific Players/Stats)
            # These are the ones mentioned in the task design
            players_to_check = ["Espinoza", "Hawkins", "Branson", "Pittman", "Fuentes"]
            found_players = [p for p in players_to_check if p in plain_text]
            result["player_names_found"] = found_players
            
            stats_to_check = [".302", "2.45", "14", "3.12", ".560"]
            found_stats = [s for s in stats_to_check if s in plain_text]
            result["stat_values_found"] = found_stats

    except Exception as e:
        result["error"] = str(e)

# Save result to JSON
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# 4. Handle permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="