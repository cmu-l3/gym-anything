#!/usr/bin/env python3
"""
Verifier for the Configure Assignment Rubric task.

Evaluates multi-step Moodle configuration by checking internal database states
and confirming workflow progression via Vision Language Model to prevent script-based gaming.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Fallback import for VLM utilities
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available. Trajectory checks will be bypassed.")

def verify_configure_rubric(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_rubric_name = metadata.get('expected_rubric_name', 'Analytical Essay Rubric')
    expected_status = metadata.get('expected_status', 20)
    expected_criteria_count = metadata.get('expected_criteria_count', 3)
    expected_levels_count = metadata.get('expected_levels_count', 9)
    criteria_keywords = metadata.get('criteria_keywords', ["Content Development", "Sources and Evidence", "Syntax and Mechanics"])

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

    task_start = result.get('task_start', 0)
    moodle_data = result.get('moodle_data', {})
    
    score = 0
    feedback_parts = []
    
    # Check 1: Was grading area initialized?
    if not moodle_data.get('found', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Grading area not configured for the assignment."
        }

    # Check 2: Active method is 'rubric' (15 points)
    if moodle_data.get('activemethod') == 'rubric':
        score += 15
        feedback_parts.append("Method set to Rubric")
    else:
        feedback_parts.append("Method is not Rubric")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    definition = moodle_data.get('definition')
    if not definition:
        feedback_parts.append("Rubric definition not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Anti-gaming: Ensure rubric was created during the task
    timecreated = definition.get('timecreated', 0)
    timemodified = definition.get('timemodified', 0)
    if timecreated < task_start and timemodified < task_start:
        feedback_parts.append("Anti-gaming alert: Rubric existed before task started and was not modified")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Check 3: Rubric Name (10 points)
    if definition.get('name', '').strip().lower() == expected_rubric_name.lower():
        score += 10
        feedback_parts.append("Name correct")
    else:
        feedback_parts.append(f"Incorrect name: {definition.get('name')}")

    # Check 4: Status is 20 / Ready (15 points)
    if definition.get('status') == expected_status:
        score += 15
        feedback_parts.append("Status is Ready")
    else:
        feedback_parts.append("Status is Draft/Not Ready")

    # Check 5 & 6: Criteria and Levels counts (20 + 20 points)
    criteria = definition.get('criteria', [])
    actual_criteria_count = len(criteria)
    
    if actual_criteria_count == expected_criteria_count:
        score += 20
        feedback_parts.append(f"{actual_criteria_count} criteria found")
    else:
        # Partial credit for criteria
        pts = int(20 * (actual_criteria_count / expected_criteria_count))
        score += min(pts, 20)
        feedback_parts.append(f"Found {actual_criteria_count}/{expected_criteria_count} criteria")

    actual_levels_count = sum(len(c.get('levels', [])) for c in criteria)
    if actual_levels_count == expected_levels_count:
        score += 20
        feedback_parts.append(f"{actual_levels_count} levels found")
    else:
        pts = int(20 * (actual_levels_count / expected_levels_count))
        score += min(pts, 20)
        feedback_parts.append(f"Found {actual_levels_count}/{expected_levels_count} levels")

    # Check 7: Content Accuracy (20 points) - Keyword matches
    matched_keywords = 0
    all_descriptions = " ".join([c.get('description', '') for c in criteria]).lower()
    for keyword in criteria_keywords:
        if keyword.lower() in all_descriptions:
            matched_keywords += 1

    content_score = int(20 * (matched_keywords / len(criteria_keywords)))
    score += content_score
    feedback_parts.append(f"Content match: {matched_keywords}/{len(criteria_keywords)} keywords")

    # VLM Trajectory Verification
    vlm_penalty = 0
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            prompt = """Analyze these trajectory frames from an agent configuring a Moodle Rubric.
Look specifically for:
1. Did the agent ever open, view, or select text from a file/document named 'rubric_definition.md' (or similar markdown file)?
2. Is there visual evidence of the agent interacting with Moodle's 'Advanced Grading' or 'Rubric' builder interface?

Answer in JSON format:
{
    "viewed_markdown_file": true/false,
    "interacted_with_moodle_builder": true/false
}
"""
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if not parsed.get('viewed_markdown_file', False):
                    vlm_penalty -= 15
                    feedback_parts.append("VLM Penalty: Agent did not visibly open the markdown document")
                if not parsed.get('interacted_with_moodle_builder', False):
                    vlm_penalty -= 15
                    feedback_parts.append("VLM Penalty: Agent did not visibly interact with the web UI (Scripting suspected)")
            else:
                logger.warning("VLM query failed, skipping trajectory verification.")
        except Exception as e:
            logger.warning(f"Error during VLM evaluation: {e}")

    final_score = max(0, score + vlm_penalty)
    passed = final_score >= 70 and moodle_data.get('activemethod') == 'rubric'

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }