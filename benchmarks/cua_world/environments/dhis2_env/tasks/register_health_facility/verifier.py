#!/usr/bin/env python3
"""
Verifier for register_health_facility task.

Scoring (100 points total):
- Organisation unit "Makonthi MCHP" exists (30 pts) [MANDATORY]
- Opening date is 2024-01-15 (10 pts)
- Short name is "Makonthi MCHP" (10 pts)
- Parent is within Bombali district hierarchy (20 pts)
- At least one org unit group assigned (20 pts)
- Created after task start time (10 pts)

Pass threshold: 60 points
Mandatory: Org unit must exist
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_register_health_facility(traj, env_info, task_info):
    """Verify the new health facility was registered correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/register_health_facility_result.json", temp_path)
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
        subscores = {}

        ou_data = result.get('ou_data', {})
        found = ou_data.get('found', False)

        # Criterion 1: Org Unit Exists (Mandatory)
        if not found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Organisation Unit 'Makonthi MCHP' was not found in DHIS2.",
                "subscores": {}
            }

        score += 30
        subscores["exists"] = True
        feedback_parts.append("Organisation unit created (+30)")

        # Criterion 2: Opening Date
        expected_date = "2024-01-15"
        # DHIS2 sometimes returns full timestamps for dates, handle basic ISO
        actual_date = ou_data.get('openingDate', '')[:10] 
        
        if actual_date == expected_date:
            score += 10
            subscores["opening_date"] = True
            feedback_parts.append(f"Opening date correct: {actual_date} (+10)")
        else:
            subscores["opening_date"] = False
            feedback_parts.append(f"Opening date incorrect: got {actual_date}, expected {expected_date}")

        # Criterion 3: Short Name
        expected_short = "Makonthi MCHP"
        actual_short = ou_data.get('shortName', '')
        
        if actual_short == expected_short:
            score += 10
            subscores["short_name"] = True
            feedback_parts.append("Short name correct (+10)")
        else:
            subscores["short_name"] = False
            feedback_parts.append(f"Short name incorrect: got '{actual_short}'")

        # Criterion 4: Hierarchy / Location (Bombali)
        is_under_bombali = ou_data.get('is_under_bombali', False)
        parent_name = ou_data.get('parent_name', 'Unknown')
        
        if is_under_bombali:
            score += 20
            subscores["hierarchy"] = True
            feedback_parts.append(f"Correctly placed under Bombali (Parent: {parent_name}) (+20)")
        else:
            subscores["hierarchy"] = False
            feedback_parts.append(f"Incorrect location. Parent is '{parent_name}', expected a chiefdom under Bombali.")

        # Criterion 5: Group Assignment
        group_count = ou_data.get('group_count', 0)
        groups = ou_data.get('groups', [])
        
        if group_count >= 1:
            score += 20
            subscores["groups"] = True
            feedback_parts.append(f"Assigned to {group_count} group(s): {', '.join(groups)} (+20)")
        else:
            subscores["groups"] = False
            feedback_parts.append("No organisation unit groups assigned.")

        # Criterion 6: Created After Task Start (Anti-gaming)
        created_str = ou_data.get('created', '')
        task_start_str = result.get('task_start_iso', '')
        
        created_after = False
        try:
            # Parse simplified ISO strings (YYYY-MM-DDTHH:MM:SS)
            created_dt = datetime.fromisoformat(created_str.replace('Z', '+00:00'))
            start_dt = datetime.fromisoformat(task_start_str.replace('Z', '+00:00'))
            if created_dt >= start_dt:
                created_after = True
        except Exception:
            # If parsing fails, lenient fallback if timestamp exists
            if created_str: 
                created_after = True

        if created_after:
            score += 10
            subscores["timestamp"] = True
            feedback_parts.append("Created during task session (+10)")
        else:
            subscores["timestamp"] = False
            feedback_parts.append("Creation time verification failed (might be pre-existing)")

        # Optional: Bonus/Debug check for coordinates (not scored strictly in this ruberic but good for feedback)
        geom = ou_data.get('geometry')
        if geom:
             feedback_parts.append("Coordinates found (Good)")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}