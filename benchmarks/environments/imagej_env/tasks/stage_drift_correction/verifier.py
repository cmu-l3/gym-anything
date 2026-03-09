#!/usr/bin/env python3
"""
Verifier for Stage Drift Correction task.

Verification Strategy:
1. Programmatic Checks (80 points):
   - Output file exists and was created during task (20 pts)
   - Output is a multi-frame stack (not a single projection) (20 pts)
   - Content matches input source (correlation check) (20 pts)
   - Stabilization Quality: Average Projection Sharpness Ratio > 1.5 (20 pts)
     (Drifting stack average is blurry; Stabilized stack average is sharp)

2. VLM Checks (20 points):
   - Trajectory verification: Did the agent use registration plugins?
   - Visual confirmation of the result.

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        return query_vlm(prompt=prompt, image=image, images=images).get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
        return None


PROCESS_PROMPT = """You are verifying an image stabilization task in Fiji (ImageJ).
Review the screenshots to see if the agent performed image registration.

Look for:
1. Menu usage: Plugins > Registration, "Correct 3D Drift", "StackReg", "TurboReg", "Template Matching".
2. Dialogs: Registration parameters, "Align", "Rigid Body", "Translation".
3. Visuals: An image stack window showing typical "black borders" moving around the edges (a side effect of stabilization).

Respond in JSON:
{
    "registration_tool_used": true/false,
    "tool_name": "name of tool if seen",
    "stabilization_artifacts_visible": true/false,
    "confidence": "low/medium/high"
}
"""


def verify_stage_drift_correction(traj, env_info, task_info):
    """
    Verify stage drift correction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load programmatic results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/stage_drift_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # Criterion 1: File Exists & Created During Task (20 pts)
    # ----------------------------------------------------------------
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Output file created")
    else:
        feedback_parts.append("Output file missing or pre-existing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # ----------------------------------------------------------------
    # Criterion 2: Is a Stack (20 pts)
    # ----------------------------------------------------------------
    if result.get("is_stack"):
        score += 20
        feedback_parts.append(f"Output is a stack ({result.get('frame_count')} frames)")
    else:
        feedback_parts.append("FAIL: Output is a single image (projection?), expected a stack")

    # ----------------------------------------------------------------
    # Criterion 3: Content Correlation (20 pts)
    # ----------------------------------------------------------------
    corr = result.get("content_correlation", 0)
    if corr > 0.5:
        score += 20
        feedback_parts.append("Content matches source")
    else:
        feedback_parts.append(f"FAIL: Content mismatch (correlation {corr:.2f})")

    # ----------------------------------------------------------------
    # Criterion 4: Stabilization Quality (Sharpness Ratio) (20 pts)
    # ----------------------------------------------------------------
    # Ratio = Output_Avg_Sharpness / Input_Avg_Sharpness
    # Drifting input -> Blurry Avg -> Low Sharpness
    # Stabilized output -> Sharp Avg -> High Sharpness
    ratio = result.get("sharpness_ratio", 0)
    if ratio > 1.4:
        score += 20
        feedback_parts.append(f"Excellent stabilization (Ratio: {ratio:.2f})")
    elif ratio > 1.1:
        score += 10
        feedback_parts.append(f"Partial stabilization (Ratio: {ratio:.2f})")
    else:
        feedback_parts.append(f"FAIL: No improvement in stability (Ratio: {ratio:.2f})")

    # ----------------------------------------------------------------
    # Criterion 5: VLM Process Verification (20 pts)
    # ----------------------------------------------------------------
    from gym_anything.vlm import sample_trajectory_frames
    frames = sample_trajectory_frames(traj, n=8)
    vlm_res = _vlm_query(env_info.get('query_vlm'), PROCESS_PROMPT, images=frames)
    
    if vlm_res and vlm_res.get("registration_tool_used"):
        score += 20
        feedback_parts.append(f"VLM confirmed usage of {vlm_res.get('tool_name', 'registration tool')}")
    else:
        # Fallback: if sharpness is really high, we trust the result even if VLM missed the menu click
        if ratio > 1.5:
            score += 20
            feedback_parts.append("VLM missed tool usage, but result confirms stabilization")
        else:
            feedback_parts.append("VLM did not observe registration tool usage")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }