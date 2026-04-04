#!/usr/bin/env python3
"""
Verifier for channel_montage_creation task.

Verification Strategy:
1. File Verification (Programmatic - 60 pts):
   - Result file exists and is a valid TIFF.
   - Dimensions indicate a montage (larger than single 512x512 panel).
   - Content is not blank (pixel std dev > 10).
   - Created after task start.

2. Workflow Verification (VLM - 40 pts):
   - Uses trajectory frames.
   - Verification of channel splitting (multiple image windows).
   - Verification of montage creation dialog or result.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logger = logging.getLogger(__name__)

# VLM Prompt for workflow verification
WORKFLOW_PROMPT = """You are verifying an ImageJ task where the user must:
1. Open a cell image.
2. Split it into 3 channels (Red, Green, Blue).
3. Create a montage combining these channels.

Look at the sequence of screenshots.
Does the agent perform these steps?

Check for:
- "SPLIT_CHANNELS": Do you see multiple image windows appear (often titled with C1, C2, C3 or Red/Green/Blue)?
- "MONTAGE_CREATION": Do you see a "Make Montage" dialog or a final window showing multiple panels stitched together?
- "FINAL_RESULT": Is there a final image visible that looks like a grid of 4 similar cell images?

Respond in JSON:
{
    "split_channels_observed": true/false,
    "montage_dialog_or_result_observed": true/false,
    "final_montage_visible": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_channel_montage_creation(traj, env_info, task_info):
    """
    Verify creation of multi-channel montage.
    
    Pass threshold: 60 points.
    """
    # 1. Setup copy from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Query VLM on trajectory
    vlm_result = {}
    if traj:
        from gym_anything.vlm import query_vlm
        try:
            frames = sample_trajectory_frames(traj, n=6)
            response = query_vlm(
                images=frames,
                prompt=WORKFLOW_PROMPT
            )
            if response.get('success'):
                vlm_result = response.get('parsed', {})
        except Exception as e:
            logger.warning(f"VLM query failed: {e}")

    # 3. Load Programmatic Results
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        copy_from_env("/tmp/channel_montage_creation_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    # 4. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Validity (15 pts)
    if result.get('file_exists') and result.get('is_valid_image'):
        score += 15
        feedback_parts.append("Valid TIFF file created")
    else:
        feedback_parts.append("FAIL: No valid TIFF file found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Timestamp (10 pts)
    if result.get('timestamp_valid'):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("FAIL: File predates task start (anti-gaming)")

    # Criterion 3: Dimensions / Montage Check (25 pts)
    # Source image is 512x512. A montage of 4 panels should be significantly larger.
    # At least one dimension should be > 700 (e.g. 1024x1024 or 2048x512)
    w = result.get('width', 0)
    h = result.get('height', 0)
    total_area = result.get('total_area', 0)
    
    # 512*512 = 262144. 4 panels ~ 1,000,000 pixels.
    # We set a threshold that proves it's not just a single panel copy.
    if (w > 700 or h > 700) and total_area > 300000:
        score += 25
        feedback_parts.append(f"Dimensions indicate montage ({w}x{h})")
    else:
        feedback_parts.append(f"FAIL: Dimensions too small ({w}x{h}) - expected multi-panel montage >700px")

    # Criterion 4: Content Sanity Check (10 pts)
    # Standard deviation > 10 implies image has contrast (not blank/solid)
    if result.get('pixel_std', 0) > 10:
        score += 10
        feedback_parts.append("Image content valid (not blank)")
    else:
        feedback_parts.append("FAIL: Image appears blank or solid color")

    # Criterion 5: VLM Workflow Verification (40 pts)
    vlm_score = 0
    if vlm_result.get('split_channels_observed'):
        vlm_score += 15
    if vlm_result.get('montage_dialog_or_result_observed') or vlm_result.get('final_montage_visible'):
        vlm_score += 25
    
    # Normalize VLM score to max 40
    score += vlm_score
    if vlm_score > 0:
        feedback_parts.append(f"VLM verified workflow ({vlm_score}/40 pts)")
    else:
        feedback_parts.append("VLM did not detect channel splitting or montage steps")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "programmatic_result": result,
            "vlm_result": vlm_result
        }
    }