#!/usr/bin/env python3
"""Verifier for Non-Standard Redirect Audit task.

Scoring (100 points total):
- Crawl Completion (10 pts): SF running/Window title check
- Meta Refresh Export (30 pts): File exists, correct domain, >0 rows
- JS Redirect Export (30 pts): File exists, correct domain, >0 rows
- Remediation Report (30 pts): Exists, sufficient size, contains keywords

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_non_standard_redirect_audit(traj, env_info, task_info):
    """Verify non-standard redirect audit task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # --- Criterion 1: Crawl Completion (10 pts) ---
    sf_running = result.get('sf_running', False)
    window_info = result.get('window_info', '').lower()
    
    # If file content suggests successful crawl, we also count it
    meta_valid = result.get('meta_refresh', {}).get('valid_content', False)
    
    if sf_running or 'crawler-test' in window_info or meta_valid:
        score += 10
        feedback_parts.append("Crawl/App detected (10/10)")
    else:
        feedback_parts.append("App not detected (0/10)")

    # --- Criterion 2: Meta Refresh Export (30 pts) ---
    meta = result.get('meta_refresh', {})
    if meta.get('exists', False):
        if meta.get('valid_content', False) and meta.get('row_count', 0) > 0:
            score += 30
            feedback_parts.append(f"Meta Refresh CSV valid ({meta.get('row_count')} rows) (30/30)")
        else:
            score += 15
            feedback_parts.append("Meta Refresh CSV exists but empty/invalid domain (15/30)")
    else:
        feedback_parts.append("Meta Refresh CSV missing (0/30)")

    # --- Criterion 3: JS Redirect Export (30 pts) ---
    js = result.get('js_redirect', {})
    if js.get('exists', False):
        if js.get('valid_content', False) and js.get('row_count', 0) > 0:
            score += 30
            feedback_parts.append(f"JS Redirect CSV valid ({js.get('row_count')} rows) (30/30)")
        else:
            score += 15
            feedback_parts.append("JS Redirect CSV exists but empty/invalid domain (15/30)")
    else:
        feedback_parts.append("JS Redirect CSV missing (0/30)")

    # --- Criterion 4: Remediation Report (30 pts) ---
    rep = result.get('report', {})
    if rep.get('exists', False):
        if rep.get('valid_content', False):
            score += 30
            feedback_parts.append("Report valid (keywords found) (30/30)")
        else:
            # Partial credit for just existing with content
            if rep.get('size_bytes', 0) > 10:
                score += 15
                feedback_parts.append("Report exists but missing keywords (15/30)")
            else:
                score += 5
                feedback_parts.append("Report empty (5/30)")
    else:
        feedback_parts.append("Report missing (0/30)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }