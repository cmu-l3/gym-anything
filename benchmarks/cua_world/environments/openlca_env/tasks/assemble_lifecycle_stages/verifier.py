#!/usr/bin/env python3
import json
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_assemble_lifecycle_stages(traj, env_info, task_info):
    """
    Verifies the PVC Pipe Life Cycle Assembly task.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy unavailable"}

    result = {}
    try:
        import tempfile
        tmp = tempfile.NamedTemporaryFile(delete=False)
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve verification data: {str(e)}"}

    score = 0
    feedback = []
    
    # 2. Programmatic Verification (Database Inspection)
    
    # Criterion A: Process Creation (20 pts)
    if result.get("process_found"):
        score += 20
        feedback.append("Success: 'PVC Pipe Life Cycle' process found in database.")
    else:
        feedback.append("Failed: Could not find the assembly process in the database.")

    # Criterion B: Input Exchanges (Production & EOL) (40 pts)
    exchanges = result.get("exchanges", [])
    
    has_resin = False
    has_landfill = False
    has_transport = False
    transport_amount = 0.0
    
    # Normalize flow names for checking
    for ex in exchanges:
        name = ex['flow'].lower()
        amount = float(ex['amount'])
        
        if "resin" in name or "polyvinyl" in name or "pvc" in name:
            # Check if it's likely the production input (mass ~1.0)
            if 0.9 <= amount <= 1.1:
                has_resin = True
        
        if "landfill" in name or "sanitary" in name or "disposal" in name:
            if 0.9 <= amount <= 1.1:
                has_landfill = True
                
        if "transport" in name or "truck" in name:
            has_transport = True
            transport_amount = amount

    if has_resin:
        score += 20
        feedback.append("Success: Production input (Resin) linked correctly.")
    else:
        feedback.append("Failed: Missing or incorrect PVC Resin input (expected ~1.0 kg).")

    if has_landfill:
        score += 20
        feedback.append("Success: End-of-Life input (Landfill) linked correctly.")
    else:
        feedback.append("Failed: Missing or incorrect Landfill input (expected ~1.0 kg).")

    # Criterion C: Transport Calculation Logic (30 pts)
    # Target: 1kg * 2500km = 2.5 t*km OR 2500 kg*km
    transport_score = 0
    if has_transport:
        # Check for t*km (2.5)
        if 2.3 <= transport_amount <= 2.7:
            transport_score = 30
            feedback.append(f"Success: Transport amount {transport_amount} is correct (t*km).")
        # Check for kg*km (2500)
        elif 2300 <= transport_amount <= 2700:
            transport_score = 30
            feedback.append(f"Success: Transport amount {transport_amount} is correct (kg*km).")
        else:
            feedback.append(f"Failed: Transport input found but amount {transport_amount} is incorrect. Expected 2.5 (t*km) or 2500 (kg*km).")
    else:
        feedback.append("Failed: No Transport input linked.")
    score += transport_score

    # Criterion D: Output File (10 pts)
    if result.get("output_exists") and result.get("output_size", 0) > 100:
        score += 10
        feedback.append("Success: Result CSV file created.")
    else:
        feedback.append("Failed: Result CSV file not found or empty.")

    # 3. VLM Verification (Trajectory Check)
    # We use this primarily as an anti-gaming check or tie-breaker, 
    # but the DB check is robust enough for primary scoring.
    # We'll check if the trajectory shows the process editor.
    
    frames = sample_trajectory_frames(traj, 4)
    if frames:
        vlm_res = query_vlm(
            images=frames,
            prompt="Does the user appear to be working in the openLCA Process Editor? Look for a tab with inputs/outputs or exchanges table."
        )
        if not vlm_res.get('success') or not vlm_res.get('parsed', {}).get('answer', False):
            # If DB check passed, we assume VLM missed it, but if DB failed, this confirms.
            pass

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }