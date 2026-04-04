#!/usr/bin/env python3
"""
Verifier for Form Complexity Count Audit task.

Scoring (100 points total):
1. CSV created/modified during task (20 pts)
2. CSV contains numeric custom extraction data (40 pts)
   - Indicates 'count()' or similar logic was used, not just text extraction
3. CSV contains data from correct domain (10 pts)
4. Summary text report exists with a number (10 pts)
5. Screaming Frog was running (20 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_form_complexity_count_audit(traj, env_info, task_info):
    """Verify form complexity task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Read result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # 1. SF Running (20 pts)
    if result.get("sf_running"):
        score += 20
        feedback_parts.append("Screaming Frog running")
    else:
        feedback_parts.append("Screaming Frog not running")

    # 2. CSV Created (20 pts)
    if result.get("csv_exists"):
        score += 20
        feedback_parts.append("CSV file created")
        
        # 3. Target Domain (10 pts)
        if result.get("target_domain_found"):
            score += 10
            feedback_parts.append("Target domain URLs found")
        else:
            feedback_parts.append("Target domain URLs NOT found in CSV")
            
        # 4. Numeric Extraction (40 pts)
        # This is the core skill check: did they use count() or just extract text?
        # Text extraction of inputs usually results in empty strings or HTML, not integers.
        if result.get("has_numeric_extraction"):
            score += 40
            col = result.get("extraction_column_name", "Unknown")
            feedback_parts.append(f"Valid numeric extraction found in column '{col}'")
        else:
            feedback_parts.append("No numeric extraction column found (Did you use count(//input)?)")
            
    else:
        feedback_parts.append("CSV file not found")

    # 5. Report (10 pts)
    if result.get("report_exists"):
        val = result.get("report_value")
        if val is not None:
            score += 10
            feedback_parts.append(f"Report contains value: {val}")
        else:
            score += 5 # Partial for file existing
            feedback_parts.append("Report empty or non-numeric")
    else:
        feedback_parts.append("Report file not found")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }