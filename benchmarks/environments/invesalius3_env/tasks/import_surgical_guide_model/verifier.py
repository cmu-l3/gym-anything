#!/usr/bin/env python3
"""
Verifier for Import Surgical Guide task.

Scoring Criteria (100 points total):
1. Project file creation (20 pts): Valid .inv3 file saved at correct path.
2. Content structure (20 pts): Contains at least 2 surfaces (Anatomy + Guide).
3. Guide Identification (30 pts): "surgical_guide" surface found in project.
4. Visualization Properties (30 pts): Guide surface color is predominantly Red.

Anti-gaming: Checks timestamps to ensure file was created during the session.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_surgical_guide_model(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Validity (20 pts) ---
    if result.get("project_exists") and result.get("file_fresh"):
        if result.get("file_valid"):
            score += 20
            feedback_parts.append("Project file saved successfully")
        else:
            score += 10
            feedback_parts.append("Project file exists but structure is invalid")
    else:
        feedback_parts.append("Project file not found or not created during task")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Surface Count (20 pts) ---
    # We expect at least 2 surfaces: the generated skull and the imported guide
    surface_count = result.get("surface_count", 0)
    if surface_count >= 2:
        score += 20
        feedback_parts.append(f"Found {surface_count} surfaces")
    else:
        feedback_parts.append(f"Insufficient surfaces found ({surface_count}). Expected at least 2 (Skull + Guide)")

    # --- Criterion 3: Guide Identification (30 pts) ---
    if result.get("guide_found"):
        score += 30
        feedback_parts.append("Surgical guide surface identified in project")
    else:
        feedback_parts.append("Surgical guide surface NOT found in project (check naming)")

    # --- Criterion 4: Color Check (30 pts) ---
    # Expected: Red. RGB approx (1.0, 0.0, 0.0).
    # InVesalius stores colors as normalized 0.0-1.0 floats.
    guide_color = result.get("guide_color", [0, 0, 0])
    # Handle both list and dict formats if plist parsing varies
    if isinstance(guide_color, dict):
        r = float(guide_color.get('r', 0))
        g = float(guide_color.get('g', 0))
        b = float(guide_color.get('b', 0))
    elif isinstance(guide_color, list) and len(guide_color) >= 3:
        r, g, b = float(guide_color[0]), float(guide_color[1]), float(guide_color[2])
    else:
        r, g, b = 0, 0, 0

    # Color Logic: Red dominant
    is_red = (r > 0.8) and (g < 0.4) and (b < 0.4)
    
    if is_red:
        score += 30
        feedback_parts.append("Guide color is Red")
    else:
        feedback_parts.append(f"Guide color incorrect (RGB: {r:.2f}, {g:.2f}, {b:.2f}). Expected Red.")

    # --- VLM Verification (Bonus/Confirmation) ---
    # If programmatic checks pass, we confirm visually to catch edge cases
    # (e.g., Guide exists but is hidden/invisible)
    if score >= 70:
        final_ss = get_final_screenshot(traj)
        if final_ss:
            vlm_prompt = (
                "The image shows a 3D medical software view. "
                "Can you see two distinct 3D objects? "
                "One should be a skull (likely white/beige) and the other a geometric block or shape colored RED. "
                "Answer yes if you see a RED object distinct from the skull."
            )
            vlm_res = query_vlm(vlm_prompt, final_ss)
            if vlm_res.get("success"):
                answer = vlm_res.get("parsed", {}).get("answer", "").lower()
                # Basic sentiment analysis of VLM response
                if "yes" in answer or "red object" in str(vlm_res.get("raw_response", "")).lower():
                    feedback_parts.append("Visual verification confirmed Red object")
                else:
                    # Don't penalize heavily if VLM is unsure, but note it
                    feedback_parts.append("Visual verification inconclusive")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }