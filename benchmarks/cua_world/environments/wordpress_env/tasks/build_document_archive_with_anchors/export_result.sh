#!/bin/bash
# Export script for build_document_archive_with_anchors task (post_task hook)

echo "=== Exporting Document Archive result ==="

# Source utility functions
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# Extract Data via WP-CLI and Python
# ============================================================

# Dump all pages and PDFs to JSON
echo "Exporting database state..."
wp post list --post_type=page --post_status=publish,draft,pending --format=json --allow-root > /tmp/all_pages.json
wp post list --post_type=attachment --post_mime_type=application/pdf --format=json --allow-root > /tmp/current_pdfs.json

# Process exported data using Python to ensure safe JSON handling
python3 << 'PYEOF'
import json
import os
import datetime

# Load pages
try:
    with open('/tmp/all_pages.json', 'r') as f:
        pages = json.load(f)
except Exception as e:
    print(f"Error loading pages: {e}")
    pages = []

# Load current PDFs
try:
    with open('/tmp/current_pdfs.json', 'r') as f:
        current_pdfs = json.load(f)
except Exception as e:
    print(f"Error loading current PDFs: {e}")
    current_pdfs = []

# Load initial PDFs
try:
    with open('/tmp/initial_pdfs.json', 'r') as f:
        initial_pdfs = json.load(f)
except Exception as e:
    print(f"Error loading initial PDFs: {e}")
    initial_pdfs = []

# Identify target page
target_page = None
for p in pages:
    if p.get('post_title', '').strip().lower() == "space exploration archive":
        # Get raw content explicitly via WP-CLI to ensure block comments are preserved
        post_id = p.get('ID')
        import subprocess
        try:
            raw_content = subprocess.check_output(
                ['wp', 'post', 'get', str(post_id), '--field=post_content', '--allow-root'],
                text=True
            )
            p['raw_content'] = raw_content
        except:
            p['raw_content'] = p.get('post_content', '')
            
        target_page = p
        break

result = {
    "page_found": target_page is not None,
    "page": target_page,
    "initial_pdf_count": len(initial_pdfs),
    "current_pdf_count": len(current_pdfs),
    "current_pdfs": current_pdfs,
    "export_timestamp": datetime.datetime.now().isoformat(),
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="