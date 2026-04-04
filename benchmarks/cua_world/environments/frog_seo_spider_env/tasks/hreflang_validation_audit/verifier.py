#!/usr/bin/env python3
"""
Verifier for Hreflang Validation Audit task.

Verification Logic:
1. Hreflang CSV Detection (15 pts): File exists, created during task, identifiable as Hreflang data.
2. Internal CSV Detection (25 pts): File exists, created during task, contains crawler-test.com data, >20 rows.
3. Report Existence & Length (20 pts): Report file exists and is >300 chars.
4. Report Content (20 pts): Contains specific keywords (hreflang, language, error, etc.) and numeric counts.
5. Screaming Frog State (10 pts): App ran/is running.
6. Anti-gaming (10 pts): Files modified after task start.

Pass Threshold: 60/100 points
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hreflang_validation_audit(traj, env_info, task_info):
    """Verify the hreflang audit task."""
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_report_keywords', ["hreflang", "language"])
    min_report_length = metadata.get('min_report_length', 300)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Hreflang CSV (15 pts) ---
    if result.get('hreflang_csv_found', False):
        score += 15
        feedback_parts.append("Hreflang export found (15/15)")
    else:
        feedback_parts.append("Hreflang export NOT found (0/15)")

    # --- Criterion 2: Internal CSV (25 pts) ---
    internal_found = result.get('internal_csv_found', False)
    domain_match = result.get('internal_has_target_domain', False)
    row_count = result.get('internal_row_count', 0)
    
    if internal_found:
        if domain_match and row_count >= 20:
            score += 25
            feedback_parts.append(f"Internal crawl export valid ({row_count} rows) (25/25)")
        elif row_count > 0:
            score += 10
            feedback_parts.append(f"Internal export found but partial data/domain match issue (10/25)")
        else:
            score += 5
            feedback_parts.append("Internal export found but empty (5/25)")
    else:
        feedback_parts.append("Internal export NOT found (0/25)")

    # --- Criterion 3: Report Existence & Length (20 pts) ---
    report_found = result.get('report_found', False)
    report_size = result.get('report_size', 0)
    
    if report_found:
        if report_size >= min_report_length:
            score += 20
            feedback_parts.append(f"Report exists and length OK ({report_size} bytes) (20/20)")
        elif report_size > 50:
            score += 10
            feedback_parts.append(f"Report exists but too short ({report_size} < {min_report_length}) (10/20)")
        else:
            score += 5
            feedback_parts.append("Report file exists but is empty/near empty (5/20)")
    else:
        feedback_parts.append("Report file NOT found (0/20)")

    # --- Criterion 4: Report Content Analysis (20 pts) ---
    content_score = 0
    if report_found and result.get('report_content_snippet'):
        content = result.get('report_content_snippet', '').lower()
        
        # Check for keywords
        found_keywords = [k for k in required_keywords if k.lower() in content]
        if len(found_keywords) >= 3:
            content_score += 10
        elif len(found_keywords) > 0:
            content_score += 5
            
        # Check for numeric digits (counts)
        if re.search(r'\d+', content):
            content_score += 10
            
    score += content_score
    if content_score > 0:
        feedback_parts.append(f"Report content analysis passed (keywords: {len(found_keywords)}) ({content_score}/20)")
    else:
        feedback_parts.append("Report content analysis failed (no relevant keywords/counts) (0/20)")

    # --- Criterion 5: Screaming Frog State (10 pts) ---
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog is running (10/10)")
    else:
        feedback_parts.append("Screaming Frog not running (0/10)")

    # --- Criterion 6: Anti-gaming (Implicit in file checks but explicit points) (10 pts) ---
    # If we found files created after start time, we award these points
    if internal_found or result.get('hreflang_csv_found', False):
        score += 10
        feedback_parts.append("Files verified created during task (10/10)")
    else:
        feedback_parts.append("No new files created during task (0/10)")

    # Pass logic: Must have at least one CSV AND the report to be useful
    passed = (score >= 60) and internal_found and report_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }