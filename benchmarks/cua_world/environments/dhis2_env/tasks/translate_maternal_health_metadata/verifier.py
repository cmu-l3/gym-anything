#!/usr/bin/env python3
"""
Verifier for translate_maternal_health_metadata task.

Scoring (100 points total):
- At least 1 ANC data element translated to French (25 pts) [MANDATORY]
- At least 3 ANC data elements translated to French (20 pts)
- All 5 specified ANC data elements translated (15 pts)
- French translations contain correct medical term "CPN" (10 pts)
- Log file exists (15 pts)
- Log file has substantive content (15 pts)

Pass threshold: 60 points
Mandatory: At least 1 translation
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_metadata_translation(traj, env_info, task_info):
    """Verify that ANC data elements were translated to French."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result from container
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/translation_result.json", temp_path)
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
        
        # Check for errors in export
        if "error" in result:
             return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

        # Get counts from result
        translated_count = result.get("targets_translated_count", 0)
        cpn_count = result.get("cpn_term_used_count", 0)
        log_exists = result.get("log_file_exists", False)
        log_content = result.get("log_content_sample", "")
        
        # Target matching logic (double check specific elements if needed)
        elements_found = result.get("elements_found", [])
        
        # Define exact targets for stricter checking if needed, but the counts 
        # from the export script are usually sufficient given the filter logic there.
        # We will trust the export script's filtering of "targets"
        
        # Criterion 1: At least 1 translation (MANDATORY)
        if translated_count < 1:
             return {
                "passed": False,
                "score": 0,
                "feedback": "No French translations found for ANC data elements. You must translate at least one.",
                "subscores": {}
            }
        
        score += 25
        subscores["one_translation"] = True
        feedback_parts.append(f"Found {translated_count} translated elements (+25)")
        
        # Criterion 2: At least 3 translations
        if translated_count >= 3:
            score += 20
            subscores["three_translations"] = True
            feedback_parts.append(">= 3 translations (+20)")
        else:
            subscores["three_translations"] = False
            feedback_parts.append(f"Only {translated_count}/5 translations found")
            
        # Criterion 3: All 5 translations
        if translated_count >= 5:
            score += 15
            subscores["five_translations"] = True
            feedback_parts.append("All 5 targets translated (+15)")
        else:
            subscores["five_translations"] = False
            
        # Criterion 4: Correct terminology "CPN"
        if cpn_count >= 1:
            score += 10
            subscores["cpn_term"] = True
            feedback_parts.append("Correct terminology 'CPN' used (+10)")
        else:
            subscores["cpn_term"] = False
            feedback_parts.append("Translations missing 'CPN' (Consultation Prénatale)")
            
        # Criterion 5: Log file exists
        if log_exists:
            score += 15
            subscores["log_file"] = True
            feedback_parts.append("Log file created (+15)")
            
            # Criterion 6: Log content
            if len(log_content) > 50:  # Arbitrary threshold for "substantive"
                score += 15
                subscores["log_content"] = True
                feedback_parts.append("Log file has content (+15)")
            else:
                subscores["log_content"] = False
                feedback_parts.append("Log file is empty or too short")
        else:
            subscores["log_file"] = False
            subscores["log_content"] = False
            feedback_parts.append("Log file missing")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "translated_count": translated_count,
                "elements": elements_found
            }
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}