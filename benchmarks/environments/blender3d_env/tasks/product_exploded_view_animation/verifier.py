#!/usr/bin/env python3
"""
Verifier for product_exploded_view_animation task.

Criteria:
1. File Saved & Created (15 pts)
2. Render Exists (15 pts)
3. Animation Exists (Keyframes) (20 pts)
4. Expansion Logic (Vertical spread increases) (25 pts)
5. Order Logic (Top > Board > Battery > Bottom) (15 pts)
6. Frame Range Set (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exploded_view(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load Result
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
    
    # 1. Check Files (30 pts total)
    if result.get('blend_exists') and result.get('blend_created_during_task'):
        score += 15
        feedback_parts.append("Blend file saved")
    else:
        feedback_parts.append("Blend file missing or not saved")

    if result.get('render_exists') and result.get('render_size', 0) > 10240: # >10KB
        score += 15
        feedback_parts.append("Render output exists")
    else:
        feedback_parts.append("Render output missing")

    # Analysis Data
    analysis = result.get('scene_analysis', {})
    if not analysis.get('analysis_success'):
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " | Scene analysis failed (invalid file?)"
        }

    # 2. Check Animation Keyframes (20 pts)
    anim_data = analysis.get('has_anim_data', {})
    animated_count = sum(1 for k, v in anim_data.items() if v)
    if animated_count >= 3:
        score += 20
        feedback_parts.append(f"Animation keyframes found on {animated_count} objects")
    elif animated_count > 0:
        score += 10
        feedback_parts.append(f"Partial animation found ({animated_count} objects)")
    else:
        feedback_parts.append("No keyframes found")

    # 3. Check Expansion (25 pts)
    pos1 = analysis.get('pos_frame_1', {})
    pos48 = analysis.get('pos_frame_48', {})
    
    parts = ["Case_Top", "Circuit_Board", "Battery", "Case_Bottom"]
    
    # Calculate Spread
    try:
        vals1 = [pos1[p] for p in parts if p in pos1]
        vals48 = [pos48[p] for p in parts if p in pos48]
        
        spread1 = max(vals1) - min(vals1) if vals1 else 0
        spread48 = max(vals48) - min(vals48) if vals48 else 0
        
        spread_diff = spread48 - spread1
        
        if spread_diff >= 3.0:
            score += 25
            feedback_parts.append(f"Good expansion (spread increase: {spread_diff:.2f})")
        elif spread_diff > 0.5:
            score += 10
            feedback_parts.append(f"Minimal expansion (spread increase: {spread_diff:.2f})")
        else:
            feedback_parts.append("No vertical expansion detected")
    except Exception:
        feedback_parts.append("Could not calculate expansion (missing objects?)")

    # 4. Check Order (15 pts)
    # Expected Z: Top > Board > Battery > Bottom
    try:
        z_top = pos48.get("Case_Top", 0)
        z_board = pos48.get("Circuit_Board", 0)
        z_batt = pos48.get("Battery", 0)
        z_bot = pos48.get("Case_Bottom", 0)
        
        if z_top > z_board > z_batt > z_bot:
            score += 15
            feedback_parts.append("Correct vertical stacking order")
        else:
            feedback_parts.append("Incorrect stacking order")
    except:
        pass

    # 5. Frame Range (10 pts)
    if abs(analysis.get('frame_end', 0) - 60) <= 5:
        score += 10
        feedback_parts.append("Frame range correct")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }