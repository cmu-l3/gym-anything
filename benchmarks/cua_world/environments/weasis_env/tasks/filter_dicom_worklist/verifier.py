#!/usr/bin/env python3
"""Verifier for filter_dicom_worklist task."""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utilities from the framework (crucial for trajectory verification)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    logger.warning("gym_anything.vlm not found. VLM verification will be bypassed or simulated.")
    VLM_AVAILABLE = False


def verify_filter_dicom_worklist(traj, env_info, task_info):
    """
    Verify that the correct DICOM patient was filtered, loaded, and exported.
    Combines File-based checking (Anti-gaming) and VLM checking (Trajectory Process).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Programmatic Checks (Output File & App State)
    # ================================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    app_running = result.get('app_was_running', False)
    
    if output_exists:
        if file_created_during_task and output_size > 20000:
            score += 40
            feedback_parts.append("✅ Valid screenshot export created during task")
        else:
            score += 10
            feedback_parts.append("❌ Export exists but size is too small or created before task")
    else:
        feedback_parts.append("❌ Target export file not found")

    if app_running:
        feedback_parts.append("✅ Weasis was running")
    else:
        feedback_parts.append("❌ Weasis was not running at the end")

    # ================================================================
    # 2. VLM Verification (Trajectory + Final State)
    # ================================================================
    if VLM_AVAILABLE and traj:
        # Sample frames from the timeline
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        prompt = """You are evaluating a medical imaging AI agent's performance in Weasis DICOM Viewer.

TASK GOAL: Import DICOMs, use the DICOM Explorer filter box to find Patient ID "TRAUMA-007", open their scan, and export a screenshot.
The target DICOM file (TRAUMA-007) contains a unique visual payload: a bright, high-contrast geometric CROSS pattern (thick vertical and horizontal lines intersecting in the center). The distractor files contain simple gradients.

Please analyze these trajectory frames and the final state, then determine:
1. "target_opened": In the final frames, is the main medical image viewer displaying the bright geometric CROSS pattern?
2. "demographics_correct": In the final frames, is the patient ID "TRAUMA-007" visible in the corner overlay text of the image viewer?
3. "worklist_filter_used": In the trajectory frames, is there evidence that the agent used the DICOM Explorer's search/filter text box (typing "TRAUMA-007" or similar) to locate the patient, rather than just clicking randomly?

Provide your response strictly in JSON format:
{
  "target_opened": boolean,
  "demographics_correct": boolean,
  "worklist_filter_used": boolean,
  "reasoning": "brief explanation"
}"""
        
        try:
            images_to_send = frames + [final] if final else frames
            vlm_result = query_vlm(images=images_to_send, prompt=prompt)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                if parsed.get("target_opened", False):
                    score += 20
                    feedback_parts.append("✅ VLM verified target image (cross pattern) opened")
                else:
                    feedback_parts.append("❌ VLM did not detect target image (cross pattern)")
                    
                if parsed.get("demographics_correct", False):
                    score += 20
                    feedback_parts.append("✅ VLM verified TRAUMA-007 demographics visible")
                else:
                    feedback_parts.append("❌ VLM did not detect TRAUMA-007 demographics")
                    
                if parsed.get("worklist_filter_used", False):
                    score += 20
                    feedback_parts.append("✅ VLM verified worklist filter box usage")
                else:
                    feedback_parts.append("❌ VLM did not detect worklist filter usage")
            else:
                feedback_parts.append("⚠️ VLM query failed or returned invalid response")
        except Exception as e:
            logger.error(f"VLM Exception: {e}")
            feedback_parts.append("⚠️ VLM verification error")
    else:
        feedback_parts.append("⚠️ VLM verification skipped (not available or no trajectory)")

    # Max score is 100. Key criteria to pass: export exists properly AND target opened
    key_criteria_met = output_exists and file_created_during_task and (score >= 80)
    passed = key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }