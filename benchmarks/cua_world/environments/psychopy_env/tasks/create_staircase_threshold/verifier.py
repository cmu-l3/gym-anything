#!/usr/bin/env python3
"""
Verifier for create_staircase_threshold task.

Verification Strategy:
1. Programmatic Checks (80 points):
   - File existence and validity
   - Use of Staircase Loop (CRITICAL - standard loops fail)
   - Correct staircase parameters (1-up/3-down, 0.8 start)
   - Grating contrast linked to variable
   - Routine structure (Instructions -> Trial)

2. VLM Checks (20 points):
   - Verify agent interacted with Builder UI
   - Confirm visual structure of flow

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logger = logging.getLogger(__name__)

def verify_create_staircase_threshold(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_params = metadata.get('staircase_params', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load result JSON
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/create_staircase_threshold_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # 2. Check Nonce (Anti-gaming)
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "FAIL: Integrity check failed (nonce mismatch)"}
    except:
        pass # Skip if nonce file missing in env (older env version)

    # 3. File Checks
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "FAIL: Experiment file not found"}
    
    score += 10
    feedback_parts.append("File created")
    
    if result.get('file_modified'):
        score += 5
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("Warning: File not modified during task")

    # 4. Critical Logic: Staircase Loop
    if result.get('has_staircase_loop'):
        score += 25
        feedback_parts.append("Staircase loop detected")
    else:
        feedback_parts.append("FAIL: No Staircase loop found (did you use a standard loop?)")
    
    # 5. Parameter Checks
    loop_params = result.get('loop_params', {})
    param_score = 0
    
    # Helper to clean and check equality roughly
    def check_param(key, expected, tolerance=0.01):
        try:
            val_str = loop_params.get(key, "").replace("[", "").replace("]", "").split(",")[0].strip()
            val = float(val_str)
            return abs(val - expected) < tolerance
        except:
            return str(expected) in str(loop_params.get(key, ""))

    if check_param('startVal', 0.8): param_score += 4
    if check_param('nUp', 1): param_score += 4
    if check_param('nDown', 3): param_score += 4
    if check_param('nReversals', 6): param_score += 4
    if check_param('minVal', 0.01): param_score += 4
    
    score += param_score
    if param_score == 20:
        feedback_parts.append("All staircase parameters correct")
    elif param_score > 0:
        feedback_parts.append(f"Some staircase parameters correct ({param_score}/20 pts)")
    
    # 6. Routine & Component Checks
    if result.get('has_instructions_routine') and result.get('flow_order_correct'):
        score += 10
        feedback_parts.append("Instructions routine correct")
    
    if result.get('has_grating'):
        score += 10
        if result.get('grating_contrast_variable'):
            score += 10
            feedback_parts.append("Grating contrast linked to staircase")
        else:
            feedback_parts.append("Grating found but contrast not linked/updating")
    else:
        feedback_parts.append("No Grating stimulus found")

    # 7. VLM Verification (Trajectory)
    # Ensure they actually used Builder, not just wrote XML
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of a user working in PsychoPy Builder.
        
        Look for:
        1. Interaction with a Loop dialog (Flow panel)
        2. Setting 'Staircase' as the loop type
        3. Editing components (Grating or Text)
        
        Do you see evidence of building an experiment with a loop?
        """
        
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {}).get('analysis', vlm_res.get('raw', '')).lower()
            if "yes" in analysis or "evidence" in analysis:
                score += 10
                feedback_parts.append("VLM confirms Builder usage")
    else:
        # Fallback if no frames (shouldn't happen in production)
        score += 10 

    passed = score >= 60 and result.get('has_staircase_loop')
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }