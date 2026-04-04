#!/bin/bash
echo "=== Exporting FRS Patient Portal Result ==="

# Source task utils
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Define output path
OUTPUT_FILE="/home/ga/Documents/FRS-PC3-2024-012.odt"
RESULT_JSON="/tmp/task_result.json"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Analyze the ODT file using Python
# We extract content.xml and styles.xml from the ODT (zip) and parse them
python3 -c "
import zipfile
import re
import json
import os
import sys
from datetime import datetime

output_path = '$OUTPUT_FILE'
task_start_ts = $TASK_START_TIME
result = {
    'file_exists': False,
    'file_size_bytes': 0,
    'file_created_during_task': False,
    'structure': {
        'toc_found': False,
        'h1_count': 0,
        'h2_count': 0,
        'table_count': 0,
        'paragraph_count': 0,
        'page_numbers_found': False
    },
    'content': {
        'module_ids_found': [],
        'keywords_found': []
    }
}

if os.path.exists(output_path):
    # File stats
    stats = os.stat(output_path)
    result['file_exists'] = True
    result['file_size_bytes'] = stats.st_size
    
    # Check modification time against task start
    if stats.st_mtime > task_start_ts:
        result['file_created_during_task'] = True

    try:
        with zipfile.ZipFile(output_path, 'r') as zf:
            # 1. Analyze content.xml
            content = zf.read('content.xml').decode('utf-8', errors='ignore')
            
            # Structural checks using Regex on XML tags
            # Heading 1: <text:h ... text:outline-level='1'>
            result['structure']['h1_count'] = len(re.findall(r'<text:h[^>]*text:outline-level=\"1\"', content))
            
            # Heading 2: <text:h ... text:outline-level='2'>
            result['structure']['h2_count'] = len(re.findall(r'<text:h[^>]*text:outline-level=\"2\"', content))
            
            # Tables: <table:table ...>
            result['structure']['table_count'] = len(re.findall(r'<table:table\b', content))
            
            # TOC: <text:table-of-content ...>
            result['structure']['toc_found'] = bool(re.search(r'<text:table-of-content\b', content))
            
            # Paragraphs (body text estimation)
            result['structure']['paragraph_count'] = len(re.findall(r'<text:p\b', content))

            # Page numbers in content (sometimes placed directly in text flow)
            if re.search(r'<text:page-number', content):
                result['structure']['page_numbers_found'] = True

            # Content Extraction for keyword matching
            # Remove tags to get plain text
            plain_text = re.sub(r'<[^>]+>', ' ', content)
            
            # Check for Module IDs
            modules = ['FR-AUTH', 'FR-APPT', 'FR-MR', 'FR-MSG', 'FR-BILL']
            for mod in modules:
                if mod in plain_text:
                    result['content']['module_ids_found'].append(mod)

            # Check for specific Keywords
            keywords = ['PatientConnect', 'FHIR', 'HIPAA', 'WCAG', 'SAML', 'HL7', 'DICOM', 'Pinnacle']
            for kw in keywords:
                if kw in plain_text:
                    result['content']['keywords_found'].append(kw)
            
            # 2. Analyze styles.xml (usual location for footer page numbers)
            if 'styles.xml' in zf.namelist():
                styles = zf.read('styles.xml').decode('utf-8', errors='ignore')
                if re.search(r'<text:page-number', styles):
                    result['structure']['page_numbers_found'] = True

    except Exception as e:
        result['error'] = str(e)

# Output JSON
with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f, indent=2)
"

# 4. Handle permissions so verification script can read it
chmod 666 "$RESULT_JSON" 2>/dev/null || true

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="