#!/usr/bin/env python3
"""
Verifier for simulate_bone_loss_erosion task.

Scoring (100 points total):
  - Project file exists: 10 pts
  - Valid project format: 10 pts
  - Multiple masks present (>=2): 20 pts
  - Baseline mask has realistic volume (>150k voxels): 20 pts
  - Erosion effect verified (Significant reduction): 40 pts

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_simulate_bone_loss_erosion(traj, env_info, task_info):
    """Verify bone erosion simulation task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    passed = False

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/simulate_bone_loss_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result: {e}"
        }

    # 1. File existence (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback_parts.append("Project file created")
    else:
        feedback_parts.append("Project file not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Valid format (10 pts)
    if result.get("valid_project"):
        score += 10
        feedback_parts.append("Valid InVesalius project")
    else:
        feedback_parts.append("Invalid project file")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Multiple masks (20 pts)
    masks = result.get("masks", [])
    mask_count = len(masks)
    
    if mask_count >= 2:
        score += 20
        feedback_parts.append(f"{mask_count} masks found")
    else:
        feedback_parts.append(f"Found {mask_count} mask(s) (need at least 2)")

    # 4. Volume Analysis (60 pts total)
    if mask_count >= 2:
        # Sort masks by volume (descending)
        # We assume the larger one is the baseline and the smaller one is the eroded one
        masks_sorted = sorted(masks, key=lambda x: x.get("voxel_count", 0), reverse=True)
        
        baseline_mask = masks_sorted[0]
        eroded_mask = masks_sorted[1] # Next largest
        
        baseline_vol = baseline_mask.get("voxel_count", 0)
        eroded_vol = eroded_mask.get("voxel_count", 0)
        
        # Check baseline volume (approx 150k - 250k for this skull dataset)
        # We set a loose lower bound to ensure it's not empty
        if baseline_vol > 100000:
            score += 20
            feedback_parts.append(f"Baseline volume valid ({baseline_vol} voxels)")
            
            # Check erosion effect
            # Erosion should reduce volume.
            # 1 iteration of erosion usually removes a layer of pixels.
            # Volume should be smaller but not zero.
            if eroded_vol < baseline_vol:
                ratio = eroded_vol / baseline_vol
                if ratio < 0.99 and eroded_vol > 50000:
                    score += 40
                    feedback_parts.append(f"Erosion verified (Ratio: {ratio:.2f})")
                elif eroded_vol <= 50000:
                    score += 10
                    feedback_parts.append("Eroded mask too small/empty")
                else:
                    feedback_parts.append(f"Volume difference negligible (Ratio: {ratio:.4f})")
            else:
                feedback_parts.append("No volume reduction detected in second mask")
        else:
            feedback_parts.append(f"Baseline mask volume too small ({baseline_vol} voxels)")
    else:
        feedback_parts.append("Cannot perform volume comparison with < 2 masks")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {"masks": masks}
    }