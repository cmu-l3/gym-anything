#!/usr/bin/env python3
"""
Verifier for boolean_intersection_common task.

Scoring Criteria:
1. File exists and created during task (20 pts)
2. File is a valid FreeCAD document (20 pts)
3. Boolean Common operation performed (30 pts)
4. Final intersection volume is correct (~80,000 mm³) (30 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_boolean_intersection(traj, env_info, task_info):
    """
    Verify the FreeCAD boolean intersection task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_volume = metadata.get('expected_volume', 80000)
    tolerance = metadata.get('volume_tolerance', 0.05) # 5%

    score = 0
    feedback_parts = []
    
    # Create temp file for result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json_name = temp_json.name
    temp_json.close()

    try:
        # Copy result JSON from container
        copy_from_env("/tmp/task_result.json", temp_json_name)
        
        with open(temp_json_name, 'r') as f:
            result = json.load(f)
            
        analysis = result.get('analysis', {})
        
        # Criterion 1: File Existence & Anti-Gaming (20 pts)
        if result.get('file_exists') and result.get('file_created_during_task'):
            score += 20
            feedback_parts.append("File created successfully")
        elif result.get('file_exists'):
            score += 10
            feedback_parts.append("File exists but timestamp issue (modified before task start?)")
        else:
            return {"passed": False, "score": 0, "feedback": "Output file not found"}

        # Criterion 2: Valid FreeCAD Document (20 pts)
        if analysis.get('valid_doc'):
            score += 20
            feedback_parts.append("Valid FreeCAD document")
        else:
            return {"passed": False, "score": score, "feedback": "File is not a valid FreeCAD document"}

        # Criterion 3: Operation Check (30 pts)
        # Check if Common object exists OR at least enough boxes were made
        if analysis.get('common_found'):
            score += 30
            feedback_parts.append("Boolean Common operation found")
        elif analysis.get('box_count', 0) >= 2:
            score += 10
            feedback_parts.append("Boxes found, but Boolean Common not detected")
        else:
            feedback_parts.append("Insufficient objects found")

        # Criterion 4: Volume Accuracy (30 pts)
        actual_volume = analysis.get('final_volume', 0.0)
        
        if actual_volume > 0:
            diff_ratio = abs(actual_volume - expected_volume) / expected_volume
            if diff_ratio <= tolerance:
                score += 30
                feedback_parts.append(f"Volume correct ({actual_volume:.1f} mm³)")
            elif diff_ratio <= 0.2:
                # Partial credit for close volume
                score += 15
                feedback_parts.append(f"Volume incorrect but close ({actual_volume:.1f} mm³, expected {expected_volume})")
            else:
                feedback_parts.append(f"Volume incorrect ({actual_volume:.1f} mm³)")
        else:
            feedback_parts.append("No solid volume detected")

        # Pass Check
        passed = score >= 80
        feedback = ". ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed due to internal error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_json_name):
            os.unlink(temp_json_name)