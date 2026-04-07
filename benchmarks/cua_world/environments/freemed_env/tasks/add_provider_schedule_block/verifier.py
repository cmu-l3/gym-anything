#!/usr/bin/env python3
"""
Verifier for add_provider_schedule_block task in FreeMED.

Uses a multi-signal approach combining database record verification
and trajectory-based Vision Language Model (VLM) checks.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_schedule_block(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # VLM Evaluation for Visual Confirmation (Trajectory Checks)
    # ================================================================
    vlm_score = 0
    vlm_feedback = ""
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = (
                "Review these screenshots of a user interacting with an EMR system (FreeMED). "
                "Did the user navigate to a scheduling or calendar interface and attempt to "
                "create an appointment or time block for Dr. Sarah Chen? "
                "Look for times between 08:00 and 12:00, the date March 20, 2026, "
                "or text like 'Hospital Board Meeting'.\n"
                "Respond strictly in JSON format: {\"user_attempted_schedule\": true/false}"
            )
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response and vlm_response.get('parsed', {}).get('user_attempted_schedule'):
                vlm_score = 15
                vlm_feedback = "VLM confirmed scheduling interaction."
            else:
                vlm_feedback = "VLM did not detect clear scheduling actions."
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            vlm_feedback = f"VLM error: {e}"

    # ================================================================
    # Programmatic Database Evaluation
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    records = result.get('records', [])

    score = 0
    feedback_parts = []

    # 1. Was a record added overall? (Anti-gaming check)
    if current_count > initial_count:
        score += 15
        feedback_parts.append(f"Scheduler records increased ({initial_count} -> {current_count})")
    else:
        feedback_parts.append("No new scheduler records detected overall")

    # 2. Check the specific records found for Dr. Sarah Chen on 2026-03-20
    if not records:
        feedback_parts.append("No schedule records found for Dr. Sarah Chen on 2026-03-20")
        return {
            "passed": False,
            "score": score + vlm_score,
            "feedback": " | ".join(feedback_parts) + f" | {vlm_feedback}"
        }

    score += 25
    feedback_parts.append("Found schedule record(s) on target date for provider")

    # Evaluate the best matching record
    best_record_score = 0
    best_record_feedback = []

    for rec in records:
        rec_score = 0
        rec_fb = []
        
        # Flexibly check time (08:xx)
        time_correct = False
        for k, v in rec.items():
            if isinstance(v, str) and ('08:' in v or '8:00' in v):
                time_correct = True
                break
        
        if time_correct:
            rec_score += 20
            rec_fb.append("Start time correct (08:xx)")
        
        # Check patient (should be empty/0 since it's an administrative block)
        patient_val = str(rec.get('calpatient', '')).strip()
        if patient_val in ['0', '', 'NULL', 'None']:
            rec_score += 10
            rec_fb.append("No patient assigned (block type correct)")
        
        # Flexibly check notes in any text column
        notes_correct = False
        for k, v in rec.items():
            if isinstance(v, str):
                v_lower = v.lower()
                if 'hospital' in v_lower or 'board' in v_lower or 'meeting' in v_lower:
                    notes_correct = True
                    break
        
        if notes_correct:
            rec_score += 15
            rec_fb.append("Meeting notes included")

        if rec_score > best_record_score:
            best_record_score = rec_score
            best_record_feedback = rec_fb
    
    score += best_record_score
    feedback_parts.extend(best_record_feedback)

    total_score = score + vlm_score
    if vlm_feedback:
        feedback_parts.append(vlm_feedback)

    # Key criteria threshold logic
    passed = total_score >= 60 and (best_record_score >= 20)

    return {
        "passed": passed,
        "score": min(100, total_score),
        "feedback": " | ".join(feedback_parts)
    }