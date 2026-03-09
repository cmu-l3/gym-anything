#!/usr/bin/env python3
"""Verifier for Non-HTML Document Audit task.

Scoring (100 points total):
- Screaming Frog ran (10 pts)
- PDF Inventory CSV:
  - Exists and created/modified during task (20 pts)
  - Contains PDF URLs (20 pts)
  - Contains target domain URLs (10 pts)
  - Has data rows (10 pts)
- Summary Report:
  - Exists and created/modified during task (15 pts)
  - Contains numeric counts (15 pts)

Pass threshold: 75 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_non_html_document_audit(traj, env_info, task_info):
    """Verify non-html document audit task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    # Retrieve result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/non_html_audit_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

    # --- Criterion 1: App Running (10 pts) ---
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog running (10/10)")
    else:
        feedback_parts.append("Screaming Frog not running (0/10)")

    # --- Criterion 2: PDF Inventory CSV (60 pts total) ---
    csv_exists = result.get('csv_exists', False)
    csv_modified = result.get('csv_modified', False)
    
    if csv_exists and csv_modified:
        score += 20
        feedback_parts.append("PDF CSV created (20/20)")
        
        # Check content quality
        if result.get('csv_has_pdf', False):
            score += 20
            feedback_parts.append("CSV contains PDF links (20/20)")
        else:
            feedback_parts.append("CSV missing PDF indicators (0/20)")
            
        if result.get('csv_has_target_domain', False):
            score += 10
            feedback_parts.append("CSV contains correct domain (10/10)")
        else:
            feedback_parts.append("CSV missing target domain (0/10)")
            
        if result.get('csv_row_count', 0) > 0:
            score += 10
            feedback_parts.append(f"CSV has {result['csv_row_count']} rows (10/10)")
        else:
            feedback_parts.append("CSV is empty (0/10)")
            
    else:
        feedback_parts.append("PDF CSV not found or not created during task (0/60)")

    # --- Criterion 3: Summary Report (30 pts total) ---
    report_exists = result.get('report_exists', False)
    report_modified = result.get('report_modified', False)
    
    if report_exists and report_modified:
        score += 15
        feedback_parts.append("Summary report created (15/15)")
        
        if result.get('report_has_count', False):
            score += 15
            feedback_parts.append("Report contains counts (15/15)")
        else:
            feedback_parts.append("Report missing numeric counts (0/15)")
    else:
        feedback_parts.append("Summary report not found (0/30)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }