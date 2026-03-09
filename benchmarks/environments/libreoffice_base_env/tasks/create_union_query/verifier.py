#!/usr/bin/env python3
"""
Verifier for create_union_query task.

Verification Strategy:
1. Programmatic Check (80 points):
   - Analyzes the ODB file to find the saved query "AllContacts".
   - checks if it uses UNION.
   - Executes the agent's SQL against the ground truth SQLite database to verify row counts (should be 67).
   - Checks for presence of the "ContactType" distinction.
2. VLM Verification (20 points):
   - Uses trajectory frames to verify the agent actually performed work in the SQL editor or Query Design view.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_union_query(traj, env_info, task_info):
    """
    Verify the agent created the UNION query correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    max_score = 100
    
    # ------------------------------------------------------------------
    # 1. Programmatic Verification (from export_result.sh output)
    # ------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Check 1: File saved (10 pts)
    if result_data.get('file_modified', False):
        score += 10
        feedback_parts.append("Database saved successfully")
    else:
        feedback_parts.append("Database NOT saved (timestamp check failed)")

    # Check 2: Query exists (20 pts)
    if result_data.get('query_found', False):
        score += 20
        feedback_parts.append(f"Query '{result_data.get('query_name')}' found")
    else:
        feedback_parts.append("Query 'AllContacts' NOT found")
        # Critical fail if query missing
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # Check 3: Uses UNION (10 pts)
    if result_data.get('uses_union', False):
        score += 10
        feedback_parts.append("SQL uses UNION operator")
    else:
        feedback_parts.append("SQL does NOT use UNION operator")

    # Check 4: Contact Type Logic (10 pts)
    if result_data.get('has_contact_type', False):
        score += 10
        feedback_parts.append("ContactType logic detected in SQL")
    else:
        feedback_parts.append("ContactType literal column missing from SQL")

    # Check 5: Execution Result / Row Count (30 pts)
    row_count = result_data.get('row_count', 0)
    expected_rows = 67
    
    if row_count == expected_rows:
        score += 30
        feedback_parts.append(f"Query returns correct row count ({row_count})")
    elif row_count > 0:
        # Partial credit if it returns something but count is wrong
        score += 10
        feedback_parts.append(f"Query returns incorrect row count ({row_count}, expected {expected_rows})")
    else:
        feedback_parts.append(f"Query execution failed or returned 0 rows. Error: {result_data.get('error', 'unknown')}")

    # ------------------------------------------------------------------
    # 2. VLM Trajectory Verification (20 pts)
    # ------------------------------------------------------------------
    # Check if agent was interacting with SQL View
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of a user working in LibreOffice Base.
        Does the user open the "SQL View" or "Query Design" window?
        Are they typing SQL commands (like SELECT, UNION) or interacting with tables?
        
        Return JSON: {"working_in_query_editor": true/false, "confidence": "high/med/low"}
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=prompt)
            vlm_parsed = vlm_response.get('parsed', {})
            
            if vlm_parsed.get('working_in_query_editor', False):
                score += 20
                feedback_parts.append("VLM confirms work in Query Editor")
            else:
                feedback_parts.append("VLM did not observe SQL editing")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            # Fallback points if programmatic was perfect
            if score >= 80: 
                score += 20
                feedback_parts.append("VLM skipped (programmatic pass)")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }