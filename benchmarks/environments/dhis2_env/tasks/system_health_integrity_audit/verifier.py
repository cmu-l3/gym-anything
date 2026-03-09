#!/usr/bin/env python3
"""
Verifier for system_health_integrity_audit task.

Scoring (100 points total):
1. Analytics/Resource tables triggered (API verification) - 20 pts
2. Data Integrity checks triggered (API verification) - 25 pts
3. Report file exists and created during task - 20 pts
4. Report content contains substantive info (length > 100 chars) - 15 pts
5. Report content mentions key terms (version, integrity results) - 10 pts
6. Report content mentions specific violations (demonstrates reading results) - 10 pts

Pass threshold: 60 points
Mandatory: Analytics triggered OR Integrity run (proof of system interaction)
"""

import json
import tempfile
import os
import logging
import base64
import re

logger = logging.getLogger(__name__)

def verify_system_health_audit(traj, env_info, task_info):
    """Verify system health audit task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/system_health_audit_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    api_checks = result.get('api_checks', {})
    analytics_triggered = api_checks.get('analytics_triggered', False)
    integrity_triggered = api_checks.get('integrity_triggered', False)
    
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_created_during_task', False)
    report_b64 = result.get('report_content_b64', "")
    
    # Decode report content
    report_text = ""
    if report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
        except:
            report_text = ""

    # Scoring Criterion 1: Analytics Triggered (20 pts)
    if analytics_triggered:
        score += 20
        feedback_parts.append("Analytics tables generation triggered (+20)")
    else:
        feedback_parts.append("Analytics generation NOT detected via API")

    # Scoring Criterion 2: Integrity Triggered (25 pts)
    if integrity_triggered:
        score += 25
        feedback_parts.append("Data integrity check triggered (+25)")
    else:
        # Fallback: If report contains very specific integrity details, we might grant partial credit
        # assuming API log was missed, but for now we stick to strict API check.
        feedback_parts.append("Data integrity check NOT detected via API")

    # Scoring Criterion 3: Report File Exists & Fresh (20 pts)
    if report_exists and report_fresh:
        score += 20
        feedback_parts.append("Report file created during task (+20)")
    elif report_exists:
        score += 10
        feedback_parts.append("Report file exists but timestamp predates task start (+10)")
    else:
        feedback_parts.append("Report file not found")

    # Scoring Criterion 4: Report Substantive Content (15 pts)
    if len(report_text) > 100:
        score += 15
        feedback_parts.append("Report content length sufficient (+15)")
    elif len(report_text) > 20:
        score += 5
        feedback_parts.append("Report content very short (+5)")
    else:
        feedback_parts.append("Report content empty or missing")

    # Scoring Criterion 5: Key Terms (10 pts)
    # Check for version number or system terms
    sys_info = result.get('system_info', {})
    real_version = sys_info.get('version', '2.')
    
    keywords_found = 0
    text_lower = report_text.lower()
    
    if 'version' in text_lower or real_version in report_text:
        keywords_found += 1
    if 'integrity' in text_lower:
        keywords_found += 1
    if 'analytics' in text_lower or 'tables' in text_lower:
        keywords_found += 1
        
    if keywords_found >= 2:
        score += 10
        feedback_parts.append("Report mentions key system terms (+10)")
    elif keywords_found == 1:
        score += 5
        feedback_parts.append("Report mentions some terms (+5)")

    # Scoring Criterion 6: Integrity Findings (10 pts)
    # Look for words like "violation", "issue", "clean", "passed", "warning"
    findings_keywords = ["violation", "issue", "error", "warning", "passed", "clean", "no issues", "fixed"]
    if any(k in text_lower for k in findings_keywords):
        score += 10
        feedback_parts.append("Report references integrity findings (+10)")
    else:
        feedback_parts.append("Report does not clearly summarize integrity findings")

    # Mandatory Check: Did they do anything technical?
    # Must have triggered at least one system task OR produced a very convincing report
    interaction_detected = analytics_triggered or integrity_triggered or (score >= 45)
    
    if not interaction_detected:
        return {
            "passed": False,
            "score": score,
            "feedback": "FAILED: No system maintenance tasks detected in API logs and report is insufficient. " + " | ".join(feedback_parts)
        }

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }