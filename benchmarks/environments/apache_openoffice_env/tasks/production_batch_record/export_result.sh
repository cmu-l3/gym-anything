#!/bin/bash
echo "=== Exporting Production Batch Record Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_FILE="/home/ga/Documents/BPR-2024-1847.odt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Initialize default result values
FILE_EXISTS="false"
FILE_SIZE=0
HEADING1_COUNT=0
HEADING2_COUNT=0
TABLE_COUNT=0
HAS_TOC="false"
HAS_FOOTER_PAGE_NUM="false"
PARAGRAPH_COUNT=0
CONTENT_MATCHES_COMPANY="false"
CONTENT_MATCHES_BATCH="false"
CONTENT_MATCHES_PRODUCT="false"
CONTENT_MATCHES_REGULATORY="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    
    # Use python to analyze the ODT structure (ODT is a zip containing XMLs)
    # We extract metrics directly here to avoid dependency issues in verifier
    # and to package the evidence in a clean JSON
    
    PYTHON_ANALYSIS=$(python3 -c "
import zipfile
import re
import sys

try:
    odt_path = '$OUTPUT_FILE'
    metrics = {
        'h1': 0, 'h2': 0, 'tables': 0, 'toc': False, 
        'page_num': False, 'paras': 0, 
        'has_company': False, 'has_batch': False, 'has_product': False, 'has_reg': False
    }
    
    with zipfile.ZipFile(odt_path, 'r') as zf:
        # Analyze content.xml
        content = zf.read('content.xml').decode('utf-8', errors='ignore')
        
        # Count Headings (looking for Outline Level which implies Heading styles)
        metrics['h1'] = len(re.findall(r'<text:h[^>]*text:outline-level=\"1\"', content))
        metrics['h2'] = len(re.findall(r'<text:h[^>]*text:outline-level=\"2\"', content))
        
        # Count Tables
        metrics['tables'] = len(re.findall(r'<table:table ', content))
        
        # Check TOC (text:table-of-content)
        if 'text:table-of-content' in content:
            metrics['toc'] = True
            
        # Count Paragraphs
        metrics['paras'] = len(re.findall(r'<text:p', content))
        
        # Check Content (strip tags for text search)
        text_only = re.sub(r'<[^>]+>', ' ', content).lower()
        if 'lakeshore' in text_only: metrics['has_company'] = True
        if 'bpr-2024-1847' in text_only: metrics['has_batch'] = True
        if 'hydrating facial serum' in text_only: metrics['has_product'] = True
        if '21 cfr' in text_only or 'iso 22716' in text_only: metrics['has_reg'] = True
        
        # Check Page Numbers (often in styles.xml or content.xml)
        if 'text:page-number' in content:
            metrics['page_num'] = True
        else:
            try:
                styles = zf.read('styles.xml').decode('utf-8', errors='ignore')
                if 'text:page-number' in styles:
                    metrics['page_num'] = True
            except:
                pass

    print(f\"{metrics['h1']}|{metrics['h2']}|{metrics['tables']}|{metrics['toc']}|{metrics['page_num']}|{metrics['paras']}|{metrics['has_company']}|{metrics['has_batch']}|{metrics['has_product']}|{metrics['has_reg']}\")

except Exception as e:
    print(f\"ERROR: {e}\", file=sys.stderr)
    print(\"0|0|0|False|False|0|False|False|False|False\")
")

    # Parse Python output
    IFS='|' read -r HEADING1_COUNT HEADING2_COUNT TABLE_COUNT HAS_TOC HAS_FOOTER_PAGE_NUM PARAGRAPH_COUNT CONTENT_MATCHES_COMPANY CONTENT_MATCHES_BATCH CONTENT_MATCHES_PRODUCT CONTENT_MATCHES_REGULATORY <<< "$PYTHON_ANALYSIS"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "structure": {
        "heading1_count": $HEADING1_COUNT,
        "heading2_count": $HEADING2_COUNT,
        "table_count": $TABLE_COUNT,
        "has_toc": $HAS_TOC,
        "has_footer_page_numbers": $HAS_FOOTER_PAGE_NUM,
        "paragraph_count": $PARAGRAPH_COUNT
    },
    "content": {
        "matches_company": $CONTENT_MATCHES_COMPANY,
        "matches_batch": $CONTENT_MATCHES_BATCH,
        "matches_product": $CONTENT_MATCHES_PRODUCT,
        "matches_regulatory": $CONTENT_MATCHES_REGULATORY
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="