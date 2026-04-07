#!/usr/bin/env python3
"""
Verifier for generate_patient_summary task in FreeMED.

HYBRID VERIFICATION:
1. Programmatic Check: Verifies if a file was downloaded (system state).
2. VLM Trajectory Check: Verifies the agent actually navigated to Maria Santos
   and triggered a print/summary feature (preventing false positives).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_patient_summary(traj, env_info, task_info):
    """
    Verify the patient summary was generated.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read exported programmatic data
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/patient_summary_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    downloads_count = result_data.get("new_downloads_count", 0)
    downloaded_files = result_data.get("downloaded_files", "")
    window_titles = result_data.get("window_titles", "").lower()

    score = 0
    feedback_parts = []
    
    # Check for programmatic evidence of completion (new file or print window)
    evidence_of_output = False
    if downloads_count > 0:
        score += 30
        evidence_of_output = True
        feedback_parts.append(f"File downloaded ({downloaded_files})")
    elif "print" in window_titles or "summary" in window_titles or "report" in window_titles:
        score += 30
        evidence_of_output = True
        feedback_parts.append("Print/Summary window title detected")
    else:
        feedback_parts.append("No new downloads or print tabs detected programmatically")

    # 2. VLM Trajectory Verification
    # We use trajectory frames to ensure the agent actually did the work, not just opened a random tab.
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        images = frames + [final_frame] if final_frame else frames
    except ImportError:
        logger.warning("gym_anything.vlm not available, skipping visual trajectory check.")
        images = []

    vlm_patient_selected = False
    vlm_summary_generated = False

    if images and 'query_vlm' in env_info:
        query_vlm = env_info['query_vlm']
        prompt = """
        Examine these screenshots from a user interacting with the FreeMED Electronic Medical Record (EMR) system.
        The goal of the task is to generate a patient clinical summary or print the chart for the patient "Maria Santos".

        Please evaluate the trajectory and respond with a JSON object containing these boolean fields:
        1. "patient_selected": Did the user successfully search for and open the chart/dashboard for "Maria Santos"?
        2. "summary_generated": Did the user click a "Print", "Summary", or "Export" button AND does the final state show a generated report, a print preview dialog, or a downloaded patient record file?

        JSON Format strictly:
        {
            "patient_selected": true/false,
            "summary_generated": true/false
        }
        """
        
        try:
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response and "parsed" in vlm_response:
                parsed = vlm_response["parsed"]
                vlm_patient_selected = parsed.get("patient_selected", False)
                vlm_summary_generated = parsed.get("summary_generated", False)
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification failed")

    # Score calculation based on VLM
    if vlm_patient_selected:
        score += 35
        feedback_parts.append("VLM confirmed Maria Santos was selected")
    else:
        feedback_parts.append("VLM could not confirm patient selection")

    if vlm_summary_generated:
        score += 35
        feedback_parts.append("VLM confirmed summary generation/print action")
    else:
        feedback_parts.append("VLM could not confirm summary generation visually")

    # Fallback if VLM is entirely unavailable but programmatic check passed
    if not images and evidence_of_output:
        score += 70  # Grant missing VLM points if we have strong programmatic evidence and no VLM
        feedback_parts.append("Awarded full points based on programmatic evidence (VLM unavailable)")

    # Key criteria: Must have successfully navigated to patient AND generated output
    passed = score >= 70 and (vlm_patient_selected or not images) and (evidence_of_output or vlm_summary_generated)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }