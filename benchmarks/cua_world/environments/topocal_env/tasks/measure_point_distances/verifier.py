#!/usr/bin/env python3
"""
Verifier for measure_point_distances task.

Uses robust regex parsing to extract distances and verifies them
against randomly generated ground truth coordinate geometry.
Includes multi-signal evaluation: File Timestamps, Content Matching, and VLM Trajectory.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_measure_point_distances(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve generated ground truth
    gt_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ground_truth = {}
    try:
        copy_from_env("C:\\tmp\\ground_truth_distances.json", gt_file.name)
        with open(gt_file.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read ground truth: {e}")
    finally:
        if os.path.exists(gt_file.name):
            os.unlink(gt_file.name)

    # 2. Retrieve task execution result
    res_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", res_file.name)
        with open(res_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(res_file.name):
            os.unlink(res_file.name)

    score = 0
    feedback_parts = []
    
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    content = result.get('file_content', '')

    # Check Output Existence & Timing (Anti-Gaming)
    if output_exists:
        score += 10
        feedback_parts.append("✅ Output file exists")
    else:
        return {"passed": False, "score": 0, "feedback": "❌ Output file distances.txt not found"}

    if file_created:
        score += 5
        feedback_parts.append("✅ File created during task")
    else:
        feedback_parts.append("❌ File timestamp precedes task start (stale)")

    # 3. Parse File Content and Compare with Ground Truth
    correct_count = 0
    pairs = ['A', 'B', 'C', 'D', 'E']
    
    for pair in pairs:
        gt_dist = ground_truth.get(pair)
        if gt_dist is None:
            continue
            
        # Regex extracts decimal values linked to the specific pair
        # e.g., "Pair A (3-17): 123.45 m" -> extracts "123.45"
        pattern = rf"Pair\s*{pair}.*?(\d+[\.,]\d+)"
        match = re.search(pattern, content, re.IGNORECASE)
        
        if match:
            try:
                # Handle possible European decimal commas
                measured_str = match.group(1).replace(',', '.')
                measured = float(measured_str)
                
                # Check within ±0.50m tolerance
                diff = abs(measured - gt_dist)
                if diff <= 0.50:
                    score += 12
                    correct_count += 1
                    feedback_parts.append(f"✅ Pair {pair} correct")
                else:
                    feedback_parts.append(f"❌ Pair {pair} incorrect (expected ~{gt_dist:.2f}, got {measured:.2f})")
            except ValueError:
                feedback_parts.append(f"❌ Pair {pair} unparseable value")
        else:
            feedback_parts.append(f"❌ Pair {pair} missing in file")

    # 4. VLM Trajectory Process Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are verifying if an agent performed distance measurements in TopoCal CAD software.
Look at these trajectory screenshots across the workflow.
1. Are survey points loaded and visible in the TopoCal drawing area?
2. Is there evidence of the agent using a measurement tool (e.g. distance query dialog, measurement line drawn, or measurement tool active)?
3. Were there any blocking error dialogs?

Respond in JSON format exactly:
{
    "points_visible": true/false,
    "measurement_tool_used": true/false,
    "no_error_dialogs": true/false
}"""
            query_func = env_info.get('query_vlm')
            if query_func:
                vlm_res = query_func(prompt=prompt, images=frames)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('measurement_tool_used', False):
                        score += 10
                        feedback_parts.append("✅ VLM: Measurement tool used")
                    if parsed.get('points_visible', False):
                        score += 10
                        feedback_parts.append("✅ VLM: Points visible")
                    if parsed.get('no_error_dialogs', False):
                        score += 5
                        feedback_parts.append("✅ VLM: No errors")
                else:
                    feedback_parts.append("⚠️ VLM parsing error")
            else:
                feedback_parts.append("⚠️ VLM query function unavailable")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("⚠️ VLM verification skipped")

    # Pass condition: File must exist, scoring >= 60, and at least 3 out of 5 distances correctly measured.
    passed = score >= 60 and correct_count >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }