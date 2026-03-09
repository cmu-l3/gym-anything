#!/bin/bash
echo "=== Exporting IQ Validation Protocol Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot "iq_validation_export"

OUTPUT_FILE="/home/ga/Documents/VAL-IQ-UPLC-2024-004.odt"
RESULT_FILE="/tmp/task_result.json"

python3 << 'PYEOF'
import json
import os
import zipfile
import re

output_file = "/home/ga/Documents/VAL-IQ-UPLC-2024-004.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "heading1_count": 0,
    "heading2_count": 0,
    "table_count": 0,
    "has_toc": False,
    "has_footer": False,
    "has_page_numbers": False,
    "paragraph_count": 0,
    "text_length": 0,
    "mentions_instrument": False,
    "mentions_iq_terms": False,
    "mentions_document_number": False
}

if not os.path.exists(output_file):
    with open("/tmp/task_result.json", "w") as f:
        json.dump(result, f)
    print("Output file not found")
    raise SystemExit(0)

result["file_exists"] = True
result["file_size"] = os.path.getsize(output_file)

try:
    with zipfile.ZipFile(output_file, 'r') as z:
        # Parse content.xml
        with z.open('content.xml') as cf:
            content = cf.read().decode('utf-8', errors='replace')

        # Count headings by outline level
        h1_matches = re.findall(r'<text:h[^>]+text:outline-level="1"', content)
        h2_matches = re.findall(r'<text:h[^>]+text:outline-level="2"', content)
        result["heading1_count"] = len(h1_matches)
        result["heading2_count"] = len(h2_matches)

        # Count tables
        table_matches = re.findall(r'<table:table\b', content)
        result["table_count"] = len(table_matches)

        # Check for auto-generated TOC
        result["has_toc"] = 'text:table-of-content' in content

        # Count paragraphs
        para_matches = re.findall(r'<text:p[ >]', content)
        result["paragraph_count"] = len(para_matches)

        # Extract plain text and check content
        plain_text = re.sub(r'<[^>]+>', ' ', content).lower()
        result["text_length"] = len(plain_text.strip())

        # Check for instrument/company mentions
        result["mentions_instrument"] = (
            'acquity' in plain_text or
            'uplc' in plain_text or
            'waters' in plain_text
        )

        # Check for IQ-specific terminology
        iq_terms = ['installation qualification', 'acceptance criteria',
                    'iq-00', 'firmware', '21 cfr', 'usp']
        result["mentions_iq_terms"] = any(t in plain_text for t in iq_terms)

        # Check for document number
        result["mentions_document_number"] = 'val-iq-uplc-2024-004' in plain_text

        # Parse styles.xml for footer / page numbers
        try:
            with z.open('styles.xml') as sf:
                styles = sf.read().decode('utf-8', errors='replace')
            result["has_footer"] = '<style:footer' in styles
            result["has_page_numbers"] = (
                'text:page-number' in styles or 'text:page-number' in content
            )
        except Exception:
            pass

except Exception as e:
    result["parse_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export complete: file_size={result['file_size']}, "
      f"h1={result['heading1_count']}, h2={result['heading2_count']}, "
      f"tables={result['table_count']}, toc={result['has_toc']}, "
      f"footer={result['has_footer']}, paras={result['paragraph_count']}")
PYEOF

echo "=== Export Complete ==="
