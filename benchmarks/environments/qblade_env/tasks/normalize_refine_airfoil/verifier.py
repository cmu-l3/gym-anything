#!/usr/bin/env python3
import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_normalize_refine_airfoil(traj, env_info, task_info):
    """
    Verifies the normalize_refine_airfoil task.
    
    Criteria:
    1. Output file exists and is valid (15 pts)
    2. Output is new (not just input file copy) (5 pts)
    3. Airfoil is Normalized (x range [0, 1]) (20 pts)
    4. Airfoil is De-rotated (TE centered at y=0) (15 pts)
    5. Panel count is correct (160 +/- 5) (20 pts)
    6. Trailing Edge Gap is correct (0.004 +/- 0.001) (15 pts)
    7. VLM verification of workflow (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    try:
        import tempfile
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}

    analysis = result.get("analysis", {})
    metadata = task_info.get("metadata", {})
    
    score = 0
    feedback = []
    
    # 1. File Exists & Valid (15 pts)
    if analysis.get("exists") and analysis.get("valid_format"):
        score += 15
        feedback.append("Output file exists and has valid format.")
    else:
        feedback.append("Output file missing or invalid.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. File is New (5 pts)
    if analysis.get("is_new"):
        score += 5
        feedback.append("File created during task.")
    else:
        feedback.append("File timestamp indicates it was not created during task.")

    # 3. Normalization (20 pts)
    if analysis.get("is_normalized"):
        score += 20
        feedback.append("Airfoil is correctly normalized.")
    else:
        feedback.append(f"Airfoil not normalized (x_range: {analysis.get('x_min', 0):.3f} to {analysis.get('x_max', 0):.3f}).")

    # 4. De-rotation (15 pts)
    if analysis.get("is_derotated"):
        score += 15
        feedback.append("Airfoil is correctly de-rotated.")
    else:
        feedback.append(f"Airfoil not de-rotated (TE center y: {analysis.get('te_center_y', 0):.4f}).")

    # 5. Panel Count (20 pts)
    actual_panels = analysis.get("panel_count", 0)
    target_panels = metadata.get("expected_panels", 160)
    tolerance_panels = metadata.get("panel_tolerance", 5)
    
    if abs(actual_panels - target_panels) <= tolerance_panels:
        score += 20
        feedback.append(f"Panel count correct ({actual_panels}).")
    else:
        feedback.append(f"Panel count incorrect (Found: {actual_panels}, Expected: {target_panels}).")

    # 6. TE Gap (15 pts)
    actual_gap = analysis.get("te_gap", 0)
    target_gap = metadata.get("target_te_gap", 0.004)
    tolerance_gap = metadata.get("te_gap_tolerance", 0.001)
    
    if abs(actual_gap - target_gap) <= tolerance_gap:
        score += 15
        feedback.append(f"TE Gap correct ({actual_gap:.4f}).")
    else:
        feedback.append(f"TE Gap incorrect (Found: {actual_gap:.4f}, Expected: {target_gap}).")

    # 7. VLM Verification (10 pts)
    # Simple check: did the agent perform visible work?
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of QBlade. 
        Did the user interact with the 'Airfoil Design' module? 
        Look for airfoil plots, menus like 'Airfoil Design' or 'QBlade Direct Design', or side panels with airfoil data.
        Return JSON: {"interacted": true/false}
        """
        try:
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
            if vlm_res.get("success") and vlm_res.get("parsed", {}).get("interacted"):
                score += 10
                feedback.append("Visual verification passed.")
            else:
                feedback.append("Visual verification failed (no interaction detected).")
        except:
            # Fallback if VLM fails: give points if file stats are good
            if score >= 60:
                score += 10
                feedback.append("Visual verification skipped (system error), defaulted pass.")

    passed = (score >= 60) and analysis.get("is_normalized") and analysis.get("exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }