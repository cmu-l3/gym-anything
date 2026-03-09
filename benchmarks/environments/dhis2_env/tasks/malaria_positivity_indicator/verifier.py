#!/usr/bin/env python3
"""
Verifier for malaria_positivity_indicator task.

Scoring (100 points total):
- Indicator created (25 pts) [MANDATORY]
- Indicator has valid numerator (15 pts)
- Indicator has valid denominator (15 pts)
- Indicator type is percentage (factor=100) (10 pts)
- Visualization created (20 pts)
- Data file exported (15 pts)

Pass threshold: 60 points
Mandatory: Indicator created
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_malaria_positivity_indicator(traj, env_info, task_info):
    """Verify that the indicator was configured correctly and visualized."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/malaria_positivity_indicator_result.json", temp_path)
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

        # Parse sections
        ind_check = result.get('indicator_check', {})
        viz_check = result.get('visualization_check', {})
        dl_check = result.get('download_check', {})

        # Criterion 1: Indicator Created (Mandatory)
        if not ind_check.get('indicator_created', False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new malaria-related indicator was created in DHIS2.",
                "subscores": {}
            }
        
        score += 25
        subscores["indicator_created"] = True
        feedback_parts.append("Indicator created (+25)")

        # Detailed Indicator Checks
        best_ind = ind_check.get('best_match', {})
        
        # Criterion 2: Numerator Valid
        numerator = best_ind.get('numerator', '')
        if numerator and numerator != '1':
            score += 15
            subscores["valid_numerator"] = True
            feedback_parts.append("Numerator configured (+15)")
        else:
            subscores["valid_numerator"] = False
            feedback_parts.append("Numerator empty or invalid")

        # Criterion 3: Denominator Valid
        denominator = best_ind.get('denominator', '')
        if denominator and denominator != '1':
            score += 15
            subscores["valid_denominator"] = True
            feedback_parts.append("Denominator configured (+15)")
        else:
            subscores["valid_denominator"] = False
            feedback_parts.append("Denominator empty or invalid")
            
        # Criterion 4: Percentage Type
        ind_type = best_ind.get('indicatorType', {})
        factor = ind_type.get('factor', 1)
        if factor == 100:
            score += 10
            subscores["percentage_type"] = True
            feedback_parts.append("Indicator type is Percentage/Factor 100 (+10)")
        else:
            subscores["percentage_type"] = False
            feedback_parts.append(f"Indicator factor is {factor}, expected 100")

        # Criterion 5: Visualization Created
        if viz_check.get('visualization_created', False):
            score += 20
            subscores["visualization_created"] = True
            feedback_parts.append("Visualization created (+20)")
        else:
            subscores["visualization_created"] = False
            feedback_parts.append("No visualization created")

        # Criterion 6: File Exported
        if dl_check.get('file_exported', False):
            score += 15
            subscores["file_exported"] = True
            feedback_parts.append("Data file exported (+15)")
        else:
            subscores["file_exported"] = False
            feedback_parts.append("No export file found")

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