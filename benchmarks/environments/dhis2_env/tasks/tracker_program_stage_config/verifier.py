#!/usr/bin/env python3
"""
Verifier for tracker_program_stage_config task.

Scoring (100 points total):
- Data Element "Chlorhexidine Gel Applied" exists (20 pts)
- Data Element has correct Value Type (Yes/No / Boolean) (10 pts)
- Data Element is associated with a Child Programme (30 pts)
- Data Element is associated specifically with the "Birth" stage (20 pts)
- Data Element is configured as Compulsory (20 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_tracker_config(traj, env_info, task_info):
    """Verify DHIS2 Tracker configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/tracker_config_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        
        # 1. Data Element Created (20 pts)
        if result.get("de_exists"):
            score += 20
            feedback_parts.append("Data Element created (+20)")
        else:
            return {"passed": False, "score": 0, "feedback": "Data Element 'Chlorhexidine Gel Applied' not found"}

        # 2. Correct Value Type (10 pts)
        if result.get("de_correct_type"):
            score += 10
            feedback_parts.append("Value Type correct (+10)")
        else:
            actual_type = result.get("de_value_type", "Unknown")
            feedback_parts.append(f"Incorrect Value Type: {actual_type} (Expected Yes/No)")

        # 3. Associated with Program (30 pts)
        # 4. Associated with Stage (20 pts)
        if result.get("de_in_stage"):
            score += 50 # Implies both program and stage found
            feedback_parts.append("Added to 'Birth' stage in Child Programme (+50)")
        elif result.get("program_found"):
            # If program found but not stage, or not in stage
            if result.get("stage_found"):
                feedback_parts.append("Program and Stage found, but Data Element not added to Stage")
            else:
                feedback_parts.append("Program found, but 'Birth' stage not identified")
        else:
            feedback_parts.append("Child Programme not found or Data Element not associated")

        # 5. Compulsory (20 pts)
        if result.get("compulsory"):
            score += 20
            feedback_parts.append("Marked as Compulsory (+20)")
        else:
            feedback_parts.append("Not marked as Compulsory")

        # Bonus/Debug info
        if result.get("display_in_reports"):
            feedback_parts.append("(Display in Reports enabled)")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}