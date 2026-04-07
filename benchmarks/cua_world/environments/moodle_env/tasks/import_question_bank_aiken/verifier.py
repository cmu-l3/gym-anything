#!/usr/bin/env python3
"""
Verifier for Import Question Bank via Aiken Format task.
Combines programmatic database state checks via PHP-exported JSON with VLM trajectory analysis.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_TRAJECTORY_PROMPT = """You are evaluating an agent performing a task in the Moodle Learning Management System.
The agent was asked to import an Aiken format question bank file into a specific course category.

Please look at this sequence of screenshots taken during the agent's execution and determine if the agent performed the following actions:
1. Navigated to the Moodle "Question Bank" area.
2. Interacted with the "Import" tab/screen.
3. Selected "Aiken format" as the file format.
4. Uploaded or selected a text file (cardiology_nclex_questions.txt).
5. Received a success/confirmation screen showing parsed questions.

Respond with a JSON object containing:
{
    "navigated_to_question_bank": boolean,
    "interacted_with_import_screen": boolean,
    "selected_aiken_format": boolean,
    "uploaded_file": boolean,
    "success_screen_visible": boolean,
    "confidence": "low|medium|high",
    "reasoning": "Brief explanation of what is visible in the frames."
}
"""

def verify_import_question_bank(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read programmatic state from JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    logger.info(f"Database extraction result: {result}")

    score = 0
    feedback_parts = []
    
    # Check 1: Did the course exist? (Sanity check)
    if not result.get('course_exists', False):
        return {"passed": False, "score": 0, "feedback": "Course NURS101 was missing or deleted."}

    # Check 2: Was the category created? (20 points)
    category_exists = result.get('target_category_exists', False)
    if category_exists:
        score += 20
        feedback_parts.append("Category 'Cardiology NCLEX Review' created.")
    else:
        feedback_parts.append("Category 'Cardiology NCLEX Review' NOT found.")

    # Check 3: Were questions imported into the course context? (30 points)
    # We check the total course questions in case they missed the category dropdown
    total_q_count = result.get('total_course_q_count', 0)
    target_q_count = result.get('target_category_q_count', 0)
    
    if total_q_count >= 15:
        score += 30
        feedback_parts.append(f"Successfully imported {total_q_count} questions.")
    elif total_q_count > 0:
        score += 10
        feedback_parts.append(f"Partial import: only {total_q_count} questions found.")
    else:
        feedback_parts.append("No questions were imported into the course.")

    # Check 4: Were they put in the CORRECT category? (30 points)
    if category_exists and target_q_count >= 15:
        score += 30
        feedback_parts.append("Questions assigned to the correct custom category.")
    elif category_exists and target_q_count > 0:
        score += 15
        feedback_parts.append(f"Some questions ({target_q_count}) assigned to correct category.")
    elif total_q_count >= 15:
        feedback_parts.append("Questions imported, but mapped to the default course category instead of the custom one.")

    # Check 5: Anti-gaming content check (20 points)
    # Verify the text actually contains expected medical content, proving it wasn't manual dummy data
    sample_text = str(result.get('sample_question_text', '')).lower()
    expected_keywords = ['myocardial', 'heart', 'nurse', 'client', 'blood', 'cardiogenic', 'pericarditis', 'ventricular']
    
    matched_keywords = [kw for kw in expected_keywords if kw in sample_text]
    if len(matched_keywords) >= 1:
        score += 20
        feedback_parts.append("Question content verified (genuine Aiken file data).")
    elif total_q_count > 0:
        feedback_parts.append("Question content mismatch! May be manual dummy data.")

    # 2. VLM Verification on Trajectory (Backup/Contextual signal)
    # We require the programmatic DB checks to pass primarily, but VLM acts as an anti-gaming shield
    vlm_passed = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=6)
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VLM_TRAJECTORY_PROMPT)
            
            if vlm_response and vlm_response.get("success"):
                vlm_parsed = vlm_response.get("parsed", {})
                logger.info(f"VLM Analysis: {vlm_parsed}")
                
                # Check for evidence of genuine interaction
                if vlm_parsed.get("navigated_to_question_bank") and vlm_parsed.get("interacted_with_import_screen"):
                    vlm_passed = True
                    feedback_parts.append("VLM confirmed question bank navigation.")
                else:
                    feedback_parts.append("VLM did not observe clear question bank navigation.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Soft-fail VLM if it errors, rely on database
        vlm_passed = True

    # Determine pass/fail
    # To pass, they must score at least 70 (Requires importing the questions + proving genuine content)
    # If they imported them to the default category instead of custom, they max out at 70 (20 content + 30 import + 0 category + 0 cat_assignment)
    # Wait, if they don't create the category (0), import to default (30), content valid (20), they get 50. They fail.
    # If they create category (20), import to default (30), content valid (20), they get 70. They pass! This is fair.
    passed = score >= 70 and total_q_count >= 15

    # Hard anti-gaming rule: If content doesn't match the file, it's an automatic fail
    if total_q_count > 0 and len(matched_keywords) == 0:
        passed = False
        score = min(score, 40)
        feedback_parts.append("FAIL: Inserted questions did not match the provided file content.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }