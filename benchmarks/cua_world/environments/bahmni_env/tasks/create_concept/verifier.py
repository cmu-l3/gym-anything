#!/usr/bin/env python3
"""
Verifier for Create Concept task in OpenMRS.

Checks:
1. Concept "Patient Satisfaction Score" exists.
2. Datatype is Numeric.
3. Class is Misc.
4. Absolute Low is 1, High is 10.
5. Units are set.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_concept(traj, env_info, task_info):
    """
    Verify the created OpenMRS concept properties.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Patient Satisfaction Score")
    expected_datatype = metadata.get('expected_datatype', "Numeric")
    expected_class = metadata.get('expected_class', "Misc")
    expected_low = metadata.get('expected_low', 1.0)
    expected_high = metadata.get('expected_high', 10.0)
    
    try:
        # Copy result file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

        # Parse result
        concept_found = result.get('concept_found', False)
        data = result.get('concept_data', {})
        
        feedback_parts = []
        score = 0
        
        # CRITERION 1: Concept Exists (25 pts)
        if concept_found and not data.get('retired', False):
            score += 25
            feedback_parts.append(f"Concept '{expected_name}' created")
        else:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Concept '{expected_name}' not found or is retired",
                "details": {"found": False}
            }

        # CRITERION 2: Datatype (15 pts)
        # OpenMRS API might return "Numeric" or "N/A" depending on version/locale, but usually "Numeric"
        actual_datatype = data.get('datatype', '')
        if expected_datatype.lower() in actual_datatype.lower():
            score += 15
            feedback_parts.append("Datatype correct (Numeric)")
        else:
            feedback_parts.append(f"Datatype mismatch: expected {expected_datatype}, got {actual_datatype}")

        # CRITERION 3: Class (15 pts)
        actual_class = data.get('concept_class', '')
        if expected_class.lower() in actual_class.lower():
            score += 15
            feedback_parts.append("Class correct (Misc)")
        else:
            feedback_parts.append(f"Class mismatch: expected {expected_class}, got {actual_class}")

        # CRITERION 4: Numeric Ranges (20 pts total)
        # Low (10 pts)
        actual_low = data.get('low_absolute')
        # Handle string/float/int comparisons safely
        try:
            if actual_low is not None and float(actual_low) == float(expected_low):
                score += 10
                feedback_parts.append(f"Low absolute correct ({expected_low})")
            else:
                feedback_parts.append(f"Low absolute incorrect: got {actual_low}")
        except (ValueError, TypeError):
             feedback_parts.append(f"Low absolute invalid: {actual_low}")

        # High (10 pts)
        actual_hi = data.get('hi_absolute')
        try:
            if actual_hi is not None and float(actual_hi) == float(expected_high):
                score += 10
                feedback_parts.append(f"High absolute correct ({expected_high})")
            else:
                feedback_parts.append(f"High absolute incorrect: got {actual_hi}")
        except (ValueError, TypeError):
             feedback_parts.append(f"High absolute invalid: {actual_hi}")

        # CRITERION 5: Units (5 pts)
        if data.get('units'):
            score += 5
            feedback_parts.append(f"Units set ({data.get('units')})")
        else:
            feedback_parts.append("Units not set")

        # CRITERION 6: Short Name/Description (10 pts)
        # Bonus for completeness
        short_names = data.get('short_names', [])
        description = data.get('description', '')
        
        has_short_name = any('satisfaction' in s.lower() for s in short_names)
        has_desc = len(description) > 5
        
        if has_short_name or has_desc:
            score += 10
            feedback_parts.append("Metadata (Short name/Description) provided")
        else:
            feedback_parts.append("Missing short name or description")

        passed = score >= 55  # Threshold from design
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": data
        }

    except Exception as e:
        logger.exception("Verification failed with exception")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}