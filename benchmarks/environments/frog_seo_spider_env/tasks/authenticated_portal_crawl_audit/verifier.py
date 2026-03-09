#!/usr/bin/env python3
"""
Verifier for Authenticated Portal Crawl Audit task.

Verifies that the agent successfully configured authentication by checking
if the crawler discovered URLs only visible to logged-in users (specifically /logout/).

Criteria:
1. Export CSV created during task (20 pts)
2. Export contains data from target domain (20 pts)
3. PROOF OF AUTHENTICATION: Export contains '/logout/' URL (50 pts)
4. Report file created (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_authenticated_portal_crawl_audit(traj, env_info, task_info):
    """Verify authenticated crawl task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Retrieve JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 1. Export CSV Created (20 pts)
    if result.get('csv_found', False):
        score += 20
        feedback_parts.append("Export CSV found (20/20)")
    else:
        feedback_parts.append("No export CSV found (0/20)")

    # 2. Domain Match (20 pts)
    if result.get('domain_match', False):
        score += 20
        feedback_parts.append("Target domain confirmed (20/20)")
    else:
        feedback_parts.append("Target domain data missing (0/20)")

    # 3. Authentication Verification (50 pts) - CRITICAL
    # The /logout/ link is strictly hidden for unauthenticated users
    has_logout = result.get('has_logout_link', False)
    
    # Double check by reading the CSV content if available
    if not has_logout and result.get('csv_found', False):
        try:
            temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
            copy_from_env("/tmp/auth_crawl_export.csv", temp_csv.name)
            with open(temp_csv.name, 'r', errors='ignore') as f:
                content = f.read()
                if '/logout/' in content:
                    has_logout = True
            os.unlink(temp_csv.name)
        except Exception:
            pass

    if has_logout:
        score += 50
        feedback_parts.append("Authentication SUCCESS: '/logout/' link found (50/50)")
    else:
        feedback_parts.append("Authentication FAILED: '/logout/' link NOT found. Crawler likely saw public pages only. (0/50)")

    # 4. Report Created (10 pts)
    if result.get('report_found', False):
        score += 10
        feedback_parts.append("Report file found (10/10)")
    else:
        feedback_parts.append("Report file missing (0/10)")

    # Final Pass/Fail
    # Must have authentication success to pass
    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }