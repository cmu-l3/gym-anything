#!/bin/bash
echo "=== Exporting implement_compliance_login_banner task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# Capture HTTP response of the login page
HTTP_CODE=$(curl -s -o /tmp/login_page.html -w "%{http_code}" http://localhost/login)

# Check if any view files were modified after the task started
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MODIFIED_FILES_COUNT=$(find /opt/socioboard/socioboard-web-php/resources/views -type f -newermt "@$TASK_START" 2>/dev/null | wc -l)

# Parse the HTML using Python to extract the injected elements cleanly
python3 << 'PYEOF'
import json, sys
from html.parser import HTMLParser

class ComplianceParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.found_warning_id = False
        self.warning_text = ""
        self.in_warning = False
        
        self.found_link_id = False
        self.link_href = ""
        self.link_text = ""
        self.in_link = False

    def handle_starttag(self, tag, attrs):
        attr_dict = dict(attrs)
        if attr_dict.get('id') == 'legal-warning':
            self.found_warning_id = True
            self.in_warning = True
        if attr_dict.get('id') == 'corp-privacy-policy':
            self.found_link_id = True
            self.in_link = True
            self.link_href = attr_dict.get('href', '')

    def handle_endtag(self, tag):
        self.in_warning = False
        self.in_link = False

    def handle_data(self, data):
        if self.in_warning:
            self.warning_text += data
        if self.in_link:
            self.link_text += data

def main():
    try:
        with open('/tmp/login_page.html', 'r', encoding='utf-8') as f:
            html = f.read()
    except Exception:
        html = ""

    parser = ComplianceParser()
    try:
        parser.feed(html)
    except Exception:
        pass

    # Clean whitespace for reliable matching
    warning_text = " ".join(parser.warning_text.split())
    link_text = " ".join(parser.link_text.split())

    result = {
        "http_code": int(sys.argv[1]),
        "modified_files_count": int(sys.argv[2]),
        "found_warning_id": parser.found_warning_id,
        "warning_text": warning_text,
        "found_link_id": parser.found_link_id,
        "link_href": parser.link_href.strip(),
        "link_text": link_text
    }

    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)

if __name__ == '__main__':
    main()
PYEOF "$HTTP_CODE" "$MODIFIED_FILES_COUNT"

chmod 644 /tmp/task_result.json /tmp/task_final.png 2>/dev/null || sudo chmod 644 /tmp/task_result.json /tmp/task_final.png 2>/dev/null || true

echo "Export completed. Results saved to /tmp/task_result.json"
cat /tmp/task_result.json