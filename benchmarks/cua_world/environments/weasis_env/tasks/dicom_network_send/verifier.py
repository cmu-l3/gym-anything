#!/usr/bin/env python3
"""
Verifier for DICOM Network Send task.

This task utilizes MULTIPLE INDEPENDENT SIGNALS to verify success and prevent gaming:
1. Network Protocol Logs: The background `storescp` daemon must log standard DICOM 
   Association and C-STORE requests. Shell copying files will NOT trigger these logs.
2. File System Checks: The hidden destination directory must contain the received 
   DICOM object files.
3. VLM Trajectory Verification: Confirms the agent interacted with the network 
   configuration UI.
"""

import os
import sys
import json
import logging
import tempfile

# Add utils to path (relative to this file, for host execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    pass # Graceful fallback if executing outside standard environment structure

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_via_vlm(traj, env_info):
    """
    Use a VLM to verify that the agent interacted with the DICOM Send / Network Node configuration UI.
    Uses multiple trajectory frames to capture the workflow.
    """
    query_func = env_info.get('query_vlm')
    if not query_func:
        logger.warning("VLM query function not available.")
        return 0, "VLM unavailable"
        
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=6)
    except ImportError:
        logger.warning("Could not import trajectory sampler.")
        return 0, "Trajectory sampler unavailable"

    if not frames:
        return 0, "No frames available"

    prompt = """You are verifying if an agent successfully configured a DICOM network node in Weasis.
    
Look at this sequence of screenshots from the agent's interaction.
Please determine:
1. UI_OPENED: Did the agent open the 'DICOM Send', 'Export', or 'Preferences -> DICOM Nodes' dialog?
2. CONFIG_ENTERED: Is there evidence of the agent entering network parameters like 'PACS_ARCHIVE', '11112', or 'Central PACS'?
3. TRANSFER_INITIATED: Did the agent click a 'Send', 'Export', or 'Verify' button related to the network transfer?

Respond in JSON format:
{
    "ui_opened": true/false,
    "config_entered": true/false,
    "transfer_initiated": true/false,
    "confidence": "high"/"medium"/"low",
    "reasoning": "brief explanation"
}
"""
    try:
        result = query_func(prompt=prompt, images=frames)
        if result.get("success"):
            parsed = result.get("parsed", {})
            ui = parsed.get("ui_opened", False)
            cfg = parsed.get("config_entered", False)
            tx = parsed.get("transfer_initiated", False)
            
            pts = 0
            if ui: pts += 5
            if cfg: pts += 10
            if tx: pts += 5
            return pts, "VLM verified UI interaction" if pts > 0 else "VLM found no UI interaction"
        return 0, "VLM query failed"
    except Exception as e:
        logger.error(f"VLM verification exception: {e}")
        return 0, str(e)


def verify_dicom_network_send(traj, env_info, task_info):
    """
    Main verification logic scoring network logs, files, and visual trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0

    # 1. Fetch Result Data
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

    assoc_count = result.get('association_count', 0)
    store_count = result.get('store_count', 0)
    file_count = result.get('file_count', 0)

    # 2. Programmatic Verification (Logs and Files)
    # Criterion 1: Network Association (20 points)
    if assoc_count > 0:
        score += 20
        feedback_parts.append(f"Network association logged ({assoc_count})")
    else:
        feedback_parts.append("No DICOM association logged")

    # Criterion 2: C-STORE Requests (20 points)
    if store_count > 0:
        score += 20
        feedback_parts.append(f"C-STORE requests logged ({store_count})")
    else:
        feedback_parts.append("No C-STORE transfers logged")

    # Criterion 3: Files Physically Received (40 points)
    if file_count > 0:
        score += 40
        feedback_parts.append(f"Received {file_count} DICOM files in archive")
    else:
        feedback_parts.append("No files received in archive")

    # 3. VLM Verification (20 points)
    # Only run VLM if programmatic checks show SOME activity, or run it unconditionally for robustness
    vlm_score, vlm_feedback = verify_via_vlm(traj, env_info)
    score += vlm_score
    feedback_parts.append(f"VLM [{vlm_score} pts]: {vlm_feedback}")

    # 4. Anti-Gaming Strict Checks
    # If files exist but NO network logs exist, the agent copied them directly (cheating)
    if file_count > 0 and assoc_count == 0 and store_count == 0:
        score = 0
        feedback_parts.append("CRITICAL FAILURE: Files exist but no network traffic logged. File copying detected.")

    # 5. Final Decision
    # Require at least the programmatic checks to be mostly successful (files + logs = 80 points)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "associations": assoc_count,
            "c_stores": store_count,
            "files_received": file_count,
            "vlm_score": vlm_score
        }
    }