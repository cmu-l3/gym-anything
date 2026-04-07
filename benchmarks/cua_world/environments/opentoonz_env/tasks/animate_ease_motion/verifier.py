#!/usr/bin/env python3
"""
Verifier for animate_ease_motion task.

Verifies:
1. Files rendered successfully (PNG sequence).
2. Character moves horizontally.
3. Motion exhibits "Ease In" (slow start) and "Ease Out" (slow end).
"""

import json
import tempfile
import os
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_animate_ease_motion(traj, env_info, task_info):
    """Verify Ease In/Ease Out animation task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    score = 0
    feedback_parts = []
    
    # 1. Check File Creation (20 pts)
    file_count = result.get("file_count", 0)
    new_files = result.get("new_files_count", 0)
    
    if new_files >= 20:
        score += 20
        feedback_parts.append(f"Render successful ({new_files} frames)")
    elif new_files > 0:
        score += 10
        feedback_parts.append(f"Partial render ({new_files} frames)")
    else:
        feedback_parts.append("No new frames rendered")
        return {"passed": False, "score": 0, "feedback": "No output files created"}

    # 2. Check Content (10 pts)
    analysis = result.get("motion_analysis", {})
    if analysis.get("asset_detected", False):
        score += 10
        feedback_parts.append("Asset content detected")
    else:
        feedback_parts.append("Frames appear empty")
        # Continue checking but max score limited

    # 3. Analyze Motion Profile
    centroids_x = analysis.get("centroids_x", [])
    
    # Filter out empty frames (-1.0)
    valid_x = [x for x in centroids_x if x > 0]
    
    if len(valid_x) < 10:
        feedback_parts.append("Not enough valid frames for motion analysis")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check Total Distance (20 pts)
    start_x = valid_x[0]
    end_x = valid_x[-1]
    total_dist = end_x - start_x
    
    # Check direction (Left to Right means x increases)
    if total_dist > 100:
        score += 20
        feedback_parts.append("Horizontal motion detected")
    elif total_dist < -100:
        score += 10 # Wrong direction but moved
        feedback_parts.append("Motion detected (reverse direction)")
        # Normalize for analysis
        valid_x = valid_x[::-1]
        start_x = valid_x[0]
        end_x = valid_x[-1]
        total_dist = end_x - start_x
    else:
        feedback_parts.append("No significant horizontal motion")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. Check Ease In / Ease Out (50 pts)
    # Normalize positions to 0.0 - 1.0 range
    # Normalize time to 0.0 - 1.0 range
    
    num_frames = len(valid_x)
    normalized_pos = [(x - start_x) / total_dist for x in valid_x]
    
    # Check "Ease In" (Slow Start)
    # At 25% of time, position should be significantly LESS than 25% (linear)
    # Typical Ease In: at 0.25 time, pos is ~0.1 to 0.15
    idx_25 = int(num_frames * 0.25)
    pos_at_25 = normalized_pos[idx_25]
    
    # Linear would be ~0.25. Threshold < 0.20 implies easing.
    if pos_at_25 < 0.20:
        score += 25
        feedback_parts.append(f"Ease-In verified (Pos@25%: {pos_at_25:.2f})")
    else:
        feedback_parts.append(f"No Ease-In detected (Pos@25%: {pos_at_25:.2f}, expected <0.20)")

    # Check "Ease Out" (Slow End)
    # At 75% of time, position should be significantly MORE than 75% (linear)
    # Because it sped up in the middle to compensate, it's now slowing down (curve flattens)
    # Typical Ease Out: at 0.75 time, pos is ~0.85 to 0.9
    idx_75 = int(num_frames * 0.75)
    pos_at_75 = normalized_pos[idx_75]
    
    # Linear would be ~0.75. Threshold > 0.80 implies easing.
    if pos_at_75 > 0.80:
        score += 25
        feedback_parts.append(f"Ease-Out verified (Pos@75%: {pos_at_75:.2f})")
    else:
        feedback_parts.append(f"No Ease-Out detected (Pos@75%: {pos_at_75:.2f}, expected >0.80)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }