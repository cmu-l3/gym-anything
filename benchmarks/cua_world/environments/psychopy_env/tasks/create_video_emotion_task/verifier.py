#!/usr/bin/env python3
"""
Verifier for create_video_emotion_task.

Verification Strategy:
1. File Existence & Validity (Experiment .psyexp and Conditions .csv)
2. Experiment Logic (Movie component used, Loop connected, Sliders present)
3. Asset Management (Videos copied to project folder)
4. CSV Content (Correct columns, rows for 3 videos)
5. VLM Verification (Trajectory shows interaction with Movie/Slider components)

Pass Threshold: 70/100 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_video_emotion_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from export_result.sh
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/video_emotion_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # Nonce check
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "Anti-gaming check failed (nonce mismatch)."}
    except Exception:
        pass # Ignore if nonce file missing (dev mode)
    finally:
        if os.path.exists(nonce_path):
            os.unlink(nonce_path)

    score = 0
    feedback = []

    # 1. File Structure (20 pts)
    if result.get('exp_exists') and result.get('csv_exists'):
        score += 10
        feedback.append("Experiment and CSV files created.")
    else:
        feedback.append("Missing experiment or CSV file.")

    if result.get('assets_copied'):
        score += 10
        feedback.append("Video assets copied correctly.")
    else:
        feedback.append("Video assets not found in project folder.")

    # 2. Experiment Logic (40 pts)
    if result.get('has_movie_component'):
        score += 10
        feedback.append("Movie component present.")
        if result.get('movie_uses_variable'):
            score += 10
            feedback.append("Movie component uses variable for playback.")
        else:
            feedback.append("Movie component does NOT use a variable (static file?).")
    else:
        feedback.append("No Movie component found.")

    slider_count = result.get('slider_count', 0)
    if slider_count >= 2:
        score += 10
        feedback.append(f"Found {slider_count} sliders.")
    elif slider_count == 1:
        score += 5
        feedback.append("Found only 1 slider (2 required).")
    else:
        feedback.append("No sliders found.")

    if result.get('has_loop') and result.get('loop_uses_csv'):
        score += 10
        feedback.append("Loop configured with CSV.")
    else:
        feedback.append("Loop missing or not connected to CSV.")

    # 3. CSV Content (20 pts)
    if result.get('csv_has_required_cols'):
        score += 10
        feedback.append("CSV has correct columns.")
    else:
        feedback.append("CSV missing required columns (video_file, emotion).")
    
    if result.get('csv_row_count', 0) >= 3:
        score += 10
        feedback.append("CSV has sufficient rows.")
    else:
        feedback.append(f"CSV has too few rows ({result.get('csv_row_count')}).")

    # 4. VLM Verification (20 pts)
    # Check for visual evidence of the Movie or Slider dialogs
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Do these screenshots show a user working in PsychoPy Builder?
        Look for:
        1. A Movie/Video component dialog or icon.
        2. A Slider/Rating scale component dialog or icon.
        3. A Loop or Flow view with multiple routines.
        
        Answer JSON: {"psychopy_visible": bool, "components_visible": bool}
        """
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('psychopy_visible'):
                score += 10
            if parsed.get('components_visible'):
                score += 10

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }