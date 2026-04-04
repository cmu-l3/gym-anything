#!/bin/bash
# Export script for customize_email_template task
# Scrapes the Email Templates configuration from Manager.io via API/HTML

echo "=== Exporting customize_email_template result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Python script to scrape the current email template state
# Manager.io structure: 
# 1. Login -> Get cookies
# 2. Get Business Key
# 3. List Email Templates -> Find "Sales Invoice" entry
# 4. Get Template Detail -> Extract Subject and Body

python3 - << 'PYEOF' > /tmp/task_result.json
import requests
import re
import json
import sys

MANAGER_URL = "http://localhost:8080"
COOKIE_FILE = "/tmp/mgr_cookies.txt"

def run_export():
    session = requests.Session()
    
    # 1. Login
    try:
        # Initial page load to get potential CSRF tokens or cookies
        session.get(MANAGER_URL)
        # Login
        login_resp = session.post(f"{MANAGER_URL}/login", data={"Username": "administrator"}, allow_redirects=True)
    except Exception as e:
        print(json.dumps({"error": f"Login failed: {e}"}))
        return

    # 2. Find Northwind Traders Business Key
    try:
        biz_page = session.get(f"{MANAGER_URL}/businesses").text
        # Look for the UUID associated with Northwind Traders
        # Pattern: <a href="/start?Key=UUID">Northwind Traders</a>
        m = re.search(r'start\?([^"&\s]+)[^<]{0,300}Northwind Traders', biz_page)
        if not m:
             # Fallback to any business if Northwind specifically isn't found (unlikely in this env)
             m = re.search(r'start\?([^"&\s]+)', biz_page)
        
        if not m:
            print(json.dumps({"error": "Could not find business key"}))
            return
            
        biz_key = m.group(1)
        # "Start" the session for this business
        session.get(f"{MANAGER_URL}/start?{biz_key}")
        
    except Exception as e:
        print(json.dumps({"error": f"Business lookup failed: {e}"}))
        return

    # 3. Find Email Templates
    # First, navigate to Settings to find the link to Email Templates
    # The URL is typically /email-templates?FileID=...
    try:
        settings_page = session.get(f"{MANAGER_URL}/settings?{biz_key}").text
        # Look for link to email templates
        # It usually contains "email-templates" in the href
        m_link = re.search(r'href="([^"]*email-templates[^"]*)"', settings_page)
        if not m_link:
            print(json.dumps({"error": "Could not find Email Templates link in Settings"}))
            return
            
        email_templates_url = f"{MANAGER_URL}{m_link.group(1)}"
        templates_page = session.get(email_templates_url).text
        
        # 4. Find the "Sales Invoice" template
        # The list page will show existing templates. We look for "Sales Invoice".
        # If it exists, there will be a link to edit it (usually the View name or an Edit button).
        # We look for a row that mentions "Sales Invoice" and capture the edit/view link.
        # The link usually looks like /email-template-form?Key=...
        
        # Regex to find the link for Sales Invoice
        # We look for "Sales Invoice" text, then find the closest preceding or succeeding link
        
        # Simplistic approach: Split by rows or look for pattern
        # The row usually has the type "Sales Invoice" and a link.
        
        template_found = False
        subject = ""
        body = ""
        
        # Check if "Sales Invoice" is in the text
        if "Sales Invoice" in templates_page:
            template_found = True
            
            # Extract the Edit link for Sales Invoice
            # This is tricky with regex on raw HTML. Let's look for the specific href associated with it.
            # Often structured as: <tr><td><a href="...">Sales Invoice</a></td>...
            m_edit = re.search(r'href="([^"]*email-template-form[^"]*)"[^>]*>Sales Invoice', templates_page)
            if not m_edit:
                # Try searching reverse: link then text
                 m_edit = re.search(r'href="([^"]*email-template-form[^"]*)".{0,200}Sales Invoice', templates_page, re.DOTALL)
            
            if m_edit:
                form_url = f"{MANAGER_URL}{m_edit.group(1)}"
                form_page = session.get(form_url).text
                
                # Extract Subject and Body from input fields
                # Subject: <input ... name="Subject" ... value="...">
                m_subj = re.search(r'name="Subject"[^>]*value="([^"]*)"', form_page)
                if m_subj:
                    subject = m_subj.group(1)
                else:
                    # Try textarea or other format? usually subject is input type=text
                    pass
                
                # Body: <textarea ... name="Body"...>Content</textarea>
                m_body = re.search(r'name="Body"[^>]*>([^<]*)<', form_page)
                if m_body:
                    body = m_body.group(1)
            else:
                # It might be in "View" mode rather than Edit link directly?
                # Assume if we found "Sales Invoice" text, a template exists.
                pass
        
    except Exception as e:
        print(json.dumps({"error": f"Scraping failed: {e}"}))
        return

    # Output result
    result = {
        "template_found": template_found,
        "subject": subject,
        "body": body,
        "scraped_successfully": True
    }
    print(json.dumps(result))

if __name__ == "__main__":
    run_export()
PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json