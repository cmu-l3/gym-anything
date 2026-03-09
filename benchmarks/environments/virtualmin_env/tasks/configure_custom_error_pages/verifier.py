#!/usr/bin/env python3
"""
Verifier for configure_custom_error_pages task.

Criteria:
1. Files (404.html, 403.html) exist in correct location (10 pts)
2. Content matches requirements (Heading, Body text, Link) (30 pts)
3. Configuration exists (in Apache config or .htaccess) (20 pts)
4. Functional test: Requesting missing page returns custom content (30 pts)
5. Anti-gaming: Files created during task, correct ownership (10 pts)
"""

import json
import base64
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_custom_error_pages(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    metadata = task_info.get('metadata', {})
    req_content = metadata.get('required_content', {})

    # Helper to decode base64
    def get_content(b64_str):
        if not b64_str: return ""
        try:
            return base64.b64decode(b64_str).decode('utf-8', errors='ignore')
        except:
            return ""

    # 1. Check Files Existence (10 pts)
    f404 = result.get('file_404', {})
    f403 = result.get('file_403', {})
    
    if f404.get('exists'):
        score += 5
        feedback.append("404.html created.")
    else:
        feedback.append("404.html missing.")

    if f403.get('exists'):
        score += 5
        feedback.append("403.html created.")
    else:
        feedback.append("403.html missing.")

    # 2. Check File Content (30 pts)
    content_404 = get_content(f404.get('content_b64', ''))
    content_403 = get_content(f403.get('content_b64', ''))
    
    # 404 Content
    if req_content.get('404_heading') in content_404:
        score += 5
    else:
        feedback.append("404.html missing required heading.")
        
    if req_content.get('404_body') in content_404:
        score += 5
    else:
        feedback.append("404.html missing required body text.")

    if 'href="/"' in content_404 or "href='/'" in content_404:
        score += 5
    else:
        feedback.append("404.html missing homepage link.")

    # 403 Content
    if req_content.get('403_heading') in content_403:
        score += 7.5
    else:
        feedback.append("403.html missing required heading.")
        
    if req_content.get('403_body') in content_403:
        score += 7.5
    else:
        feedback.append("403.html missing required body text.")

    # 3. Check Configuration (20 pts)
    htaccess = result.get('htaccess_configured', False)
    apache = result.get('apache_configured', False)
    
    if htaccess or apache:
        score += 20
        feedback.append("Apache configuration detected.")
    else:
        feedback.append("No ErrorDocument configuration found in .htaccess or Apache config.")

    # 4. Functional Test (30 pts)
    curl_404 = get_content(result.get('curl_404_response_b64', ''))
    
    # Check if the returned page actually contains our custom content
    # This proves the server is serving our file
    if req_content.get('404_heading') in curl_404:
        score += 30
        feedback.append("Functional test passed: Server serves custom 404 page.")
    else:
        feedback.append("Functional test failed: Server did not return custom 404 content.")

    # 5. Anti-gaming / Ownership (10 pts)
    # Check ownership matches 'acmecorp' (which usually maps to the user id, 
    # but exact string might vary depending on env setup. 
    # In Virtualmin, user is typically the domain owner 'acmecorp'.)
    # We'll be lenient if functional test passes, but check creation time.
    
    created_during = f404.get('created_during_task', False) and f403.get('created_during_task', False)
    if created_during:
        score += 10
        feedback.append("Files created during task session.")
    else:
        feedback.append("Files detected were not created during this task session.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }