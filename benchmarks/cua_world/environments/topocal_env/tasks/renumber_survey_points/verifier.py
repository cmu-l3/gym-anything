#!/usr/bin/env python3
"""
Verifier for renumber_survey_points task in TopoCal.

ROBUST MULTI-SIGNAL VERIFICATION:
1. File exists and was created DURING task (anti-gaming) -> 10 pts
2. Exact correct point count exported (45) -> 10 pts
3. Formatting shows strictly sequential numbering (1001-1045) -> 20 pts
4. XYZ coordinates match the ground truth without corruption -> 30 pts
5. The points correspond to the sequentially sorted original inputs -> 15 pts
6. VLM Trajectory Evidence shows TopoCal interface usage -> 15 pts
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully renumbered survey points using TopoCal.

TASK: Renumber 45 survey points sequentially starting from 1001 and export them.

Look at these trajectory screenshots and determine:
1. Did the agent interact with TopoCal's point renumbering tools (e.g., "Puntos" -> "Renumerar" or editing tools)?
2. Is there evidence of a point list/table inside TopoCal showing points numbered 1001, 1002, etc.?
3. Did the agent use TopoCal's export functionality to save the points (e.g., File -> Export)?

Respond in JSON format:
{
    "used_topocal_renumbering": true/false,
    "sequential_numbers_visible": true/false,
    "used_export_function": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_renumber_survey_points(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. READ EXPORT RESULT JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)

    if output_exists and file_created:
        score += 10
        feedback_parts.append("Export file created during task (+10)")
    elif output_exists:
        score += 5
        feedback_parts.append("Export file exists but predates task (+5)")
    else:
        feedback_parts.append("Export file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. READ GROUND TRUTH JSON
    ground_truth = []
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Failed to load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # 3. PARSE AGENT EXPORTED FILE
    points_data = []
    temp_pts = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("C:/Users/Docker/Documents/renumbered_points.txt", temp_pts.name)
        with open(temp_pts.name, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()
                if not line: continue
                # Handle possible delimiters used by agent (comma, tab, semicolon)
                parts = re.split(r'[,\t;]+', line)
                parts = [p.strip() for p in parts if p.strip()]
                if len(parts) >= 4:
                    try:
                        # Extract integer from ID field safely
                        pid_str = ''.join(filter(str.isdigit, parts[0]))
                        if not pid_str: continue
                        points_data.append({
                            'id': int(pid_str),
                            'x': float(parts[1]),
                            'y': float(parts[2]),
                            'z': float(parts[3])
                        })
                    except ValueError:
                        continue
    except Exception as e:
        feedback_parts.append(f"Failed to parse exported points: {e}")
    finally:
        if os.path.exists(temp_pts.name):
            os.unlink(temp_pts.name)

    if len(points_data) == 45:
        score += 10
        feedback_parts.append("Correct point count 45 (+10)")
    else:
        feedback_parts.append(f"Point count: {len(points_data)} (expected 45)")

    # 4. EVALUATE SEQUENTIALITY AND COORDINATE PRESERVATION
    sorted_gt = sorted(ground_truth, key=lambda p: p['original_id'])
    sorted_pts = sorted(points_data, key=lambda p: p['id'])

    seq_matches = x_matches = y_matches = z_matches = ordering_matches = 0
    denominator = max(len(sorted_gt), len(sorted_pts))
    if denominator == 0: denominator = 1

    for i, pt in enumerate(sorted_pts):
        expected_id = 1001 + i
        if pt['id'] == expected_id:
            seq_matches += 1
            
        if i < len(sorted_gt):
            gt_pt = sorted_gt[i]
            
            x_match = abs(pt['x'] - gt_pt['x']) <= 0.005
            y_match = abs(pt['y'] - gt_pt['y']) <= 0.005
            z_match = abs(pt['z'] - gt_pt['z']) <= 0.005
            
            if x_match: x_matches += 1
            if y_match: y_matches += 1
            if z_match: z_matches += 1
            if x_match and y_match and z_match: ordering_matches += 1

    seq_score = (seq_matches / denominator) * 20
    x_score = (x_matches / denominator) * 10
    y_score = (y_matches / denominator) * 10
    z_score = (z_matches / denominator) * 10
    order_score = (ordering_matches / denominator) * 15

    score += seq_score + x_score + y_score + z_score + order_score

    feedback_parts.append(f"Sequence Check: {seq_score:.1f}/20")
    feedback_parts.append(f"XYZ Check: {(x_score+y_score+z_score):.1f}/30")
    feedback_parts.append(f"Ordering Match: {order_score:.1f}/15")

    # 5. VLM TRAJECTORY VERIFICATION
    vlm_score = 0
    vlm_feedback = "VLM Check skipped (not available)"
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = (frames or []) + ([final] if final else [])
            
            if images:
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    criteria_met = sum([
                        parsed.get("used_topocal_renumbering", False),
                        parsed.get("sequential_numbers_visible", False),
                        parsed.get("used_export_function", False)
                    ])
                    vlm_score = (criteria_met / 3.0) * 15
                    vlm_feedback = f"VLM Score: {vlm_score:.1f}/15 (Confidence: {parsed.get('confidence', 'unknown')})"
                else:
                    vlm_feedback = f"VLM Query Failed: {vlm_result.get('error')}"
        except ImportError:
            vlm_feedback = "VLM module unavailable, skipping visual check."
        except Exception as e:
            vlm_feedback = f"VLM exception: {e}"

    score += vlm_score
    feedback_parts.append(vlm_feedback)

    # 6. FINAL PASS/FAIL EVALUATION
    # Requirements to pass: mostly sequentially sound and retained coordinates
    passed = score >= 70 and seq_score >= 10 and (x_score+y_score+z_score) >= 15
    
    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": " | ".join(feedback_parts)
    }