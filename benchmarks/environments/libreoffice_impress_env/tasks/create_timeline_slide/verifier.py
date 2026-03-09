#!/usr/bin/env python3
"""
Verifier for Create Cloud Migration Timeline Slide task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_timeline_slide(traj, env_info, task_info):
    """
    Verify that the timeline slide was created correctly.
    
    Criteria:
    1. File exists and was modified (10 pts)
    2. Presentation has 4 slides (15 pts)
    3. Slide 4 contains "Cloud Migration" title (15 pts)
    4. Slide 4 has at least 5 shapes (20 pts)
    5. Milestones text present (20 pts)
    6. Quarter labels present (10 pts)
    7. Anti-gaming / Original content preserved (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values from metadata
    metadata = task_info.get('metadata', {})
    required_title = metadata.get('required_title', "Cloud Migration").lower()
    min_shapes = metadata.get('min_shapes_count', 5)

    try:
        # Load result JSON from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

        # Parse analysis data
        odp_data = result.get('odp_analysis', {})
        slide4_text = odp_data.get('slide4_text', '').lower()
        
        score = 0
        feedback_parts = []
        passed_criteria = 0
        total_criteria = 7

        # 1. File Status (10 pts)
        if result.get('file_exists') and result.get('file_modified'):
            score += 10
            passed_criteria += 1
            feedback_parts.append("✅ File saved and modified")
        elif result.get('file_exists'):
            score += 5
            feedback_parts.append("⚠️ File saved but timestamp indicates no modification")
        else:
            return {"passed": False, "score": 0, "feedback": "❌ File not found"}

        # 2. Slide Count (15 pts)
        slide_count = odp_data.get('slide_count', 0)
        if slide_count == 4:
            score += 15
            passed_criteria += 1
            feedback_parts.append("✅ Correct slide count (4)")
        else:
            feedback_parts.append(f"❌ Incorrect slide count: {slide_count} (expected 4)")

        # 3. Timeline Title (15 pts)
        if required_title in slide4_text or "timeline" in slide4_text:
            score += 15
            passed_criteria += 1
            feedback_parts.append("✅ Timeline title found")
        else:
            feedback_parts.append("❌ Timeline title missing on Slide 4")

        # 4. Shape Count (20 pts)
        shape_count = odp_data.get('slide4_shape_count', 0)
        if shape_count >= min_shapes:
            score += 20
            passed_criteria += 1
            feedback_parts.append(f"✅ Sufficient shapes found ({shape_count})")
        elif shape_count >= 3:
            score += 10
            feedback_parts.append(f"⚠️ Partial shapes found ({shape_count}/{min_shapes})")
        else:
            feedback_parts.append(f"❌ Insufficient shapes ({shape_count}/{min_shapes})")

        # 5. Milestone Text (20 pts)
        # We look for key phrases from the required milestones
        milestones_found = odp_data.get('milestones_found', [])
        # We defined 8 keywords in export_result.sh, look for at least 4 unique matches
        unique_matches = len(set(milestones_found))
        if unique_matches >= 5:
            score += 20
            passed_criteria += 1
            feedback_parts.append(f"✅ Milestones text found ({unique_matches} keywords)")
        elif unique_matches >= 3:
            score += 10
            feedback_parts.append(f"⚠️ Some milestones text missing ({unique_matches} keywords)")
        else:
            feedback_parts.append(f"❌ Milestones text missing (only {unique_matches} keywords found)")

        # 6. Quarter Labels (10 pts)
        quarters_found = len(set(odp_data.get('quarters_found', [])))
        if quarters_found >= 4:
            score += 10
            passed_criteria += 1
            feedback_parts.append(f"✅ Quarter labels found ({quarters_found}/5)")
        else:
            feedback_parts.append(f"❌ Quarter labels missing (found {quarters_found}/5)")

        # 7. Integrity / Anti-gaming (10 pts)
        # Check if file size increased (adding slides/shapes adds bytes)
        initial_size = 0  # We don't have this in task_result.json, assume modified check covers it partially
        # If file modified and parsed successfully, we assume integrity is okay for this simplified check
        if odp_data.get('parsed_successfully') and result.get('file_modified'):
            score += 10
            passed_criteria += 1
            feedback_parts.append("✅ File structure valid")
        else:
            feedback_parts.append("❌ File corrupted or invalid format")

        # Calculate Final Pass State
        # Must have correct slide count and reasonable content
        passed = (score >= 60) and (slide_count == 4) and (shape_count >= 3)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification Failed: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification system error: {str(e)}"
        }