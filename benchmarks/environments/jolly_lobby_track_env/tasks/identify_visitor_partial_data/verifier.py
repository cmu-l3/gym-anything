#!/usr/bin/env python3
"""
Verifier for identify_visitor_partial_data task.

Criteria:
1. Identification: 'key_owner.txt' contains "Kyle Reese" (40 pts)
2. Record Update: Database file contains the note "Lost keys returned to owner" (40 pts)
3. Process: File created during task & DB modified (20 pts)
4. VLM Verification as fallback/confirmation.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_visitor_partial_data(traj, env_info, task_info):
    """
    Verify that the agent identified the correct visitor and updated the record.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_name = metadata.get('target_name', "Kyle Reese")
    expected_note = metadata.get('expected_note', "Lost keys returned to owner")

    # Load result JSON
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

    score = 0
    feedback_parts = []
    
    # Criterion 1: Identification (File Content) - 40 pts
    output_exists = result.get('output_file_exists', False)
    output_content = result.get('output_content', "").strip()
    
    if output_exists:
        if target_name.lower() in output_content.lower():
            score += 40
            feedback_parts.append(f"✅ Correctly identified visitor: {target_name}")
        else:
            score += 10 # Partial credit for creating file
            feedback_parts.append(f"❌ Incorrect visitor identified. Expected '{target_name}', got '{output_content}'")
    else:
        feedback_parts.append("❌ Output file 'key_owner.txt' not found")

    # Criterion 2: Record Update (DB Content) - 40 pts
    # We rely on 'strings' grep from export_result.sh
    note_found = result.get('note_found_in_db', False)
    db_modified = result.get('db_modified', False)
    
    if note_found:
        score += 40
        feedback_parts.append("✅ Visitor record updated with correct note")
    elif db_modified:
        score += 10 # Credit for modifying DB but maybe wrong text or not flushed
        feedback_parts.append("⚠️ Database modified, but specific note text not found (may be encoding issue or wrong text)")
    else:
        feedback_parts.append("❌ Visitor record not updated (Database unchanged)")

    # Criterion 3: Anti-gaming / Process - 20 pts
    file_created_during = result.get('file_created_during_task', False)
    app_running = result.get('app_running', False)
    
    if file_created_during and app_running:
        score += 20
        feedback_parts.append("✅ Process checks passed (App running, file created)")
    elif app_running:
        score += 10
        feedback_parts.append("⚠️ App running but output file pre-existed?")
    else:
        feedback_parts.append("❌ App not running at end of task")

    # VLM Verification (Bonus/Confirmation)
    # If score is borderline (e.g. DB check failed due to format), VLM can save it.
    if score < 80:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        prompt = f"""
        Review these screenshots of a user using Jolly Lobby Track.
        1. Did the user search for a visitor (look for a search bar, list filtering)?
        2. Did the user select a visitor named "{target_name}" or with phone ending in "9876"?
        3. Did the user enter the note "{expected_note}"?
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_screen], prompt=prompt)
            if vlm_res.get('success'):
                feedback_parts.append(f"VLM Analysis: {vlm_res.get('parsed', 'Analysis available')}")
                # We can add small bonus if visually confirmed but DB check failed
                # But for now, we'll rely on the programmatic checks as primary
        except Exception:
            pass

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }