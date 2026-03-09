#!/usr/bin/env python3
"""
Verifier for data_element_groupset_dimension task.

Scoring (100 points total):
- Group "Malaria Testing" exists (15 pts)
- "Malaria Testing" has >= 2 elements (10 pts)
- Group "Malaria Treatment" exists (15 pts)
- "Malaria Treatment" has >= 2 elements (10 pts)
- Group Set "Malaria Programme Areas" exists (15 pts)
- Group Set contains >= 2 groups (10 pts)
- Group Set marked as data dimension (10 pts) [CRITICAL]
- Visualization created after task start (15 pts)

Pass threshold: 60 points
Mandatory: At least one group AND the group set must exist.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_data_element_groupset_dimension(traj, env_info, task_info):
    """Verify DHIS2 metadata setup for programme dimensions."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/task_result.json", temp_path)
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

        # 1. Check Malaria Testing Group (25 pts)
        if result.get('testing_group_found'):
            score += 15
            subscores['testing_group'] = True
            count = result.get('testing_group_element_count', 0)
            if count >= 2:
                score += 10
                feedback_parts.append(f"Testing group valid ({count} elements) (+25)")
            else:
                feedback_parts.append(f"Testing group found but has only {count} elements (+15)")
        else:
            subscores['testing_group'] = False
            feedback_parts.append("Malaria Testing group not found")

        # 2. Check Malaria Treatment Group (25 pts)
        if result.get('treatment_group_found'):
            score += 15
            subscores['treatment_group'] = True
            count = result.get('treatment_group_element_count', 0)
            if count >= 2:
                score += 10
                feedback_parts.append(f"Treatment group valid ({count} elements) (+25)")
            else:
                feedback_parts.append(f"Treatment group found but has only {count} elements (+15)")
        else:
            subscores['treatment_group'] = False
            feedback_parts.append("Malaria Treatment group not found")

        # 3. Check Group Set (35 pts)
        if result.get('groupset_found'):
            score += 15
            subscores['groupset'] = True
            
            # Check content
            count = result.get('groupset_group_count', 0)
            if count >= 2:
                score += 10
                feedback_parts.append("Group set contains groups (+10)")
            else:
                feedback_parts.append("Group set empty or incomplete")
            
            # Check dimension flag (Critical for analytics)
            if result.get('groupset_is_dimension'):
                score += 10
                feedback_parts.append("Group set configured as dimension (+10)")
            else:
                feedback_parts.append("Group set NOT marked as data dimension (cannot be used in analytics)")
        else:
            subscores['groupset'] = False
            feedback_parts.append("Malaria Programme Areas group set not found")

        # 4. Check Visualization (15 pts)
        if result.get('visualization_found'):
            score += 15
            feedback_parts.append(f"Visualization '{result.get('visualization_name')}' created (+15)")
        else:
            feedback_parts.append("No new visualization found")

        # Mandatory check: Must have done some metadata work
        has_group = result.get('testing_group_found') or result.get('treatment_group_found')
        has_set = result.get('groupset_found')
        
        if not (has_group and has_set):
            return {
                "passed": False,
                "score": score,
                "feedback": "FAILED: You must create at least one data element group AND the group set to pass. " + " | ".join(feedback_parts),
                "subscores": subscores
            }

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}