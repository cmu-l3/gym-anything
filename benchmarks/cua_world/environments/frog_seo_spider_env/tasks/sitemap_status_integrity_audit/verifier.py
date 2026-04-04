#!/usr/bin/env python3
"""
Verifier for Sitemap Status Integrity Audit.

Scoring Breakdown (100 pts total):
1. CSV Export (50 pts):
   - File exists and created during task: 20 pts
   - Contains 'Status Code' column: 10 pts
   - Contains the target 404 URL (proof of crawl): 20 pts

2. Remediation Report (40 pts):
   - File exists and created during task: 10 pts
   - Mentions "404": 10 pts
   - Identifies the specific 404 URL: 20 pts

3. Screaming Frog State (10 pts):
   - Application was running: 10 pts

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sitemap_audit(traj, env_info, task_info):
    """Verify sitemap audit task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
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

    # 1. Verify CSV Export (50 pts)
    export_exists = result.get('export_exists', False)
    export_fresh = result.get('export_fresh', False)
    export_valid = result.get('export_valid_cols', False)
    export_target = result.get('export_found_target', False)
    
    if export_exists and export_fresh:
        score += 20
        feedback_parts.append("CSV exported successfully (20/20)")
        
        if export_valid:
            score += 10
            feedback_parts.append("CSV structure valid (10/10)")
        else:
            feedback_parts.append("CSV missing Status Code column (0/10)")
            
        if export_target:
            score += 20
            feedback_parts.append("CSV contains crawled 404 URL (20/20)")
        else:
            feedback_parts.append("CSV missing target 404 URL - did you crawl the sitemap? (0/20)")
    else:
        feedback_parts.append("No new CSV export found (0/50)")

    # 2. Verify Remediation Report (40 pts)
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_fresh', False)
    report_404 = result.get('report_mentions_404', False)
    report_url = result.get('report_identifies_url', False)
    
    if report_exists and report_fresh:
        score += 10
        feedback_parts.append("Report created (10/10)")
        
        if report_404:
            score += 10
            feedback_parts.append("Report identifies 404 errors (10/10)")
        else:
            feedback_parts.append("Report does not mention 404s (0/10)")
            
        if report_url:
            score += 20
            feedback_parts.append("Report identifies specific broken URL (20/20)")
        else:
            feedback_parts.append("Report missing specific broken URL (0/20)")
    else:
        feedback_parts.append("No new report file found (0/40)")

    # 3. App State (10 pts)
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog running (10/10)")
    else:
        feedback_parts.append("Screaming Frog not running (0/10)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }