#!/usr/bin/env python3
"""
Verifier for outbreak_response_dataset task.

Scoring (100 points total):
- Data set created (MANDATORY) (30 pts)
- Name contains 'Cholera' and 'Kenema' (10 pts)
- Period type is 'Weekly' (15 pts)
- At least 1 data element assigned (15 pts)
- At least 3 data elements assigned (10 pts)
- Organisation unit assigned (15 pts)
- Org unit includes 'Kenema' (5 pts)

Pass threshold: 60 points
Mandatory: Data set creation
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_outbreak_response_dataset(traj, env_info, task_info):
    """Verify the creation and configuration of the outbreak data set."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/outbreak_response_dataset_result.json", temp_path)
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

        # Criterion 1: Data Set Created (Mandatory)
        found = result.get('found', False)
        if not found:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new Data Set named 'Cholera' found created during the task.",
                "subscores": {"found": False}
            }
        
        score += 30
        subscores["found"] = True
        feedback_parts.append("Data Set created (+30)")

        # Extract details
        name = result.get('name', '')
        period_type = result.get('periodType', '')
        de_count = result.get('data_element_count', 0)
        ou_count = result.get('org_unit_count', 0)
        ou_names = result.get('org_unit_names', [])

        # Criterion 2: Name check
        # Expect "Cholera Outbreak Surveillance - Kenema"
        if "cholera" in name.lower() and "kenema" in name.lower():
            score += 10
            subscores["name_correct"] = True
            feedback_parts.append(f"Name correct ('{name}') (+10)")
        else:
            subscores["name_correct"] = False
            feedback_parts.append(f"Name '{name}' missing keywords 'Cholera' or 'Kenema'")

        # Criterion 3: Period Type
        if period_type == "Weekly":
            score += 15
            subscores["period_weekly"] = True
            feedback_parts.append("Period type is Weekly (+15)")
        else:
            subscores["period_weekly"] = False
            feedback_parts.append(f"Incorrect Period Type: {period_type} (expected Weekly)")

        # Criterion 4 & 5: Data Elements
        if de_count >= 1:
            score += 15
            subscores["has_de"] = True
            feedback_parts.append(f"Has data elements ({de_count}) (+15)")
            
            if de_count >= 3:
                score += 10
                subscores["has_3_de"] = True
                feedback_parts.append("Has >= 3 data elements (+10)")
            else:
                subscores["has_3_de"] = False
                feedback_parts.append(f"Only {de_count} data elements (expected >= 3)")
        else:
            subscores["has_de"] = False
            subscores["has_3_de"] = False
            feedback_parts.append("No data elements assigned")

        # Criterion 6 & 7: Org Units
        if ou_count >= 1:
            score += 15
            subscores["has_ou"] = True
            
            # Check if Kenema is involved
            # Agent might assign 'Kenema District' or specific facilities like 'Kenema Govt Hospital'
            has_kenema = any("kenema" in ou.lower() for ou in ou_names)
            
            if has_kenema:
                score += 5
                subscores["ou_is_kenema"] = True
                feedback_parts.append("Assigned to Kenema org units (+20)")
            else:
                subscores["ou_is_kenema"] = False
                feedback_parts.append(f"Assigned to {ou_count} org units, but 'Kenema' not found in names (+15)")
        else:
            subscores["has_ou"] = False
            subscores["ou_is_kenema"] = False
            feedback_parts.append("No organisation units assigned")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": result
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}