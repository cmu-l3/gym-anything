#!/usr/bin/env python3
"""
Verifier for manual_neck_crop_segmentation task.

Criteria:
1. File exists and is a valid NIfTI (20 pts)
2. Dimensions match original CT (512x512x108) (20 pts)
3. Bottom 10 slices (index 0-9) are completely empty (40 pts)
4. Middle slices (e.g. index 54) have bone content (20 pts)

Pass threshold: 80 points
"""

import json
import os
import tempfile
import logging
import sys
import numpy as np

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing nibabel, usually available in verifier env or installed
try:
    import nibabel as nib
    NIBABEL_AVAILABLE = True
except ImportError:
    NIBABEL_AVAILABLE = False


def ensure_nibabel():
    """Install nibabel if missing."""
    global NIBABEL_AVAILABLE, nib
    if not NIBABEL_AVAILABLE:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
            import nibabel
            nib = nibabel
            NIBABEL_AVAILABLE = True
        except Exception as e:
            logger.error(f"Failed to install nibabel: {e}")
            return False
    return True


def verify_manual_neck_crop_segmentation(traj, env_info, task_info):
    """Verify the segmented NIfTI file has the neck crop applied."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    expected_shape = tuple(metadata.get("expected_shape", [512, 512, 108]))
    slices_to_clear = metadata.get("slices_to_clear", 10)
    min_bone_voxels = metadata.get("min_bone_voxels_center", 1000)

    score = 0
    feedback_parts = []
    
    # 1. Get basic export info
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/export_result.json", tmp_json.name)
        with open(tmp_json.name) as f:
            export_info = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve export info: {e}"}

    if not export_info.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    if not export_info.get("created_during_task"):
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this task run")
        # We proceed but this is suspicious

    # 2. Get the actual NIfTI file for analysis
    if not ensure_nibabel():
        return {"passed": False, "score": 0, "feedback": "Verifier failed to load image library"}

    try:
        tmp_nii = tempfile.NamedTemporaryFile(delete=False, suffix=".nii.gz")
        tmp_nii.close()
        copy_from_env("/home/ga/Documents/cleaned_skull.nii.gz", tmp_nii.name)
        
        img = nib.load(tmp_nii.name)
        data = img.get_fdata()
        header = img.header
        
        # Criterion 1: Valid NIfTI
        score += 20
        feedback_parts.append("Valid NIfTI file")
        
        # Criterion 2: Dimensions
        # Data shape in nibabel is typically (X, Y, Z)
        # Note: InVesalius might export 4D (X, Y, Z, 1). Handle that.
        shape = data.shape
        if len(shape) == 4 and shape[3] == 1:
            shape = shape[:3]
            data = data[:, :, :, 0]
            
        if shape == expected_shape:
            score += 20
            feedback_parts.append(f"Correct dimensions {shape}")
        else:
            feedback_parts.append(f"Incorrect dimensions: {shape} (expected {expected_shape})")
            # If dimensions are wrong, we probably can't check slices accurately
            os.unlink(tmp_nii.name)
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # Criterion 3: Bottom slices empty
        # We check index 0 to slices_to_clear
        # InVesalius imports 0051 (CT Cranium) such that slice 1 is index 0.
        bottom_slab = data[:, :, :slices_to_clear]
        bottom_sum = np.sum(bottom_slab)
        
        # Safety check: Agent might have flipped Z. Check top slab too just in case?
        # Task said "Axial Slice 1-10", which is index 0-9. Stick to that.
        
        if bottom_sum == 0:
            score += 40
            feedback_parts.append(f"Bottom {slices_to_clear} slices successfully cleared")
        else:
            feedback_parts.append(f"Bottom slices NOT empty (found {int(bottom_sum)} voxels)")
            
        # Criterion 4: Middle content preserved
        # Check middle slice (index ~54)
        mid_z = expected_shape[2] // 2
        mid_slice_sum = np.sum(data[:, :, mid_z])
        
        if mid_slice_sum > min_bone_voxels:
            score += 20
            feedback_parts.append(f"Bone anatomy preserved in center ({int(mid_slice_sum)} voxels)")
        else:
            feedback_parts.append("Center slice is empty or missing bone anatomy")

        os.unlink(tmp_nii.name)
        
    except Exception as e:
        feedback_parts.append(f"Failed to analyze NIfTI content: {e}")
        if os.path.exists(tmp_nii.name):
            os.unlink(tmp_nii.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }