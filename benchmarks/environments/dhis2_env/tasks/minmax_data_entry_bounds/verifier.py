#!/usr/bin/env python3
"""
Verifier for minmax_data_entry_bounds task.

Scoring (100 points total):
- Min-max records created for Bombali (Count increased) (30 pts) [MANDATORY]
- Significant number of records generated (> 20) (15 pts)
- Records linked to Immunization/EPI data elements (15 pts)
- Summary file created (15 pts)
- Summary file content check (substantive > 50 chars) (15 pts)
- Summary file mentions key terms (Bombali, Immunization) (10 pts)

Pass threshold: 60 points
Mandatory: New records must exist.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_minmax_config(traj, env_info, task_info):
    """Verify min-max values were generated and documented."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        # Load results from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/minmax_result.json", temp_path)
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

        score = 0
        feedback_parts = []
        
        # Parse data
        initial_count = int(result.get("initial_count", 0))
        current_count = int(result.get("current_count", 0))
        immunization_count = int(result.get("immunization_linked_count", 0))
        file_exists = result.get("file_exists", False)
        file_content = result.get("file_content", "").lower()
        file_length = int(result.get("file_length", 0))

        delta = current_count - initial_count

        # Criterion 1: Records created (Mandatory)
        if delta <= 0:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "No new min-max value boundaries were generated for Bombali district."
            }
        
        score += 30
        feedback_parts.append(f"Min-max records generated (+30, count: {delta})")

        # Criterion 2: Significant generation
        # If user only manually added 1, delta is small. Generation creates many.
        if delta >= 20:
            score += 15
            feedback_parts.append("Significant number of boundaries generated (+15)")
        else:
            feedback_parts.append(f"Few records generated ({delta}), expected batch generation")

        # Criterion 3: Immunization linkage
        # Verify the generated records correspond to the correct dataset
        if immunization_count >= 1:
            score += 15
            feedback_parts.append("Records linked to Immunization data elements (+15)")
        else:
            feedback_parts.append("Generated records do not appear to be for Immunization data")

        # Criterion 4: Summary file exists
        if file_exists:
            score += 15
            feedback_parts.append("Summary file created (+15)")
            
            # Criterion 5: Content substantive
            if file_length > 50:
                score += 15
                feedback_parts.append("Summary file content substantive (+15)")
            else:
                feedback_parts.append("Summary file content too short")

            # Criterion 6: Content keywords
            if "bombali" in file_content and ("immun" in file_content or "epi" in file_content):
                score += 10
                feedback_parts.append("Summary mentions correct district and dataset (+10)")
            else:
                feedback_parts.append("Summary missing keywords 'Bombali' or 'Immunization'")

        else:
            feedback_parts.append("Summary file not found")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}