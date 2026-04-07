#!/usr/bin/env python3
"""
Verifier for Supply Chain Inventory Simulation task.

Verification Logic:
1. View 'INVENTORY_FORECAST' must exist.
2. View definition must contain the 'MODEL' clause (Critical Skill).
3. Logic Verification (Product 101):
   - Week 1: Start 100, Demand 80 -> Close 20. 20 < Safety(50) -> Order 200.
   - Week 2: Open 20, Arrivals 200 (from W1 order), Demand 50 -> Close 170. Order 0.
   - Week 3: Open 170, Arrivals 0, Demand 60 -> Close 110.
4. CSV Output file must exist and contain data.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_supply_chain_simulation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/supply_chain_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    db_res = result.get("db_verification", {})
    
    # 1. View Exists (10 pts)
    if db_res.get("view_exists"):
        score += 10
        feedback_parts.append("View INVENTORY_FORECAST created (+10)")
    else:
        return {"passed": False, "score": 0, "feedback": "View INVENTORY_FORECAST not found."}

    # 2. Uses MODEL Clause (20 pts)
    # This is the core skill being tested.
    if db_res.get("uses_model_clause"):
        score += 20
        feedback_parts.append("MODEL clause used correctly (+20)")
    else:
        feedback_parts.append("MODEL clause NOT detected in view definition (0 pts). Task requires SQL MODEL.")

    # 3. Column Structure (10 pts)
    required_cols = task_info["metadata"]["required_columns"]
    actual_cols = db_res.get("columns", [])
    if set(required_cols).issubset(set(actual_cols)):
        score += 10
        feedback_parts.append("Required columns present (+10)")
    else:
        feedback_parts.append(f"Missing columns. Found: {actual_cols}")

    # 4. Logic Verification (45 pts total)
    # Check Product 101 data traces
    logic_data = db_res.get("logic_check_p101", [])
    if len(logic_data) >= 3:
        w1 = logic_data[0]
        w2 = logic_data[1]
        
        # Check Week 1 Logic (15 pts)
        # Open=100, Arr=0, Dem=80, Close=20, Order=200 (Safety=50)
        w1_pass = (w1["open"] == 100 and w1["arr"] == 0 and 
                   w1["close"] == 20 and w1["order"] == 200)
        
        if w1_pass:
            score += 15
            feedback_parts.append("Week 1 calculations correct (+15)")
        else:
            feedback_parts.append(f"Week 1 logic failed. Got: {w1}")

        # Check Week 2 Logic (15 pts) - Crucial for Inter-row dependency (Arrivals)
        # Open=20 (prev close), Arr=200 (prev order), Dem=50, Close=170
        w2_pass = (w2["open"] == 20 and w2["arr"] == 200 and 
                   w2["close"] == 170)
        
        if w2_pass:
            score += 15
            feedback_parts.append("Week 2 inter-row dependency correct (+15)")
        else:
            feedback_parts.append(f"Week 2 logic failed (Check lag/arrivals). Got: {w2}")
            
        # Check Ordering Logic (15 pts)
        # Week 1 order triggered correctly (checked above).
        # Week 2 Close=170 > 50, so Order should be 0.
        if w1["order"] == 200 and w2["order"] == 0:
            score += 15
            feedback_parts.append("Reorder threshold logic correct (+15)")
        else:
            feedback_parts.append("Reorder logic failed")
    else:
        feedback_parts.append("Insufficient data rows for logic check")

    # 5. CSV Export (15 pts)
    if result.get("csv_exists"):
        if result.get("csv_size", 0) > 100: # Arbitrary small size check
            score += 15
            feedback_parts.append("CSV exported successfully (+15)")
        else:
            score += 5
            feedback_parts.append("CSV exists but looks empty (+5)")
    else:
        feedback_parts.append("CSV file not found")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }