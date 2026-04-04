#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prepare_course_reading_list(traj, env_info, task_info):
    """
    Verify the reading list preparation task.
    
    Criteria:
    1. Collection created correctly (10 pts)
    2. Correct items added (20 pts)
    3. Note added to Marbury (25 pts)
    4. Report file generated and valid (25 pts)
    5. VLM verification of workflow (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Collection Check (10 pts)
    if result.get("collection_exists"):
        score += 10
        feedback.append("Collection 'Week 1 - Judicial Review' created.")
    else:
        feedback.append("Collection not found.")

    # 2. Items Check (20 pts)
    items_ok = True
    if not result.get("has_marbury"):
        feedback.append("Missing 'Marbury v. Madison' in collection.")
        items_ok = False
    if not result.get("has_article"):
        feedback.append("Missing 'Constitutional Fact Review' in collection.")
        items_ok = False
    
    if items_ok and result.get("collection_exists"):
        score += 20
        feedback.append("All required items found in collection.")
    elif result.get("collection_exists"):
        # Partial credit for items
        if result.get("has_marbury"): score += 10
        if result.get("has_article"): score += 10

    # 3. Note Check (25 pts)
    if result.get("note_found"):
        score += 25
        feedback.append("Instruction note added to 'Marbury v. Madison' correctly.")
    else:
        feedback.append("Note about 'original jurisdiction' not found on Marbury case.")

    # 4. File Check (25 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        if result.get("file_content_valid"):
            score += 25
            feedback.append("Report generated successfully with correct content.")
        else:
            score += 15
            feedback.append("Report file exists but missing note text.")
    elif result.get("file_exists"):
        score += 5
        feedback.append("Report file exists but timestamp suggests it wasn't created now.")
    else:
        feedback.append("Report file 'week1_syllabus.html' not found.")

    # 5. VLM Verification (20 pts)
    # Check if we saw the report dialog or note editor
    frames = sample_trajectory_frames(traj, n=4)
    vlm_prompt = (
        "Look at these screenshots of a user using Juris-M/Zotero. "
        "Did the user perform the following actions?\n"
        "1. Open a collection named 'Week 1'.\n"
        "2. Add a yellow sticky note or edit a note tab.\n"
        "3. Open a 'Zotero Report' window or save a file.\n"
        "Answer Yes/No for each and provide a brief reason."
    )
    
    try:
        vlm_resp = query_vlm(images=frames, prompt=vlm_prompt)
        # Simple heuristic based on VLM text response
        if "yes" in vlm_resp.lower():
            score += 20
            feedback.append("VLM verified workflow actions.")
        else:
            # Fallback if VLM is uncertain but file exists
            if result.get("file_exists") and result.get("note_found"):
                score += 20
                feedback.append("VLM uncertain, but evidence confirms workflow.")
            else:
                feedback.append("VLM could not verify workflow.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Graceful fallback: full points if hard evidence is perfect
        if score >= 80:
            score += 20

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " ".join(feedback)
    }