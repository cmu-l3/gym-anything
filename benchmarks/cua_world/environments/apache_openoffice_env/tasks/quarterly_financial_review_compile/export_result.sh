#!/bin/bash
echo "=== Exporting quarterly_financial_review_compile results ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

python3 << 'PYEOF'
import zipfile, re, json, os

output_path = "/home/ga/Documents/PNTP_Q3_Review_FY2024.odt"

result = {
    "file_exists": False,
    "file_size": 0,
    "formula_count": 0,
    "formulas_found": [],
    "calculated_values": [],
    "heading1_count": 0,
    "heading2_count": 0,
    "has_toc": False,
    "is_landscape_present": False,
    "has_footer": False,
    "has_page_number": False,
    "table_count": 0,
    "capex_keywords_found": [],
    "has_sawmill_note": False,
    "has_pntp_text": False,
    "has_confidential_text": False,
    "text_content": "",
    "created_during_task": False,
    "paragraph_count": 0,
    "parse_error": None
}

try:
    if os.path.exists(output_path):
        result["file_exists"] = True
        result["file_size"] = os.path.getsize(output_path)

        # Check if file was created/modified during the task
        task_start = 0
        if os.path.exists("/tmp/task_start_time.txt"):
            with open("/tmp/task_start_time.txt", "r") as f:
                try:
                    task_start = int(f.read().strip())
                except:
                    pass
        file_mtime = int(os.path.getmtime(output_path))
        if task_start > 0 and file_mtime >= task_start:
            result["created_during_task"] = True

        with zipfile.ZipFile(output_path, 'r') as zf:
            # Parse content.xml
            if 'content.xml' in zf.namelist():
                content = zf.read('content.xml').decode('utf-8', errors='replace')
                result["text_content"] = content[:5000]

                # Count formulas
                result["formulas_found"] = re.findall(r'table:formula\s*=\s*"([^"]+)"', content)
                result["formula_count"] = len(result["formulas_found"])

                # Extract calculated values from formula cells
                raw_values = re.findall(r'office:value\s*=\s*"([0-9.]+)"', content)
                result["calculated_values"] = [float(v) for v in raw_values]

                # Count headings
                result["heading1_count"] = len(re.findall(r'<text:h[^>]+text:outline-level="1"', content))
                result["heading2_count"] = len(re.findall(r'<text:h[^>]+text:outline-level="2"', content))

                # Check for auto-generated TOC
                result["has_toc"] = 'text:table-of-content' in content

                # Count tables
                result["table_count"] = len(re.findall(r'<table:table[ >]', content))

                # Count paragraphs
                result["paragraph_count"] = len(re.findall(r'<text:p[ >]', content))

                # Check CapEx keywords
                for kw in ["Sawmill", "Kiln", "Wastewater", "Fleet"]:
                    if kw.lower() in content.lower():
                        result["capex_keywords_found"].append(kw)

                # Check for Sawmill status note (60%)
                result["has_sawmill_note"] = "60%" in content or "60 percent" in content.lower()

                # Check for PNTP and CONFIDENTIAL
                result["has_pntp_text"] = "PNTP" in content
                result["has_confidential_text"] = "CONFIDENTIAL" in content or "Confidential" in content

            # Parse styles.xml for page layout and footer
            if 'styles.xml' in zf.namelist():
                styles = zf.read('styles.xml').decode('utf-8', errors='replace')

                # Check for landscape page orientation
                if 'print-orientation="landscape"' in styles:
                    result["is_landscape_present"] = True

                # Check for footer
                if '<style:footer' in styles:
                    result["has_footer"] = True
                    # Check for PNTP/CONFIDENTIAL in footer
                    if "PNTP" in styles:
                        result["has_pntp_text"] = True
                    if "CONFIDENTIAL" in styles or "Confidential" in styles:
                        result["has_confidential_text"] = True

                # Check for page number field
                if 'text:page-number' in styles or 'text:page-number' in content:
                    result["has_page_number"] = True

    else:
        result["parse_error"] = f"Output file not found: {output_path}"

except Exception as e:
    result["parse_error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="
