#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_electrical_update(traj, env_info, task_info):
    """
    Verifies the Electrical SLD Update task.
    
    Criteria:
    1. Diagram file modified (10 pts)
    2. Panel 'DP-EV' added (20 pts)
    3. Wire specs '3#3/0' added (20 pts)
    4. Breaker '200A' added (15 pts)
    5. Panel specs '225A'/'480V' added (15 pts)
    6. Topology change (more cells) (10 pts)
    7. PDF Exported (10 pts)
    
    VLM is used as a sanity check for diagram visual structure if programmatic checks are borderline.
    """
    
    # 1. Load result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get("diagram_analysis", {})
    score = 0
    feedback = []

    # --- Programmatic Scoring ---

    # 1. File Modification (10 pts)
    if analysis.get("modified_after_start"):
        score += 10
        feedback.append("File saved successfully.")
    else:
        feedback.append("Source file not saved/modified.")

    # 2. Panel 'DP-EV' (20 pts)
    if analysis.get("has_dp_ev"):
        score += 20
    else:
        feedback.append("Missing new panel tag 'DP-EV'.")

    # 3. Wire Specs (20 pts)
    if analysis.get("has_feeder_spec"):
        score += 20
    else:
        feedback.append("Missing or incorrect wire schedule (expected 3#3/0).")

    # 4. Breaker Spec (15 pts)
    if analysis.get("has_breaker_spec"):
        score += 15
    else:
        feedback.append("Missing 200A breaker rating.")

    # 5. Panel Specs (15 pts)
    if analysis.get("has_panel_spec"):
        score += 15
    else:
        feedback.append("Missing panel ratings (225A or 480/277V).")

    # 6. Topology Change (10 pts) - Minimal check for added complexity
    # Initial count was ~12 cells. We expect at least breaker + line + panel + text ~ +4
    initial_count = 12 # Hardcoded based on setup script
    current_count = analysis.get("cell_count", 0)
    if current_count >= initial_count + 3:
        score += 10
    else:
        feedback.append(f"Diagram complexity did not increase significantly (Cells: {current_count}).")

    # 7. PDF Export (10 pts)
    if result.get("pdf_exported"):
        score += 10
        feedback.append("PDF exported successfully.")
    else:
        feedback.append("PDF export missing.")

    # --- VLM Verification (Trajectory Sanity Check) ---
    # Only run if score is promising (>40) but not perfect, or to confirm visual layout
    if score > 40:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of an electrical diagram editor.
        The user should have added a new branch to the diagram.
        
        Look for:
        1. A new box/rectangle labeled something like "DP-EV" or "Panel".
        2. Connection lines extending the existing tree structure.
        
        Does the final state look like a valid Single Line Diagram with a new addition?
        Answer YES or NO.
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final], prompt=prompt)
            if vlm_res and "NO" in vlm_res.get("response", "").upper():
                feedback.append("VLM visual check: Diagram structure may be malformed.")
                # We don't deduct points heavily for VLM unless programmatic failed, 
                # but we can use it to flag anomalies.
        except Exception:
            pass

    passed = (score >= 70) and analysis.get("has_dp_ev") and analysis.get("has_feeder_spec")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }