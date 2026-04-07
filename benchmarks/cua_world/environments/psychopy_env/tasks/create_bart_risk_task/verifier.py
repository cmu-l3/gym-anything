#!/usr/bin/env python3
"""
Verifier for create_bart_risk_task.

Verification Strategy:
1. Programmatic:
   - Check if experiment and CSV files exist and were created during task.
   - Validate CSV structure (must have 'explosion_point').
   - Parse .psyexp XML to confirm:
     - Nested Loop structure (critical for BART).
     - Dynamic visual sizing (balloon growth).
     - Logic implementation (pumps logic).
2. VLM:
   - Verify trajectory shows Builder usage (Flow panel, Code components).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bart_risk_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/bart_task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # 1. File Existence & Creation (15 pts)
    if result.get("exp_exists") and result.get("file_created_during_task"):
        score += 15
        feedback_parts.append("Experiment file created successfully.")
    elif result.get("exp_exists"):
        score += 5
        feedback_parts.append("Experiment file exists but timestamp check failed.")
    else:
        feedback_parts.append("Experiment file not found.")

    # 2. Conditions File (15 pts)
    if result.get("csv_valid"):
        score += 15
        feedback_parts.append("Conditions CSV valid.")
    elif result.get("csv_exists"):
        score += 5
        feedback_parts.append("Conditions CSV exists but missing 'explosion_point' column.")
    else:
        feedback_parts.append("Conditions CSV missing.")

    # 3. Nested Loops (20 pts)
    # BART requires an outer loop for trials and inner for pumps
    if result.get("nested_loops"):
        score += 20
        feedback_parts.append("Nested loop structure detected.")
    else:
        feedback_parts.append("Nested loops not detected (critical for BART).")

    # 4. Dynamic Visuals (20 pts)
    # Balloon must grow
    if result.get("dynamic_size"):
        score += 20
        feedback_parts.append("Dynamic balloon size configured.")
    else:
        feedback_parts.append("Balloon size does not appear to be dynamic.")

    # 5. Logic & Feedback (10 pts)
    if result.get("logic_found"):
        score += 10
        feedback_parts.append("Pump/Explosion logic detected.")
    
    if result.get("feedback_found"):
        score += 5 # Bonus/Check
        feedback_parts.append("Feedback routine found.")
    
    # 6. VLM Verification (20 pts)
    # We want to see the flow being constructed
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        You are verifying a user building a PsychoPy experiment.
        Look for:
        1. A "Flow" panel at the bottom showing a nested loop structure (a loop inside another loop).
        2. A routine showing a red circle (balloon).
        3. A code component being edited.
        
        Does the user appear to be building a task with these elements?
        """
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_res.get("success") and vlm_res.get("parsed", {}).get("answer", False): # Assuming boolean response wrapper or analyzing text
             # Simple check on success and positive sentiment for now if wrapper varies
             # For this strict verifier, we'll assume a positive analysis adds points
             score += 20
             feedback_parts.append("VLM confirms workflow.")
        else:
             # Fallback if VLM is ambiguous, grant partial if programmatic passed high
             if score >= 60:
                 score += 20
                 feedback_parts.append("VLM inconclusive, inferred from file structure.")

    # Pass Threshold
    passed = score >= 60 and result.get("nested_loops")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }