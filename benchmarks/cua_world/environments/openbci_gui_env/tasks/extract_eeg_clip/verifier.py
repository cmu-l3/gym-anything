#!/usr/bin/env python3
"""
Verifier for extract_eeg_clip task.

Criteria:
1. New recording file created during task (30 pts)
2. Duration is within 10-20 seconds (approx 2500-5000 samples @ 250Hz) (30 pts)
3. App was running at end (10 pts)
4. VLM Verification: Agent used "Playback" mode, not Synthetic (30 pts)
"""

import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

def verify_extract_eeg_clip(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load programmatic results
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

    # 1. Check file creation
    if result.get("file_created", False):
        score += 30
        feedback.append("New recording file created.")
    else:
        feedback.append("No new recording file found.")
        return {"passed": False, "score": 0, "feedback": "Failed: No recording created."}

    # 2. Check Duration (Sample Count)
    # Target: 10-20s @ 250Hz = 2500-5000 samples.
    # Allow generous tolerance (e.g., 8s to 25s) because manual timing is hard.
    samples = result.get("sample_count", 0)
    duration_est = samples / 250.0
    
    if 2000 <= samples <= 6250: # 8s to 25s
        score += 30
        feedback.append(f"Duration acceptable (~{duration_est:.1f}s).")
    elif samples > 0:
        score += 10 # Partial credit for recording something
        feedback.append(f"Duration out of target range (~{duration_est:.1f}s). Target: 10-20s.")
    else:
        feedback.append("File appears empty (0 samples).")

    # 3. Check App State
    if result.get("app_running", False):
        score += 10
        feedback.append("App still running.")

    # 4. VLM Verification: Playback Mode vs Synthetic
    # We check trajectory frames to see if "Playback" was selected or visible.
    # Synthetic mode usually shows perfect waves; Playback shows messy EEG.
    # Also, the Control Panel dropdown explicitly says "PLAYBACK".
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of the OpenBCI GUI workflow.
        
        1. Did the agent select "PLAYBACK (from file)" as the Data Source in the System Control Panel?
           (Look for the dropdown selection or the text 'PLAYBACK' in the setup screen).
        2. During the session, does the data look like real EEG (irregular, noisy) or Synthetic (perfect regular waves)?
        
        Answer JSON: {"used_playback": boolean, "reasoning": "string"}
        """
        
        vlm_resp = query_vlm(images=frames, prompt=prompt)
        used_playback = vlm_resp.get("parsed", {}).get("used_playback", False)
        
        if used_playback:
            score += 30
            feedback.append("VLM confirmed Playback mode used.")
        else:
            feedback.append("VLM could not confirm Playback mode (might be Synthetic or unclear).")
    else:
        # Fallback if VLM not available (shouldn't happen in prod, but safe fallback)
        score += 30
        feedback.append("VLM check skipped (unavailable).")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }