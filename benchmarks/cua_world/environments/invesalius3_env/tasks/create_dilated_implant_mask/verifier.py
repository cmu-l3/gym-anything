#!/usr/bin/env python3
"""
Verifier for create_dilated_implant_mask task.

Criteria:
1. Files Exist (20 pts): Both anatomical and dilated STLs must exist.
2. Valid STLs (20 pts): Both must be valid binary STLs created during the task.
3. Baseline Volume (20 pts): Anatomical skull volume must be realistic (>500 cm3).
4. Dilation Verified (40 pts): Dilated volume > 1.02 * Anatomical volume.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_dilated_implant_mask(traj, env_info, task_info):
    """Verify the agent created a normal and a dilated skull model."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_volume = metadata.get("min_volume_cm3", 500.0)
    dilation_ratio = metadata.get("dilation_ratio_threshold", 1.02)

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/dilated_mask_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}"
        }

    score = 0
    feedback_parts = []
    
    anat = result.get("anatomical", {})
    dil = result.get("dilated", {})
    comp = result.get("comparison", {})

    # Criterion 1: Files Exist (20 pts)
    if anat.get("exists") and dil.get("exists"):
        score += 20
        feedback_parts.append("Both STL files created")
    else:
        feedback_parts.append("One or both STL files missing")

    # Criterion 2: Valid STLs & Created During Task (20 pts)
    if anat.get("valid") and dil.get("valid") and anat.get("created_during_task") and dil.get("created_during_task"):
        score += 20
        feedback_parts.append("Files are valid STLs and newly created")
    elif anat.get("valid") and dil.get("valid"):
        # Valid but maybe pre-existing? (Anti-gaming)
        score += 10
        feedback_parts.append("Files valid but timestamp check failed/inconclusive")
    else:
        feedback_parts.append("Files are invalid or corrupt")

    # Criterion 3: Baseline Volume Plausible (20 pts)
    vol_anat = anat.get("volume", 0.0)
    if vol_anat > min_volume:
        score += 20
        feedback_parts.append(f"Anatomical volume realistic ({vol_anat:.1f} cm3)")
    else:
        feedback_parts.append(f"Anatomical volume too small ({vol_anat:.1f} cm3 < {min_volume})")

    # Criterion 4: Dilation Verified (40 pts)
    ratio = comp.get("volume_ratio", 0.0)
    vol_dil = dil.get("volume", 0.0)
    
    if ratio >= dilation_ratio:
        score += 40
        feedback_parts.append(f"Dilation confirmed (Ratio: {ratio:.3f} > {dilation_ratio})")
    elif ratio > 1.0:
        # It is larger, but not by enough (maybe micro-dilation?)
        score += 20
        feedback_parts.append(f"Dilated model is larger but below threshold (Ratio: {ratio:.3f})")
    elif ratio > 0:
        feedback_parts.append(f"Dilated model is not larger than anatomical (Ratio: {ratio:.3f})")
    else:
        feedback_parts.append("Comparison failed (invalid volumes)")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "anatomical_volume": vol_anat,
            "dilated_volume": vol_dil,
            "ratio": ratio
        }
    }