#!/usr/bin/env python3
"""
Verifier for create_delay_discounting_task.

Verification Strategy:
1. CSV Integrity (55 points):
   - File exists and valid CSV (10)
   - Exactly 27 rows (15)
   - Correct columns (sir, ldr, days) (10)
   - Data matches the official Kirby 27-item dataset (20)
     (Allows for order independence)

2. Experiment Structure (45 points):
   - File exists and valid XML (10)
   - Loop configured pointing to CSV (10)
   - Visuals: Uses variables $sir, $ldr in text components (15)
   - Keyboard: Valid response keys (10)

Ground Truth Data (Kirby 1999):
Stored in the verifier to check against agent's CSV.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

# The 27 Kirby items: (SIR, LDR, Days)
KIRBY_GROUND_TRUTH = {
    # Small
    (19, 25, 53), (14, 25, 19), (10, 25, 12),
    (11, 30, 7),  (20, 55, 7),  (15, 35, 13),
    (25, 60, 14), (24, 35, 29), (34, 50, 155),
    # Medium
    (54, 55, 117), (54, 60, 111), (54, 80, 20),
    (27, 50, 21),  (49, 60, 89),  (40, 55, 62),
    (47, 50, 160), (41, 75, 20),  (33, 80, 14),
    # Large
    (31, 85, 7),   (22, 85, 20),  (67, 75, 119),
    (34, 35, 186), (25, 30, 80),  (69, 85, 91),
    (78, 80, 162), (54, 75, 117), (80, 85, 157)
}

def verify_create_delay_discounting_task(traj, env_info, task_info):
    """Verify the Kirby Delay Discounting task creation."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Load results
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/create_delay_discounting_task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export failed: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # --- PART 1: CSV Verification (55 pts) ---
    csv_exists = result.get("csv_exists", False)
    csv_rows = result.get("csv_rows", 0)
    csv_headers = result.get("csv_headers_valid", False)
    csv_data = result.get("csv_data", [])
    
    if csv_exists:
        score += 10
        feedback_parts.append("CSV exists")
        
        if csv_headers:
            score += 10
            feedback_parts.append("Columns correct")
        else:
            feedback_parts.append("Columns missing or renamed")
            
        if csv_rows == 27:
            score += 15
            feedback_parts.append("Row count correct (27)")
        else:
            feedback_parts.append(f"Row count incorrect ({csv_rows})")
            
        # Data Validity Check
        matches = 0
        try:
            # Normalize agent data to integer tuples
            agent_set = set()
            for row in csv_data:
                try:
                    s = int(float(row.get('sir', 0)))
                    l = int(float(row.get('ldr', 0)))
                    d = int(float(row.get('days', 0)))
                    agent_set.add((s, l, d))
                except ValueError:
                    pass
            
            # Intersection with ground truth
            matches = len(agent_set.intersection(KIRBY_GROUND_TRUTH))
            
            if matches == 27:
                score += 20
                feedback_parts.append("Data matches Kirby dataset perfectly")
            elif matches > 20:
                score += 10
                feedback_parts.append(f"Data mostly correct ({matches}/27)")
            else:
                feedback_parts.append(f"Data invalid ({matches}/27 matches)")
        except Exception as e:
            feedback_parts.append(f"Data validation error: {e}")
            
    else:
        feedback_parts.append("CSV file not found")

    # --- PART 2: Experiment Verification (45 pts) ---
    exp_exists = result.get("exp_exists", False)
    has_loop = result.get("has_loop", False)
    loop_ref = result.get("loop_file_ref", "")
    has_sir = result.get("has_sir_var", False)
    has_ldr = result.get("has_ldr_var", False)
    
    if exp_exists:
        score += 10
        feedback_parts.append("Experiment file exists")
        
        if has_loop:
            score += 10
            # Check if loop points to csv
            if "kirby_mcq.csv" in loop_ref:
                feedback_parts.append("Loop linked to CSV")
            else:
                feedback_parts.append("Loop exists but wrong file link")
        else:
            feedback_parts.append("No loop found")
            
        if has_sir and has_ldr:
            score += 15
            feedback_parts.append("Text variables configured ($sir/$ldr)")
        elif has_sir or has_ldr:
            score += 7
            feedback_parts.append("Partial text variable configuration")
        else:
            feedback_parts.append("Text variables missing")
            
        # Check keyboard
        keys = result.get("keyboard_keys", "")
        if "q" in keys and "p" in keys:
             score += 10
             feedback_parts.append("Keyboard keys correct")
    else:
        feedback_parts.append("Experiment file not found")

    # Final logic
    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }