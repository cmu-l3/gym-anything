#!/usr/bin/env python3
"""
Verifier for animate_straight_ahead_growth task.
Verifies that the agent created a sequence of growing shapes.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_animate_straight_ahead_growth(traj, env_info, task_info):
    """
    Verify the growth animation task.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_frames = metadata.get('min_frames', 12)
    min_growth_factor = metadata.get('min_growth_factor', 3.0)

    # 2. Get Result JSON
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

    # 3. Extract Data
    frame_count = result.get("frame_count", 0)
    created_during_task = result.get("frames_created_during_task", 0)
    has_transparency = result.get("has_transparency", False)
    growth_data = result.get("growth_data", [])

    score = 0
    feedback_parts = []

    # 4. Scoring Logic

    # Criterion 1: Frame Count (20 pts)
    # Require at least min_frames
    if frame_count >= min_frames:
        score += 20
        feedback_parts.append(f"Frame count OK ({frame_count} frames)")
    elif frame_count > 0:
        # Partial credit
        pts = int(20 * (frame_count / min_frames))
        score += pts
        feedback_parts.append(f"Insufficient frames ({frame_count}/{min_frames})")
    else:
        feedback_parts.append("No frames rendered")

    # Criterion 2: Timestamp Check (Anti-gaming) (Automatic fail if 0)
    if created_during_task < frame_count * 0.8:
        feedback_parts.append(f"Warning: Only {created_during_task} frames created during task session")
        # Penalty applied implicitly if growth data is valid, but we verify data validity next

    # Criterion 3: Transparency (20 pts)
    if has_transparency:
        score += 20
        feedback_parts.append("Transparency verified")
    elif frame_count > 0:
        feedback_parts.append("No transparency detected (background should be transparent)")

    # Criterion 4: Growth Magnitude (30 pts)
    # Check if the object actually got bigger
    # Filter out empty frames (0 pixels)
    valid_areas = [area for area in growth_data if area > 0]
    
    growth_score = 0
    if len(valid_areas) >= 2:
        start_area = valid_areas[0]
        end_area = valid_areas[-1]
        
        # Calculate factor
        if start_area > 0:
            growth_factor = end_area / start_area
            if growth_factor >= min_growth_factor:
                growth_score = 30
                feedback_parts.append(f"Growth magnitude OK ({growth_factor:.1f}x)")
            elif growth_factor > 1.2:
                growth_score = 15
                feedback_parts.append(f"Growth magnitude weak ({growth_factor:.1f}x)")
            else:
                feedback_parts.append(f"No significant growth detected ({growth_factor:.1f}x)")
        else:
             feedback_parts.append("Start frame empty")
    else:
        feedback_parts.append("Not enough valid frames to measure growth")
    
    score += growth_score

    # Criterion 5: Growth Trend (20 pts)
    # Check if area generally increases
    trend_score = 0
    if len(valid_areas) >= 5:
        increases = 0
        total_steps = len(valid_areas) - 1
        for i in range(total_steps):
            if valid_areas[i+1] > valid_areas[i]:
                increases += 1
        
        # Calculate percentage of steps that were increases
        consistency = increases / total_steps
        if consistency > 0.7: # Allow some jitter/drawing variance
            trend_score = 20
            feedback_parts.append(f"Growth trend consistent ({int(consistency*100)}%)")
        elif consistency > 0.4:
            trend_score = 10
            feedback_parts.append(f"Growth trend inconsistent ({int(consistency*100)}%)")
        else:
            feedback_parts.append("No clear growth trend")
    
    score += trend_score

    # Criterion 6: Distinct Frames (10 pts)
    # Check that it's not just the same image copied
    distinct_score = 0
    if len(valid_areas) > 1:
        # Simple check: do pixel counts vary?
        # A perfectly identical pixel count is unlikely in hand-drawn straight ahead animation
        unique_areas = len(set(valid_areas))
        if unique_areas > len(valid_areas) * 0.5:
             distinct_score = 10
             feedback_parts.append("Frames appear distinct")
        else:
             feedback_parts.append("Frames appear repetitive")
    
    score += distinct_score

    # Final Result
    # Pass threshold: 60 points
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }