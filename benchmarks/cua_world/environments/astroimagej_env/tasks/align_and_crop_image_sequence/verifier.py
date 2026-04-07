#!/usr/bin/env python3
"""
Verifier for Stabilize and Crop Time-Series Image Stack task.

Scoring criteria (100 points total):
1. Output file count exactly 20 (15 pts)
2. Dimensions are cropped (h < 4096, w < 4096) (15 pts)
3. Sub-pixel alignment achieved (shift < 1.0 px) (30 pts)
4. Edge zeros eliminated (no black padding remaining) (15 pts)
5. Data integrity intact (variance between frames > 0) (10 pts)
6. VLM trajectory verification of AstroImageJ usage (15 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent performing an image sequence alignment and cropping task in AstroImageJ.

The images are sampled chronologically. Look for evidence that the agent used AstroImageJ's GUI tools to accomplish the task.

Indicators of success:
1. SEQUENCE_IMPORTED: Is an image stack loaded in AstroImageJ (a window showing a star field image with a slider at the bottom for frames)?
2. ALIGNMENT_TOOL_USED: Do you see the "Align stack using apertures" dialog, or evidence of alignment circles placed on stars?
3. CROP_TOOL_USED: Do you see a yellow rectangle (ROI) drawn on the image, or evidence of the Image > Crop menu being accessed?

Respond in JSON format:
{
    "sequence_imported": true/false,
    "alignment_tool_used": true/false,
    "crop_tool_used": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of observations"
}
"""

def verify_align_and_crop(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # ====================================================================
    # 1. Read programmatic results from container
    # ====================================================================
    result = {}
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    if result.get("error"):
        feedback.append(f"Export script error: {result['error']}")

    # ====================================================================
    # 2. Programmatic Verification
    # ====================================================================
    
    # Criterion 1: File Count
    count = result.get("output_file_count", 0)
    if count == 20:
        score += 15
        feedback.append("✅ Exported exactly 20 files")
    elif count > 0:
        score += 5
        feedback.append(f"❌ Exported {count} files (expected 20)")
    else:
        feedback.append("❌ No output files found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Data Integrity (Prevent frame duplication gaming)
    integrity_std = result.get("data_integrity_std", 0.0)
    if integrity_std > 1.0:
        score += 10
        feedback.append("✅ Data integrity preserved (frames have expected temporal variance)")
    else:
        feedback.append("❌ Data integrity failed (frames appear identical or corrupted)")

    # Criterion 3: Cropping
    is_cropped = result.get("is_cropped", False)
    dims = result.get("dimensions", [0, 0])
    if is_cropped:
        score += 15
        feedback.append(f"✅ Images cropped successfully to {dims[0]}x{dims[1]}")
    else:
        feedback.append(f"❌ Images not cropped (dimensions {dims[0]}x{dims[1]})")

    # Criterion 4: Edge Zeros
    edge_zeros = result.get("edge_zeros_detected", True)
    if not edge_zeros and is_cropped:
        score += 15
        feedback.append("✅ Edges clean (no alignment zero-padding artifacts)")
    elif not edge_zeros:
        feedback.append("❌ Edges clean, but image wasn't cropped (raw images used?)")
    else:
        feedback.append("❌ Edge artifacts detected (black borders from alignment not fully cropped)")

    # Criterion 5: Sub-pixel alignment
    shift = result.get("shift_magnitude_px")
    if shift is not None:
        if shift < 1.0:
            score += 30
            feedback.append(f"✅ Stack aligned successfully (residual shift {shift:.2f} px)")
        elif shift < 3.0:
            score += 15
            feedback.append(f"⚠️ Stack partially aligned (residual shift {shift:.2f} px)")
        else:
            feedback.append(f"❌ Stack not aligned (residual shift {shift:.2f} px)")
    else:
        feedback.append("❌ Could not measure alignment shift")

    # ====================================================================
    # 3. VLM Verification
    # ====================================================================
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=6)
        try:
            vlm_resp = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_resp and vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                
                if parsed.get("sequence_imported"): vlm_score += 5
                if parsed.get("alignment_tool_used"): vlm_score += 5
                if parsed.get("crop_tool_used"): vlm_score += 5
                
                score += vlm_score
                feedback.append(f"VLM verified workflow: +{vlm_score} pts")
            else:
                feedback.append("VLM query failed or invalid response")
        except Exception as e:
            feedback.append(f"VLM exception: {e}")
    else:
        feedback.append("VLM unavailable - skipping visual check")

    # ====================================================================
    # Final Decision
    # ====================================================================
    # Require cropping, alignment, and proper file count to pass
    passed = (score >= 70) and is_cropped and (shift is not None and shift < 1.0) and (count == 20)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }