#!/usr/bin/env python3
"""
Verifier for AstroImageJ align_time_series task.

Verification Criteria:
1. Output FITS file exists (10 pts)
2. FITS file created/modified during task (10 pts)
3. FITS file is a 10-frame 3D cube (20 pts)
4. Anti-gaming: Frames are distinct, not just clones (variance > 1.0) (10 pts)
5. Alignment: Remaining drift < 15.0 px (Partial Alignment) (15 pts)
6. Alignment: Remaining drift < 2.0 px (Perfect Alignment) (25 pts)
7. VLM: Agent workflow verified from trajectory frames (10 pts)
"""

import os
import json
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_align_time_series(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_frames = metadata.get('expected_frames', 10)
    perf_tol = metadata.get('tolerances', {}).get('perfect_alignment_px', 2.0)
    part_tol = metadata.get('tolerances', {}).get('partial_alignment_px', 15.0)

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result from container
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

    # 2. Check File Existence & Timestamp
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if output_exists:
        score += 10
        feedback_parts.append("Output file exists")
        if file_created:
            score += 10
            feedback_parts.append("File correctly modified during task")
        else:
            feedback_parts.append("Warning: File existed before task start (not modified)")
    else:
        feedback_parts.append("Output file aligned_stack.fits NOT found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Check FITS Integrity & Structure
    fits_analyzed = result.get('fits_analyzed', False)
    if not fits_analyzed:
        err = result.get('error', 'Unknown error analyzing FITS')
        feedback_parts.append(f"FITS Error: {err}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    shape = result.get('shape', [])
    if len(shape) == 3 and shape[0] == expected_frames:
        score += 20
        feedback_parts.append(f"Valid {expected_frames}-frame FITS cube")
    else:
        feedback_parts.append(f"Invalid FITS shape: {shape}. Expected (10, H, W)")

    # 4. Anti-Gaming (Variance Check)
    variance = result.get('variance', 0.0)
    if variance > 1.0:
        score += 10
        feedback_parts.append("Anti-gaming passed (frames are distinct)")
    else:
        feedback_parts.append(f"Anti-gaming failed: Variance too low ({variance:.2f}). Frames appear to be identical clones.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 5. Alignment Accuracy
    shift_mag = result.get('shift_magnitude', 999.0)
    if shift_mag <= perf_tol:
        score += 40  # 15 (partial) + 25 (perfect)
        feedback_parts.append(f"Perfect alignment achieved (drift: {shift_mag:.2f}px)")
    elif shift_mag <= part_tol:
        score += 15
        feedback_parts.append(f"Partial alignment achieved (drift: {shift_mag:.2f}px)")
    else:
        feedback_parts.append(f"Alignment failed: Drift too high ({shift_mag:.2f}px)")

    # 6. VLM Verification of Trajectory
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "Review these screenshots of AstroImageJ. "
            "Did the user open the 'Align stack using WCS or apertures' tool "
            "or use the Aperture selection tool (circle cursors) to select a reference star?"
        )
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        if "yes" in vlm_result.lower() or "true" in vlm_result.lower():
            score += 10
            feedback_parts.append("VLM verified use of alignment tools")
        else:
            feedback_parts.append("VLM did not clearly detect alignment tool usage")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Gracefully skip VLM points if VLM is unavailable, just note it.
        feedback_parts.append("VLM verification skipped/failed")

    # Evaluate Pass/Fail
    passed = score >= 70 and output_exists and shift_mag <= perf_tol

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "variance": variance,
            "shift_magnitude": shift_mag
        }
    }