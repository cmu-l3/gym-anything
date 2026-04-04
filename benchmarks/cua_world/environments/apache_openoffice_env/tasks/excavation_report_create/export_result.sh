#!/bin/bash
echo "=== Exporting Excavation Report Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Variables
OUTPUT_FILE="/home/ga/Documents/UNM-OCA-2024-031.odt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
JSON_RESULT="/tmp/task_result.json"

# 3. Run Python script to analyze ODT file
# We use Python because parsing XML with bash is fragile
python3 -c '
import sys
import os
import json
import zipfile
import re
import time

output_path = "'"$OUTPUT_FILE"'"
task_start = int("'"$TASK_START"'")
result = {
    "exists": False,
    "size_bytes": 0,
    "created_after_start": False,
    "toc_present": False,
    "h1_count": 0,
    "h2_count": 0,
    "table_count": 0,
    "page_numbers_present": False,
    "body_para_count": 0,
    "keywords_found": [],
    "error": None
}

if os.path.exists(output_path):
    result["exists"] = True
    stats = os.stat(output_path)
    result["size_bytes"] = stats.st_size
    result["created_after_start"] = stats.st_mtime > task_start

    try:
        with zipfile.ZipFile(output_path, "r") as zf:
            # Read content.xml
            content_xml = zf.read("content.xml").decode("utf-8")
            
            # Read styles.xml (for page numbers/footers)
            styles_xml = ""
            if "styles.xml" in zf.namelist():
                styles_xml = zf.read("styles.xml").decode("utf-8")

            # Check for TOC
            if "text:table-of-content" in content_xml:
                result["toc_present"] = True

            # Count Headings (proper styles)
            # Look for <text:h ... text:outline-level="1">
            result["h1_count"] = len(re.findall(r"<text:h[^>]*text:outline-level=\"1\"", content_xml))
            result["h2_count"] = len(re.findall(r"<text:h[^>]*text:outline-level=\"2\"", content_xml))

            # Count Tables
            result["table_count"] = len(re.findall(r"<table:table ", content_xml))

            # Check Page Numbers (text:page-number tag in styles or content)
            if "text:page-number" in content_xml or "text:page-number" in styles_xml:
                result["page_numbers_present"] = True

            # Count substantial body paragraphs (not headers, length > 20 chars)
            # Simple regex approximation
            paras = re.findall(r"<text:p[^>]*>(.*?)</text:p>", content_xml)
            body_count = 0
            text_content = ""
            for p in paras:
                clean_p = re.sub(r"<[^>]+>", "", p)
                text_content += clean_p + " "
                if len(clean_p) > 20:
                    body_count += 1
            result["body_para_count"] = body_count

            # Check Keywords
            target_keywords = ["LA 189274", "Coyote Springs", "pueblo", "ceramic", "stratigraphy"]
            found = []
            for kw in target_keywords:
                if kw.lower() in text_content.lower():
                    found.append(kw)
            result["keywords_found"] = found

    except Exception as e:
        result["error"] = str(e)

# Write result to JSON
with open("'"$JSON_RESULT"'", "w") as f:
    json.dump(result, f, indent=2)
'

# 4. Set permissions
chmod 666 "$JSON_RESULT" 2>/dev/null || true

echo "Analysis complete. Result saved to $JSON_RESULT"
cat "$JSON_RESULT"
echo "=== Export complete ==="