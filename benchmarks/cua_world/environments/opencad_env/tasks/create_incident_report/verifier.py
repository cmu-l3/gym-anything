#!/usr/bin/env python3
"""Verifier for create_incident_report task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_incident_report(traj, env_info, task_info):
    """
    Verify that an incident report regarding 'Dragline 4' vandalism was created.
    
    Criteria:
    1. A new report record exists in the database (created during task).
    2. The title matches 'Vandalism - Dragline 4' (fuzzy match allowed).
    3. The narrative contains key details ('rear counterweight', 'Dragline 4', 'spray paint').
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expectations
    metadata = task_info.get('metadata', {})
    expected_title_kw = "Dragline 4"
    expected_narrative_kw = "rear counterweight"
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_incident_report_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check if report found
    if not result.get('report_found'):
        return {
            "passed": False,
            "score": 0, 
            "feedback": "No matching incident report found in database (checked for 'Dragline 4' in new records)."
        }
    
    score += 20
    feedback_parts.append("Report record found")
    
    report = result.get('report', {})
    title = report.get('title', '')
    narrative = report.get('narrative', '')
    
    # 2. Check Title (30 pts)
    if expected_title_kw.lower() in title.lower():
        score += 30
        feedback_parts.append(f"Title matched '{expected_title_kw}'")
    elif "vandalism" in title.lower():
        score += 15
        feedback_parts.append("Title contained 'Vandalism' but missing 'Dragline 4'")
    else:
        feedback_parts.append(f"Title mismatch: got '{title}'")

    # 3. Check Narrative (40 pts)
    # Keywords: "spray paint", "counterweight", "Dragline 4"
    keywords = ["spray paint", "counterweight", "dragline 4"]
    matched_kws = [k for k in keywords if k.lower() in narrative.lower()]
    
    if len(matched_kws) == 3:
        score += 40
        feedback_parts.append("Narrative fully accurate")
    elif len(matched_kws) > 0:
        partial_score = int(40 * (len(matched_kws) / 3))
        score += partial_score
        feedback_parts.append(f"Narrative partially accurate ({len(matched_kws)}/3 keywords)")
    else:
        feedback_parts.append("Narrative missing key details")

    # 4. Anti-gaming / New Record check (10 pts)
    # The export script already filters by ID > Baseline, so if report_found is true, 
    # it implies it's a new record. We double check counts just in case.
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    if current_count > initial_count:
        score += 10
        feedback_parts.append("New record count confirmed")
    else:
        # If ID check passed but count didn't increase (e.g. deletion + creation), we might warn
        # But usually ID check is sufficient for 'newness'.
        feedback_parts.append("Count did not increase (possibly replaced record)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }