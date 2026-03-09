#!/usr/bin/env python3
"""Verifier for grain_boundary_measurement task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_grain_boundary_measurement(traj, env_info, task_info):
    """
    Verify Grain Boundary Measurement task.

    Scoring (100 points total):
    - Criterion 1: Result file exists, non-empty, created after task start (20 pts)
    - Criterion 2: Image dimensions recorded (width/height > 50) (15 pts)
    - Criterion 3: Total boundary length measured (> 100 px) (25 pts)
    - Criterion 4: Boundary density calculated (0 < density < 1.0) (25 pts)
    - Criterion 5: Data consistency (Density ~ Length/Area) (15 pts)

    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/grain_boundary_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(temp_file.name)
            except Exception:
                pass

        score = 0
        feedback_parts = []
        subscores = {}

        # ----------------------------------------------------------------
        # Criterion 1: File integrity and timestamp
        # ----------------------------------------------------------------
        file_exists = result.get('file_exists', False)
        file_size = result.get('file_size_bytes', 0)
        file_time = result.get('file_modified_time', 0)
        task_start = result.get('task_start_timestamp', 0)

        if file_exists and file_size > 10:
            if task_start > 0 and file_time < task_start:
                feedback_parts.append("FAIL: Result file predates task start")
                subscores["file_valid"] = False
            else:
                score += 20
                subscores["file_valid"] = True
                feedback_parts.append(f"File created ({file_size} bytes)")
        else:
            subscores["file_valid"] = False
            feedback_parts.append("FAIL: Result file not found or empty")

        # ----------------------------------------------------------------
        # Criterion 2: Image dimensions
        # ----------------------------------------------------------------
        width = result.get('width', 0)
        height = result.get('height', 0)
        
        if width > 50 and height > 50:
            score += 15
            subscores["dimensions"] = True
            feedback_parts.append(f"Dimensions found ({width:.0f}x{height:.0f})")
        else:
            subscores["dimensions"] = False
            feedback_parts.append("FAIL: Valid image dimensions not found")

        # ----------------------------------------------------------------
        # Criterion 3: Boundary Length
        # ----------------------------------------------------------------
        length = result.get('boundary_length', 0)
        if length > 100:
            score += 25
            subscores["length"] = True
            feedback_parts.append(f"Boundary length measured ({length:.1f} px)")
        else:
            subscores["length"] = False
            feedback_parts.append(f"FAIL: Boundary length too small or missing ({length})")

        # ----------------------------------------------------------------
        # Criterion 4: Boundary Density
        # ----------------------------------------------------------------
        density = result.get('boundary_density', 0)
        if 0 < density < 1.0:
            score += 25
            subscores["density"] = True
            feedback_parts.append(f"Density valid ({density:.4f} px^-1)")
        else:
            subscores["density"] = False
            feedback_parts.append(f"FAIL: Density invalid or missing ({density})")

        # ----------------------------------------------------------------
        # Criterion 5: Consistency Check
        # ----------------------------------------------------------------
        # If we have all metrics, check if Density is roughly Length / Area
        # We allow a large margin of error because 'Area' might be total image area 
        # or ROI area, and density calculation methods vary.
        consistency_bonus = False
        if width > 0 and height > 0 and length > 0 and density > 0:
            area = width * height
            calc_density = length / area
            # If calculated density is within factor of 10 of reported density
            # (Allows for unit differences like % vs fraction, or ROI vs Image)
            ratio = density / calc_density if calc_density > 0 else 0
            if 0.1 <= ratio <= 10.0:
                consistency_bonus = True
        
        if consistency_bonus:
            score += 15
            subscores["consistency"] = True
            feedback_parts.append("Data is consistent")
        else:
            # If we missed data, we can't check consistency
            subscores["consistency"] = False
            if subscores["density"] and subscores["length"]:
                feedback_parts.append("Data inconsistency detected")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": subscores
        }

    except Exception as e:
        logger.exception("Verification error")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}