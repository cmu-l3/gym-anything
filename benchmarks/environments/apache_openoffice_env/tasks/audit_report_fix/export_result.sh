#!/bin/bash
echo "=== Exporting Audit Report Fix Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot "audit_report_export"

OUTPUT_FILE="/home/ga/Documents/building_audit_final.odt"
RESULT_FILE="/tmp/task_result.json"

python3 << 'PYEOF'
import json
import os
import zipfile
import re

output_file = "/home/ga/Documents/building_audit_final.odt"
result = {
    "file_exists": False,
    "file_size": 0,
    "heading1_count": 0,
    "heading2_count": 0,
    "heading3_count": 0,
    "has_toc": False,
    "has_footer": False,
    "has_page_numbers": False,
    "red_text_count": 0,
    "red_style_names": [],
    "paragraph_count": 0
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

        # Count headings
        h1_matches = re.findall(r'<text:h[^>]+text:outline-level="1"', content)
        h2_matches = re.findall(r'<text:h[^>]+text:outline-level="2"', content)
        h3_matches = re.findall(r'<text:h[^>]+text:outline-level="3"', content)
        result["heading1_count"] = len(h1_matches)
        result["heading2_count"] = len(h2_matches)
        result["heading3_count"] = len(h3_matches)

        # Check for auto-generated TOC
        result["has_toc"] = 'text:table-of-content' in content

        # Count paragraphs
        para_matches = re.findall(r'<text:p[ >]', content)
        result["paragraph_count"] = len(para_matches)

        # Detect red text: find automatic style names that have fo:color="#ff0000"
        # Search both content.xml and the automatic-styles section
        red_patterns = [
            r'fo:color="#ff0000"',
            r'fo:color="#FF0000"',
            r'fo:color="#Ff0000"',
            r'fo:color="#fF0000"',
        ]
        red_in_content = sum(
            len(re.findall(p, content, re.IGNORECASE))
            for p in [r'fo:color="#ff0000"']
        )
        # More robust: case-insensitive search
        red_matches_ci = re.findall(r'fo:color="#(?:ff|FF|Ff|fF)0{4}"', content, re.IGNORECASE)
        red_hex_matches = re.findall(r'fo:color="#([0-9a-fA-F]{6})"', content)
        # Count red-ish colors (R=FF, G and B are low)
        red_count = 0
        red_style_names = []
        for hex_val in red_hex_matches:
            r_val = int(hex_val[0:2], 16)
            g_val = int(hex_val[2:4], 16)
            b_val = int(hex_val[4:6], 16)
            if r_val >= 200 and g_val < 50 and b_val < 50:
                red_count += 1

        # Also find style names with red color defined
        style_red_pattern = r'style:name="([^"]+)"[^>]*>(?:[^<]|<(?!style:))*?fo:color="#(?:ff|FF)0000"'
        red_styles = re.findall(
            r'<style:style[^>]+style:name="([^"]+)"[^<]*(?:<[^/][^>]*>)*?'
            r'<style:text-properties[^>]+fo:color="#(?:ff|FF)0000"',
            content, re.DOTALL
        )
        result["red_style_names"] = red_styles[:10]

        # Count paragraphs that USE a red style
        red_para_count = 0
        for sname in red_styles:
            escaped = re.escape(sname)
            red_para_count += len(re.findall(
                f'<text:p[^>]+text:style-name="{escaped}"', content
            ))

        # Also count raw occurrences of the red color string as a proxy
        result["red_text_count"] = max(
            red_para_count,
            len(re.findall(r'fo:color="#ff0000"', content, re.IGNORECASE))
        )

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
      f"h3={result['heading3_count']}, toc={result['has_toc']}, "
      f"red_count={result['red_text_count']}, "
      f"footer={result['has_footer']}, page_numbers={result['has_page_numbers']}")
PYEOF

echo "=== Export Complete ==="
