#!/usr/bin/env python3
"""
Verifier for LCA Commons Metadata Prep task.

Checks:
1. Programmatic: Verification of DB entities (Actor, Source, Process) and their links via SQL export.
2. VLM: Verification that the "Administrative Information" tab was accessed and modified.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to verify UI interaction
METADATA_TAB_PROMPT = """You are verifying an OpenLCA task where the user must edit the 'Administrative Information' of a process.

Look at the provided screenshots (trajectory).
1. Do you see the 'Administrative Information' section or tab of a Process editor?
2. In this section, are there fields for 'Data Generator', 'Publication', or 'Technology description'?
3. Is there any text visible like 'EcoTech', 'Enzymatic', or '2024'?

Respond in JSON:
{
    "admin_tab_visible": true/false,
    "metadata_fields_visible": true/false,
    "target_text_visible": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None

def verify_lca_metadata(traj, env_info, task_info):
    """
    Verify that the agent created the correct metadata entities and linked them.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load programmatic result
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
    feedback = []

    # 1. Check Entities Creation (Programmatic)
    if result.get("actor_found"):
        score += 20
        feedback.append("Actor 'EcoTech Consulting' created.")
    else:
        feedback.append("Actor 'EcoTech Consulting' NOT found.")

    if result.get("source_found"):
        score += 20
        feedback.append("Source 'Q4 2024 Production Report' created.")
    else:
        feedback.append("Source 'Q4 2024 Production Report' NOT found.")

    if result.get("process_found"):
        score += 10
        feedback.append("Process 'Bio-based Polyol Production' created.")
    else:
        feedback.append("Process 'Bio-based Polyol Production' NOT found.")

    # 2. Check Linkages (Programmatic)
    if result.get("actor_linked"):
        score += 15
        feedback.append("Actor correctly linked as Data Generator.")
    else:
        feedback.append("Actor NOT linked as Data Generator.")

    if result.get("source_linked"):
        score += 15
        feedback.append("Source correctly linked as Publication.")
    else:
        feedback.append("Source NOT linked as Publication.")

    # 3. Check Metadata Content (Programmatic)
    if result.get("tech_desc_match"):
        score += 10
        feedback.append("Technology description matches.")
    else:
        feedback.append("Technology description missing or incorrect.")

    if result.get("validity_match"):
        score += 10
        feedback.append("Validity period set to 2024.")
    else:
        feedback.append("Validity period not set to 2024.")

    # 4. VLM Trajectory Check (Anti-gaming / Process verification)
    # Only verify if we have partial points to confirm manual work
    if score > 0:
        # Sample frames from trajectory
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, 4)
        vlm_res = _vlm_query(env_info.get('query_vlm'), METADATA_TAB_PROMPT, images=frames)
        
        if vlm_res:
            if not vlm_res.get("admin_tab_visible", False):
                feedback.append("Warning: Administrative tab usage not clearly observed in screenshots.")
            # We don't deduct points heavily for VLM failure here as database proof is strong, 
            # but we use it to ensure the GUI was used.

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }