#!/usr/bin/env python3
"""
Verifier for the fix_http_api_client task.

Analyzes the exported source code from the container to ensure
all 5 critical bugs were correctly fixed by the agent.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_http_api_client(traj, env_info, task_info):
    """
    Verify the HTTP API client bug fixes.
    
    Expected Fixes:
    1. url_builder.py: Uses urlencode instead of string interpolation.
    2. retry.py: Uses ** or pow() for backoff, and doesn't retry on 4xx.
    3. http_client.py: timeout=(connect_timeout, read_timeout).
    4. auth.py: Bearer without base64, ApiKey uses X-API-Key.
    5. pagination.py: page <= total_pages (or similar), checks for cursor Is None.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/api_client_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Anti-gaming check
    if not result.get("file_modified_during_task", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No files were modified during the task execution. Agent did nothing."
        }

    files = result.get("files", {})
    score = 0
    feedback = []

    # 1. Check URL Builder (20 points)
    url_src = files.get("client/url_builder.py", "")
    has_urlencode = re.search(r'urllib\.parse\.urlencode', url_src)
    has_quote = re.search(r'urllib\.parse\.quote', url_src)
    still_has_interpolation = re.search(r'f"\{k\}=\s*\{v\}"', url_src)
    
    if (has_urlencode or has_quote) and not still_has_interpolation:
        score += 20
        feedback.append("[+] url_builder.py: Properly uses urlencode/quote (20/20)")
    elif still_has_interpolation:
        feedback.append("[-] url_builder.py: Still uses naive string interpolation for parameters (0/20)")
    else:
        # Partial fix if they manually did replace(" ", "%20") etc, but urlencode is the standard
        feedback.append("[-] url_builder.py: Could not verify URL encoding fix (0/20)")

    # 2. Check Retry Logic (20 points)
    retry_src = files.get("client/retry.py", "")
    has_exponential = re.search(r'\*\*\s*attempt', retry_src) or re.search(r'pow\(', retry_src) or re.search(r'math\.pow\(', retry_src)
    still_has_linear = re.search(r'base_delay\s*\*\s*attempt', retry_src)
    
    # Verify 400s are excluded. Original was `if status_code >= 400: return True`
    still_retries_400 = re.search(r'if\s+status_code\s*>=\s*400:\s*return\s+True', retry_src)
    retries_500s_only = re.search(r'>=\s*500', retry_src) or re.search(r'status_code\s*in\s*\[429,\s*500', retry_src) or re.search(r'status_code\s*==\s*429', retry_src)

    if has_exponential and not still_has_linear and not still_retries_400:
        score += 20
        feedback.append("[+] retry.py: Exponential backoff and status codes fixed (20/20)")
    elif has_exponential and not still_has_linear:
        score += 10
        feedback.append("[~] retry.py: Exponential backoff fixed, but status codes still incorrect (10/20)")
    elif not still_retries_400 and retries_500s_only:
        score += 10
        feedback.append("[~] retry.py: Status codes fixed, but backoff still linear (10/20)")
    else:
        feedback.append("[-] retry.py: Bugs not fixed (0/20)")

    # 3. Check Timeout Tuple (20 points)
    http_src = files.get("client/http_client.py", "")
    # Original: timeout = (self.read_timeout, self.connect_timeout)
    # Fixed: timeout = (self.connect_timeout, self.read_timeout)
    fixed_timeout = re.search(r'timeout\s*=\s*\(\s*self\.connect_timeout\s*,\s*self\.read_timeout\s*\)', http_src)
    
    if fixed_timeout:
        score += 20
        feedback.append("[+] http_client.py: Timeout tuple order corrected (20/20)")
    else:
        feedback.append("[-] http_client.py: Timeout tuple order still swapped or missing (0/20)")

    # 4. Check Auth Logic (20 points)
    auth_src = files.get("client/auth.py", "")
    still_base64 = re.search(r'base64\.b64encode', auth_src)
    has_xapikey = re.search(r"['\"]X-API-Key['\"]", auth_src, re.IGNORECASE)
    
    if not still_base64 and has_xapikey:
        score += 20
        feedback.append("[+] auth.py: Bearer token and X-API-Key headers fixed (20/20)")
    elif not still_base64:
        score += 10
        feedback.append("[~] auth.py: Bearer token fixed, but API Key header still incorrect (10/20)")
    elif has_xapikey:
        score += 10
        feedback.append("[~] auth.py: API Key header fixed, but Bearer token still uses base64 (10/20)")
    else:
        feedback.append("[-] auth.py: Auth logic bugs remain (0/20)")

    # 5. Check Pagination Logic (20 points)
    pag_src = files.get("client/pagination.py", "")
    page_fixed = re.search(r'while\s+page\s*<=\s*total_pages', pag_src) or re.search(r'while\s+page\s*<\s*total_pages\s*\+\s*1', pag_src)
    cursor_fixed = re.search(r'if\s+not\s+cursor', pag_src) or re.search(r'if\s+cursor\s+is\s+None', pag_src) or re.search(r'if\s+cursor\s*==\s*None', pag_src)

    if page_fixed and cursor_fixed:
        score += 20
        feedback.append("[+] pagination.py: Page loop and cursor termination fixed (20/20)")
    elif page_fixed:
        score += 10
        feedback.append("[~] pagination.py: Page loop fixed, but cursor infinite loop remains (10/20)")
    elif cursor_fixed:
        score += 10
        feedback.append("[~] pagination.py: Cursor termination fixed, but page loop misses last page (10/20)")
    else:
        feedback.append("[-] pagination.py: Pagination bugs remain (0/20)")

    # Final tally
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "pytest_output": result.get("pytest_output", "")
        }
    }