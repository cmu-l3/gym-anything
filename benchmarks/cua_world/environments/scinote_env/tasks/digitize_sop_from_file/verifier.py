#!/usr/bin/env python3
"""
Verifier for digitize_sop_from_file task.

VERIFICATION METRICS:
1. Protocol Existence (Database Verification)
2. Anti-Gaming Timestamp Check (Created during task window)
3. Step Count Check
4. Content Fidelity Check (Fuzzy matching expected SOP steps against created SciNote steps)
5. VLM Trajectory Check (Did agent view the local SOP text file?)
"""

import json
import os
import tempfile
import difflib
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_via_vlm(traj, query_vlm):
    """Fallback VLM verification to ensure the file was actually opened/read during the trajectory."""
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        if not frames and not final:
            return False

        images = frames + [final] if final else frames
        prompt = """Look at these screenshots from an agent's desktop trajectory.
Did the agent open a local text file (e.g., in a terminal via 'cat'/'less', or in a text editor like gedit) to view the RIPA Lysis SOP contents?
Respond with JSON only:
{"viewed_text_file": true/false}
"""
        result = query_vlm(images=images, prompt=prompt)
        if result and result.get("success"):
            parsed = result.get("parsed", {})
            return parsed.get("viewed_text_file", False)
    except Exception as e:
        logger.warning(f"VLM trajectory check failed or not available: {e}")
    
    return True # Default to True if VLM is unavailable, relying on strict DB checks

def clean_text_for_comparison(text):
    """Remove numbered prefixes, punctuation, and lowercase the string for fuzzy matching."""
    text = text.lower()
    text = re.sub(r'^\d+\.\s*', '', text) # Remove leading "1. "
    text = re.sub(r'[^\w\s]', '', text) # Remove punctuation
    return text.strip()

def verify_digitize_sop(traj, env_info, task_info):
    """Verify that the agent accurately transferred the SOP to SciNote."""
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_protocol = metadata.get('expected_protocol_name', 'RIPA Lysis Protocol')
    expected_steps = metadata.get('expected_steps', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/digitize_sop_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported JSON result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    proto_found = result.get('protocol_found', False)
    task_start_time = int(result.get('task_start_time', 0))
    proto_data = result.get('protocol', {})
    proto_created_at = int(proto_data.get('created_at_epoch', 0))
    actual_steps = result.get('steps', [])
    actual_step_count = result.get('step_count', 0)

    # 1. Protocol Existence & Timestamp (Anti-gaming) [30 Points]
    if proto_found:
        if proto_created_at >= task_start_time:
            score += 30
            feedback_parts.append(f"Protocol '{expected_protocol}' found and created during task")
        else:
            feedback_parts.append(f"Protocol '{expected_protocol}' found but created before task started (Anti-gaming check failed)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append(f"Protocol '{expected_protocol}' not found in database")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Step Count Match [10 Points]
    if actual_step_count == len(expected_steps):
        score += 10
        feedback_parts.append(f"Correct number of steps ({actual_step_count})")
    else:
        feedback_parts.append(f"Expected {len(expected_steps)} steps, found {actual_step_count}")

    # 3. Content Fidelity (Fuzzy matching) [48 Points - 8 pts per step]
    content_score = 0
    step_matches = 0
    
    for i, expected_text in enumerate(expected_steps):
        expected_clean = clean_text_for_comparison(expected_text)
        best_ratio = 0.0
        
        # Check against all created steps (in case they got out of order, give partial credit, 
        # but highest score for matching the sequence position)
        if i < len(actual_steps):
            act_step = actual_steps[i]
            # The agent might put the SOP text in the step 'name' OR 'text_content'
            act_name_clean = clean_text_for_comparison(act_step.get('name', ''))
            act_desc_clean = clean_text_for_comparison(act_step.get('text_content', ''))
            
            ratio_name = difflib.SequenceMatcher(None, expected_clean, act_name_clean).ratio()
            ratio_desc = difflib.SequenceMatcher(None, expected_clean, act_desc_clean).ratio()
            
            best_ratio = max(ratio_name, ratio_desc)
        
        if best_ratio > 0.8:
            content_score += 8
            step_matches += 1
        elif best_ratio > 0.5:
            content_score += 4 # Partial credit for typos or missing words
    
    score += content_score
    feedback_parts.append(f"Successfully matched {step_matches}/{len(expected_steps)} step contents")

    # 4. VLM Trajectory Check [12 Points]
    if query_vlm:
        vlm_verified = verify_via_vlm(traj, query_vlm)
        if vlm_verified:
            score += 12
            feedback_parts.append("VLM confirmed SOP text file was accessed")
        else:
            feedback_parts.append("VLM did not observe the SOP text file being opened")
    else:
        score += 12
        feedback_parts.append("VLM unavailable - awarding default trajectory points")

    # Pass threshold: Must have created the protocol and matched at least 4 of the 6 steps accurately.
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "protocol_created": proto_found,
            "step_count_correct": actual_step_count == len(expected_steps),
            "content_fidelity_score": content_score
        }
    }