#!/usr/bin/env python3
"""
Verifier for Suspension Damping Simulator task.

Scoring (100 points):
- File Created (10 pts): File exists and created during task.
- Sliders Present (20 pts): m, k, c sliders exist.
- Correct Simulation State (20 pts): Sliders set to m=40, k=25000, c=500.
- Oscillator Function (25 pts): Function with exp and cos defined.
- Envelope Functions (15 pts): Function(s) with exp but no cos.
- Dynamic Text (10 pts): Text element present related to damping ratio.

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_suspension_damping_simulator(traj, env_info, task_info):
    """Verify the suspension damping simulator task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    target_m = metadata.get('target_m', 40.0)
    target_k = metadata.get('target_k', 25000.0)
    target_c = metadata.get('target_c', 500.0)
    tolerance = metadata.get('tolerance', 0.05)

    try:
        # Copy result from container
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. File Check (10 pts)
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created successfully (+10)")
    elif result.get('file_found'):
        score += 5
        feedback_parts.append("File found but timestamp predates task (+5)")
    else:
        feedback_parts.append("File 'suspension.ggb' not found (0)")

    # 2. Sliders Check (20 pts)
    sliders_found = result.get('sliders_found', [])
    required_sliders = {'m', 'k', 'c'}
    found_set = set(sliders_found)
    
    if required_sliders.issubset(found_set):
        score += 20
        feedback_parts.append("All sliders (m, k, c) found (+20)")
    elif found_set:
        partial = int(20 * len(found_set) / 3)
        score += partial
        feedback_parts.append(f"Some sliders found: {found_set} (+{partial})")
    else:
        feedback_parts.append("No sliders found (0)")

    # 3. Simulation State Values (20 pts)
    vals = result.get('slider_values', {})
    val_score = 0
    val_feedback = []
    
    # Check m
    m_val = vals.get('m')
    if m_val is not None and abs(m_val - target_m) <= target_m * tolerance:
        val_score += 6
        val_feedback.append("m correct")
    
    # Check k
    k_val = vals.get('k')
    if k_val is not None and abs(k_val - target_k) <= target_k * tolerance:
        val_score += 7
        val_feedback.append("k correct")
        
    # Check c
    c_val = vals.get('c')
    if c_val is not None and abs(c_val - target_c) <= target_c * tolerance:
        val_score += 7
        val_feedback.append("c correct")
        
    if val_score > 0:
        score += val_score
        feedback_parts.append(f"Values checked: {', '.join(val_feedback)} (+{val_score})")
    else:
        feedback_parts.append("Slider values incorrect or not set to scenario defaults (0)")

    # 4. Oscillator Function (25 pts)
    if result.get('has_oscillator'):
        score += 25
        feedback_parts.append("Oscillator function (exp*cos) found (+25)")
    else:
        feedback_parts.append("Oscillator function missing or incorrect formula (0)")

    # 5. Envelope Functions (15 pts)
    if result.get('has_envelopes'):
        score += 15
        feedback_parts.append("Envelope functions found (+15)")
    else:
        feedback_parts.append("Envelope functions missing (0)")

    # 6. Dynamic Text (10 pts)
    if result.get('has_dynamic_text'):
        score += 10
        feedback_parts.append("Dynamic text found (+10)")
    else:
        feedback_parts.append("Dynamic text missing (0)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }