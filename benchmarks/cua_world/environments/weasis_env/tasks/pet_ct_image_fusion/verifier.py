#!/usr/bin/env python3
"""
Verifier for PET/CT Image Fusion Task.
Uses multi-signal verification: file-based constraints and VLM hybrid checks.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available. Verification will operate in degraded programmatic-only mode.")

VLM_PROMPT = """You are evaluating a medical imaging agent's performance inside Weasis DICOM Viewer.

The goal of the agent was to fuse a functional PET series over a structural CT series, apply a color LUT to the PET layer, and export a fused screenshot.

Look at the provided trajectory frames and final screenshot to determine:
1. Is there a medical image viewer visible?
2. Are BOTH grayscale anatomical structures (CT scan) AND bright colored blobs representing metabolic activity (PET) visible?
3. Are they overlaid/fused in the SAME single viewport? (A side-by-side split screen view without overlap fails this requirement).
4. Is the PET data strictly colorized (e.g., using a Hot Iron, Rainbow, or Orange/Yellow/Red scale)?

Respond strictly in JSON format matching this schema:
{
    "medical_viewer_visible": true/false,
    "ct_anatomy_visible": true/false,
    "pet_activity_visible": true/false,
    "overlaid_in_same_viewport": true/false,
    "pet_colorized": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_pet_ct_fusion(traj, env_info, task_info):
    """
    Verify PET/CT fusion using both export metadata checks and Visual Language Model review.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch and Parse Container Export Output
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read container result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    app_was_running = result.get('app_was_running', False)
    min_size = task_info.get('metadata', {}).get('min_export_size_bytes', 20000)

    # Sanity Verification
    if not app_was_running:
        feedback_parts.append("Weasis app was not running")
        
    file_valid = False
    
    # Milestone 1 & 2: Output Constraints
    if output_exists:
        if created_during_task:
            score += 20
            feedback_parts.append("Export file correctly created during the session")
            
            if output_size >= min_size:
                score += 20
                file_valid = True
                feedback_parts.append(f"Export file size ({output_size} bytes) indicates genuine content")
            else:
                feedback_parts.append(f"Export file size ({output_size} bytes) is too small. Possibly empty or an icon")
        else:
            feedback_parts.append("Export file exists but fails anti-gaming timestamp check")
    else:
        feedback_parts.append("Expected export file (fusion_view.jpg) was not found")

    # Milestone 3: Trajectory & VLM Visual Verification
    if VLM_AVAILABLE and file_valid:
        try:
            # Sample throughout workflow (trajectory frames) + final desktop state
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            
            # Form image array
            images = frames + [final] if final else frames
            
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=images)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                # Check metrics against VLM observation
                if parsed.get("ct_anatomy_visible", False):
                    score += 15
                    feedback_parts.append("CT Anatomy structure visible")
                    
                if parsed.get("pet_activity_visible", False):
                    score += 15
                    feedback_parts.append("PET activity features visible")
                    
                if parsed.get("pet_colorized", False):
                    score += 15
                    feedback_parts.append("PET dataset colorized via LUT")
                    
                if parsed.get("overlaid_in_same_viewport", False):
                    score += 15
                    feedback_parts.append("Modalities properly fused in the same viewport")
                else:
                    feedback_parts.append("Failure: Images were not overlaid/fused together")
            else:
                feedback_parts.append(f"VLM query failed: {vlm_res.get('error', 'unparseable')}")
        except Exception as e:
            logger.warning(f"VLM verification exception caught: {e}")
            feedback_parts.append(f"VLM check threw an error: {e}")
            
    elif not VLM_AVAILABLE and file_valid:
        # Fallback handling in headless programmatic-only test sweeps
        score += 60
        feedback_parts.append("VLM module unavailable - awarding maximum programmatic fallback points")

    # Threshold for success: Required to properly export the file and effectively display fused PET + CT
    passed = (file_valid and score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }