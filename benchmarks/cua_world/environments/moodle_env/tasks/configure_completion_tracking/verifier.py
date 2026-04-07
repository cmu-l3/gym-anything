#!/usr/bin/env python3
"""Verifier for Configure Completion Tracking task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_completion_tracking(traj, env_info, task_info):
    """
    Verify completion tracking configuration in Moodle.
    
    Scoring (100 points):
    - Completion tracking enabled on course (15 pts)
    - Page 1 "Required Reading: Cell Biology" created (15 pts)
    - Page 2 "Lab Safety Guidelines" created (15 pts)
    - Page 1: Automatic completion enabled (10 pts)
    - Page 2: Automatic completion enabled (10 pts)
    - Page 1: "Require view" condition set (5 pts)
    - Page 2: "Require view" condition set (5 pts)
    - Course Completion Criteria requires both activities (25 pts)
    
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/completion_tracking_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        task_start = int(result.get('task_start_time', 0))

        # Criterion 1: Completion tracking enabled (15 pts)
        if int(result.get('completion_tracking_enabled', 0)) == 1:
            score += 15
            subscores["completion_enabled"] = True
            feedback_parts.append("Completion tracking enabled")
        else:
            subscores["completion_enabled"] = False
            feedback_parts.append("Completion tracking NOT enabled")

        # Process Activity 1
        act1 = result.get('activity_1', {})
        if act1.get('found', False):
            # Check timestamps to ensure no cheating (using pre-existing data)
            # timeadded is in seconds
            time_added = int(act1.get('timeadded', 0))
            is_new = time_added > task_start
            
            if is_new:
                score += 15
                feedback_parts.append("Reading activity created")
            else:
                score += 5 # Reduced points for pre-existing
                feedback_parts.append("Reading activity found (pre-existing)")
            
            # Auto completion (completion=2 means AUTOMATIC, 1 is manual)
            if int(act1.get('completion', 0)) == 2:
                score += 10
                feedback_parts.append("Reading: Auto completion set")
            else:
                feedback_parts.append(f"Reading: Wrong completion mode ({act1.get('completion')})")
                
            # View requirement
            if int(act1.get('completionview', 0)) == 1:
                score += 5
                feedback_parts.append("Reading: View condition set")
            else:
                feedback_parts.append("Reading: View condition missing")
                
            # Course criteria link
            if int(act1.get('in_course_criteria', 0)) > 0:
                subscores["act1_linked"] = True
            else:
                subscores["act1_linked"] = False
        else:
            feedback_parts.append("Reading activity NOT found")
            subscores["act1_linked"] = False

        # Process Activity 2
        act2 = result.get('activity_2', {})
        if act2.get('found', False):
            # Timestamp check
            time_added = int(act2.get('timeadded', 0))
            is_new = time_added > task_start

            if is_new:
                score += 15
                feedback_parts.append("Safety activity created")
            else:
                score += 5
                feedback_parts.append("Safety activity found (pre-existing)")

            # Auto completion
            if int(act2.get('completion', 0)) == 2:
                score += 10
                feedback_parts.append("Safety: Auto completion set")
            else:
                feedback_parts.append(f"Safety: Wrong completion mode ({act2.get('completion')})")

            # View requirement
            if int(act2.get('completionview', 0)) == 1:
                score += 5
                feedback_parts.append("Safety: View condition set")
            else:
                feedback_parts.append("Safety: View condition missing")

            # Course criteria link
            if int(act2.get('in_course_criteria', 0)) > 0:
                subscores["act2_linked"] = True
            else:
                subscores["act2_linked"] = False
        else:
            feedback_parts.append("Safety activity NOT found")
            subscores["act2_linked"] = False

        # Criterion: Course Completion Criteria (25 pts)
        # Both activities must be linked
        if subscores.get("act1_linked") and subscores.get("act2_linked"):
            score += 25
            feedback_parts.append("Course completion requires both activities")
        elif subscores.get("act1_linked") or subscores.get("act2_linked"):
            score += 10
            feedback_parts.append("Course completion requires only one activity (expected both)")
        else:
            feedback_parts.append("Course completion criteria NOT configured correctly")

        # Pass threshold
        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON result"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}