#!/usr/bin/env python3
"""
Verifier for Code Bloat Ratio Audit task.

Scoring Breakdown (100 points):
- App usage (10 pts)
- Data Export (50 pts total)
  - CSV exists and modified (10 pts)
  - Contains "Text to Code Ratio" column (20 pts)
  - Contains correct domain data (10 pts)
  - Has sufficient data rows (10 pts)
- Analysis Report (40 pts total)
  - Report file exists and modified (10 pts)
  - Non-trivial size (>100 bytes) (10 pts)
  - Contains numeric data (ratios) (10 pts)
  - Contains identified URLs (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_code_bloat_ratio_audit(traj, env_info, task_info):
    """Verify code bloat audit task."""
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

    # 1. App Usage (10 pts)
    # Check if SF was running at end or file was created (implying usage)
    if result.get('sf_running', False) or result.get('csv_exists', False):
        score += 10
        feedback.append("Screaming Frog usage detected (10/10)")
    else:
        feedback.append("Screaming Frog not running and no output found (0/10)")

    # 2. CSV Export Validation (50 pts)
    csv_exists = result.get('csv_exists', False)
    csv_mod = result.get('csv_modified', False)
    
    if csv_exists and csv_mod:
        score += 10
        feedback.append("CSV export found (10/10)")
        
        # Check Column
        if result.get('has_ratio_column', False):
            score += 20
            feedback.append("Correct 'Text to Code Ratio' column found (20/20)")
        else:
            feedback.append("Missing 'Text to Code Ratio' column in export (0/20)")
            
        # Check Domain
        if result.get('has_target_domain', False):
            score += 10
            feedback.append("Target domain data confirmed (10/10)")
        else:
            feedback.append("Target domain not found in export (0/10)")
            
        # Check Rows
        if result.get('row_count', 0) >= 20:
            score += 10
            feedback.append(f"Sufficient data rows found: {result['row_count']} (10/10)")
        else:
            feedback.append(f"Insufficient data rows: {result.get('row_count', 0)} (0/10)")
    else:
        feedback.append("No valid CSV export file found (0/50)")

    # 3. Report Validation (40 pts)
    rpt_exists = result.get('report_exists', False)
    rpt_mod = result.get('report_modified', False)
    
    if rpt_exists and rpt_mod:
        score += 10
        feedback.append("Analysis report found (10/10)")
        
        if result.get('report_size', 0) > 100:
            score += 10
            feedback.append("Report has meaningful length (10/10)")
        else:
            feedback.append("Report is too short (0/10)")
            
        if result.get('report_has_numbers', False):
            score += 10
            feedback.append("Report contains numeric analysis (10/10)")
        else:
            feedback.append("Report missing numeric values (0/10)")
            
        if result.get('report_has_urls', False):
            score += 10
            feedback.append("Report identifies specific URLs (10/10)")
        else:
            feedback.append("Report missing URL references (0/10)")
    else:
        feedback.append("No valid analysis report found (0/40)")

    # Final Check
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }