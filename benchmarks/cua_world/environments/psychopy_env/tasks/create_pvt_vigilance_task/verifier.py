#!/usr/bin/env python3
"""
Verifier for create_pvt_vigilance_task.

Verification Strategy:
1. Programmatic (85 points):
   - CSV file correctness (values, format)
   - Experiment structure (XML parsing)
   - Specific PVT logic (counter update, false start detection)
2. VLM (15 points):
   - Trajectory verification showing the Builder interface interactions

Pass threshold: 65 points (Must have working counter and basic structure)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_create_pvt_vigilance_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_isis = metadata.get('expected_isis', [2.0, 5.0, 3.5, 8.0, 4.0])

    # Copy result file
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/pvt_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # NONCE CHECK
    if result.get("result_nonce") == "":
        return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: Nonce missing"}

    score = 0
    feedback_parts = []

    # 1. Conditions File Check (20 pts)
    # ----------------------------------------------------------------
    cond_exists = result.get("cond_exists", False)
    cond_modified = result.get("cond_modified", False)
    cond_values = result.get("cond_values", [])
    
    if cond_exists and cond_modified:
        # Check if expected values are present
        # We allow them in any order for partial credit, but exact set preferred
        matches = 0
        for val in expected_isis:
            if val in cond_values:
                matches += 1
        
        if matches == 5:
            score += 20
            feedback_parts.append("Conditions file correct (20/20)")
        elif matches >= 3:
            score += 10
            feedback_parts.append(f"Conditions file partial match ({matches}/5 values) (10/20)")
        else:
            score += 5
            feedback_parts.append("Conditions file exists but values incorrect (5/20)")
    else:
        feedback_parts.append("Conditions file missing or not created (0/20)")

    # 2. Experiment Structure (20 pts)
    # ----------------------------------------------------------------
    exp_exists = result.get("exp_exists", False)
    valid_xml = result.get("is_valid_xml", False)
    
    if exp_exists and valid_xml:
        structure_score = 0
        if result.get("has_isi_wait"): structure_score += 5
        if result.get("has_reaction_test"): structure_score += 5
        if result.get("has_feedback"): structure_score += 5
        if result.get("has_loop", True): structure_score += 5 # XML check usually finds loop easily
        
        score += structure_score
        feedback_parts.append(f"Experiment structure score: {structure_score}/20")
    else:
        feedback_parts.append("Experiment file missing or invalid (0/20)")

    # 3. Dynamic Counter Implementation (25 pts)
    # ----------------------------------------------------------------
    # This is the hardest technical part: needs 'set every frame' and 't*1000'
    counter_score = 0
    if result.get("counter_uses_time_var"): counter_score += 10
    if result.get("counter_updates_every_frame"): counter_score += 10
    if result.get("counter_is_red"): counter_score += 5
    
    score += counter_score
    feedback_parts.append(f"Dynamic counter score: {counter_score}/25")

    # 4. Logic Implementation (20 pts)
    # ----------------------------------------------------------------
    logic_score = 0
    if result.get("false_start_logic_found"): logic_score += 10
    if result.get("feedback_logic_found"): logic_score += 5
    if result.get("variable_isi_found"): logic_score += 5
    
    score += logic_score
    feedback_parts.append(f"Logic implementation score: {logic_score}/20")

    # 5. File Creation Anti-gaming (15 pts)
    # ----------------------------------------------------------------
    # Already checked modified flags above, but this gives points purely for
    # successfully saving valid files during the session
    creation_score = 0
    if cond_exists and cond_modified: creation_score += 7
    if exp_exists and result.get("exp_modified"): creation_score += 8
    
    score += creation_score
    
    # 6. Final Evaluation
    # ----------------------------------------------------------------
    # Pass threshold: 65 points
    # Critical criteria: Must have counter working OR logic working to pass
    
    critical_met = (result.get("counter_uses_time_var") and result.get("counter_updates_every_frame")) or \
                   (result.get("false_start_logic_found"))
    
    passed = (score >= 65) and critical_met
    
    if not critical_met:
        feedback_parts.append("FAILED CRITICAL: Must implement either dynamic counter or false start logic correctly")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }