#!/usr/bin/env python3
"""
Verifier for the Configure DICOM Send task.

Checks:
1. Network Logs: Verifies an Association was established.
2. Protocol Logs: Verifies C-STORE requests were logged.
3. Disk I/O: Verifies the files physically arrived in the target directory AFTER the task start time.
4. VLM Trajectory: Verifies the GUI was actually used to configure/send (prevents terminal 'storescu' gaming).
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing screenshots of an agent using Weasis DICOM Viewer to configure and execute a DICOM Network Send (C-STORE).

Please look closely at these chronological frames and determine if the agent utilized the Weasis Graphical User Interface (GUI) to accomplish the network configuration or transfer.

Indicators to look for:
1. Is the Weasis "Preferences" dialog open to the "DICOM / DICOM Nodes" section?
2. Is there a "DICOM Send", "Export", or "Destination" dialog window open?
3. Is there a progress bar indicating an active DICOM export/transfer?
4. Are they entering an IP (127.0.0.1) or Port (4242) into a GUI form?

Respond in pure JSON format:
{
    "gui_node_configuration_visible": true/false,
    "dicom_send_dialog_visible": true/false,
    "transfer_progress_visible": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_configure_dicom_send(traj, env_info, task_info):
    """Verify that DICOM Send was configured and executed using Weasis."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch programmatic data from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Network Checks (60 Points Total)
    assoc_count = result.get('association_count', 0)
    cstore_count = result.get('cstore_count', 0)
    new_files = result.get('new_files_received', 0)
    
    # A. Association Request (Network Connection)
    if assoc_count > 0:
        score += 20
        feedback_parts.append(f"DICOM Association logged ({assoc_count})")
    else:
        feedback_parts.append("No DICOM Association detected")

    # B. C-STORE Request (Protocol Transfer)
    if cstore_count > 0:
        score += 20
        feedback_parts.append(f"C-STORE protocol commands logged ({cstore_count})")
    else:
        feedback_parts.append("No C-STORE protocol commands logged")
        
    # C. Files successfully written to disk during the task
    if new_files > 0:
        score += 20
        feedback_parts.append(f"Files successfully transferred to PACS ({new_files})")
    else:
        feedback_parts.append("No new files arrived at destination")

    # Anti-gaming: If files arrived but no association was made, they bypassed the network protocol.
    if new_files > 0 and assoc_count == 0:
        score -= 40
        feedback_parts.append("WARNING: Files found but no network transfer logged (Cheat detected)")

    # 3. VLM Trajectory Verification (40 Points)
    # Proves the agent actually used the UI to configure the node rather than a terminal
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        all_frames = frames + [final_frame] if final_frame else frames
        
        vlm_response = query_vlm(images=all_frames, prompt=VLM_PROMPT)
        
        if vlm_response and vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            gui_config = parsed.get("gui_node_configuration_visible", False)
            gui_dialog = parsed.get("dicom_send_dialog_visible", False)
            gui_progress = parsed.get("transfer_progress_visible", False)
            
            if gui_config or gui_dialog or gui_progress:
                score += 40
                feedback_parts.append("VLM confirmed Weasis GUI usage")
            else:
                feedback_parts.append("VLM did not detect GUI DICOM configuration")
        else:
            logger.warning("VLM query failed or returned no success.")
            feedback_parts.append("VLM verification failed")
            
    except Exception as e:
        logger.error(f"VLM verification exception: {e}")
        feedback_parts.append("VLM verification encountered an error")

    # 4. Final Assessment
    # An agent passing programmatic checks completely gets 60 points. 
    # With VLM GUI confirmation, it gets 100 points.
    # We require at least 70 to pass to ensure they actually used the GUI.
    passed = score >= 70

    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": " | ".join(feedback_parts)
    }