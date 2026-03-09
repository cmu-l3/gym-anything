#!/usr/bin/env python3
"""
Verifier for internal_link_equity_audit task.

Checks:
1. Valid Inlinks CSV export (Source/Destination/Anchor cols).
2. Report file existence and content (Counts, URLs, Recommendations).
3. Anti-gaming: Files must be created during task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_internal_link_equity_audit(traj, env_info, task_info):
    """
    Verify the Internal Link Equity Audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Read result file
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

    # --- Criteria 1: Inlinks CSV Export (45 pts) ---
    csv_found = result.get('inlinks_csv_found', False)
    has_anchor = result.get('has_anchor_col', False)
    domain_in_csv = result.get('target_domain_in_csv', False)
    row_count = result.get('inlinks_row_count', 0)

    if csv_found and has_anchor:
        score += 15
        feedback_parts.append("Correct 'Inlinks' CSV found (15/15)")
        
        if domain_in_csv:
            score += 10
            feedback_parts.append("CSV contains target domain data (10/10)")
        else:
            feedback_parts.append("CSV empty or wrong domain (0/10)")
            
        if row_count >= 50:
            score += 20
            feedback_parts.append(f"CSV has sufficient data ({row_count} rows) (20/20)")
        elif row_count > 0:
            score += 10
            feedback_parts.append(f"CSV has limited data ({row_count} rows) (10/20)")
        else:
            feedback_parts.append("CSV is empty (0/20)")
    else:
        feedback_parts.append("No valid 'All Inlinks' CSV found in exports (0/45). Did you use Bulk Export > Links > All Inlinks?")

    # --- Criteria 2: Analysis Report (45 pts) ---
    report_exists = result.get('report_exists', False)
    report_size = result.get('report_size_bytes', 0)
    has_numbers = result.get('report_has_numbers', False)
    has_urls = result.get('report_has_urls', False)
    has_anchor_term = result.get('report_has_anchor_term', False)
    has_recs = result.get('report_has_recommendations', False)

    if report_exists and report_size >= 500:
        score += 5
        feedback_parts.append("Report exists and has sufficient length (5/5)")
        
        if has_numbers:
            score += 10
            feedback_parts.append("Report contains numeric counts (10/10)")
        else:
            feedback_parts.append("Report missing numeric counts (0/10)")
            
        if has_urls:
            score += 10
            feedback_parts.append("Report references specific URLs (10/10)")
        else:
            feedback_parts.append("Report missing URL references (0/10)")
            
        if has_anchor_term:
            score += 10
            feedback_parts.append("Report covers anchor text (10/10)")
        else:
            feedback_parts.append("Report missing anchor text analysis (0/10)")
            
        if has_recs:
            score += 10
            feedback_parts.append("Report includes recommendations (10/10)")
        else:
            feedback_parts.append("Report missing recommendations (0/10)")
            
    elif report_exists:
        score += 5 # Credit for file existence
        feedback_parts.append(f"Report exists but is too short ({report_size} bytes) (5/45)")
    else:
        feedback_parts.append("Report file not found (0/45)")

    # --- Criteria 3: Screaming Frog State (10 pts) ---
    # We check if it ran at all (captured in result generation) or is running
    sf_running = result.get('sf_running', False)
    if sf_running or csv_found: # If CSV found, it must have run
        score += 10
        feedback_parts.append("Screaming Frog was used (10/10)")
    else:
        feedback_parts.append("Screaming Frog not detected (0/10)")

    passed = score >= 60 and csv_found and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }