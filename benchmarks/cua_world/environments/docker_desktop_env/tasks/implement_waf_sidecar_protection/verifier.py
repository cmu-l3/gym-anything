#!/usr/bin/env python3
"""
Verifier for implement_waf_sidecar_protection task.

Scoring Criteria:
1. Legitimate traffic passes (200 OK) - 30 pts
2. SQL Injection blocked (403 Forbidden) - 30 pts
3. XSS blocked (403 Forbidden) - 10 pts
4. Vulnerable app NOT directly exposed - 20 pts
5. WAF container running - 10 pts

Pass Threshold: 80 points
"""

import json
import os
import tempfile

def verify_waf_protection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    feedback_parts = []
    
    # 1. Check Legitimate Traffic (30 pts)
    legit_status = result.get("legit_status", "000")
    if legit_status == "200":
        score += 30
        feedback_parts.append("Legitimate traffic allowed (200 OK)")
    else:
        feedback_parts.append(f"Legitimate traffic failed (Got {legit_status})")

    # 2. Check SQL Injection Block (30 pts)
    sqli_status = result.get("sqli_status", "000")
    if sqli_status == "403":
        score += 30
        feedback_parts.append("SQL Injection blocked (403 Forbidden)")
    elif sqli_status == "200":
        feedback_parts.append("SQL Injection NOT blocked (200 OK - Still Vulnerable)")
    else:
        feedback_parts.append(f"SQL Injection unexpected status ({sqli_status})")

    # 3. Check XSS Block (10 pts)
    xss_status = result.get("xss_status", "000")
    if xss_status == "403":
        score += 10
        feedback_parts.append("XSS blocked (403 Forbidden)")
    else:
        feedback_parts.append(f"XSS not blocked (Got {xss_status})")

    # 4. Check Direct Exposure (20 pts)
    app_exposed = result.get("app_has_direct_ports", True)
    if not app_exposed:
        score += 20
        feedback_parts.append("App container correctly isolated (no direct ports)")
    else:
        feedback_parts.append("App container still has direct port mapping (Insecure)")

    # 5. Check WAF Container (10 pts)
    waf_running = result.get("waf_running", False)
    if waf_running:
        score += 10
        feedback_parts.append("WAF container is running")
    else:
        feedback_parts.append("WAF container not detected")

    # Pass logic: Must have functional app, blocked attacks, and proper architecture
    # Threshold 80 allows missing XSS check or WAF detection if functionality is perfect
    # But essentially requires SQLi block + Legit Pass + Isolation
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }