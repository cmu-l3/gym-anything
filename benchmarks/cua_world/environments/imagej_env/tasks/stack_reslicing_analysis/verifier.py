#!/usr/bin/env python3
"""
Verifier for stack_reslicing_analysis task.

Task:
1. Open Fly Brain (256x256x57 RGB)
2. Convert to 8-bit
3. Reslice (Top) -> Result is 256x57x256
4. Z-Project (Max) -> Result is 256x57 (2D)
5. Save

Scoring Criteria:
1. File Creation (20 pts): Output file exists and was created during task.
2. Dimensions (40 pts): Width ~256, Height ~57.
   - This dimension signature (256x57) specifically proves reslicing occurred.
   - A standard Z-project of the original would be 256x256.
3. Projection (20 pts): Image is a single slice (n_frames = 1), not a stack.
4. Format (20 pts): Image is 8-bit (mode 'L' or 'P').

Bonus/Safety: VLM check on trajectory to ensure steps were followed.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_stack_reslicing(traj, env_info, task_info):
    """
    Verify the Fly Brain reslicing task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env function unavailable"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    exp_w = metadata.get('expected_width', 256)
    exp_h = metadata.get('expected_height', 57)
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_file.close()
        try:
            copy_from_env("/tmp/stack_reslicing_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        
        # 1. File Creation (20 pts)
        if result.get('file_exists') and result.get('file_created_during_task'):
            score += 20
            feedback_parts.append("Output file created successfully")
        elif result.get('file_exists'):
            feedback_parts.append("Output file exists but timestamp predates task")
        else:
            feedback_parts.append("Output file not found")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # 2. Dimensions (40 pts) - The critical check
        # Allow +/- 2 pixel tolerance
        w = result.get('width', 0)
        h = result.get('height', 0)
        
        w_ok = abs(w - exp_w) <= 2
        h_ok = abs(h - exp_h) <= 2
        
        if w_ok and h_ok:
            score += 40
            feedback_parts.append(f"Dimensions correct ({w}x{h})")
        else:
            feedback_parts.append(f"Incorrect dimensions: Got {w}x{h}, expected {exp_w}x{exp_h}")
            if w == 256 and h == 256:
                feedback_parts.append("(Hint: It looks like you projected the original stack without reslicing)")

        # 3. Projection check (20 pts)
        n_frames = result.get('n_frames', 1)
        if n_frames == 1:
            score += 20
            feedback_parts.append("Image is flattened (single slice)")
        else:
            feedback_parts.append(f"Image is still a stack ({n_frames} slices)")

        # 4. Format check (20 pts)
        if result.get('is_8bit'):
            score += 20
            feedback_parts.append("Format is 8-bit")
        else:
            mode = result.get('mode', 'unknown')
            feedback_parts.append(f"Incorrect format: {mode} (expected 8-bit grayscale)")

        # 5. Content check (Sanity)
        if result.get('mean_intensity', 0) < 1.0:
            score = 0
            feedback_parts.append("Image appears to be empty/black")

        passed = score >= 80  # Requires dimensions to be correct
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}