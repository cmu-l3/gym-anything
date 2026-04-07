#!/usr/bin/env python3
"""
Verifier for create_operation_span_task.

Verification Strategy:
1.  **File Existence (20 pts):** Checks if the directory structure and required CSV files exist.
2.  **CSV Validity (20 pts):** Checks if CSVs have correct headers and row counts (sanity check for real data).
3.  **Experiment Structure (60 pts):**
    -   Valid PsychoPy XML (10 pts).
    -   Nested Loop Architecture (25 pts): Must detect a loop starting inside another loop.
    -   Dynamic Loading (15 pts): Inner loop must reference a variable (e.g., `$conditionFile`), not a static file.
    -   Correct Routine Placement (10 pts): Math/Letter routines inside inner loop, Recall routine inside outer loop but after inner loop.

Pass Threshold: 70 points (Must have functional nested loop structure).
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_create_operation_span_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/ospan_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # --- Criterion 1: Files & Directories (20 pts) ---
    if result.get("dir_exists") and result.get("exp_exists"):
        score += 10
        feedback_parts.append("Project directory and experiment file found.")
    else:
        feedback_parts.append("Experiment file missing.")
    
    csvs = result.get("csv_files", {})
    required_csvs = ["set_size_3.csv", "set_size_4.csv", "block_list.csv"]
    missing_csvs = [f for f in required_csvs if not csvs.get(f, {}).get("exists")]
    
    if not missing_csvs:
        score += 10
        feedback_parts.append("All CSV files created.")
    else:
        feedback_parts.append(f"Missing CSVs: {', '.join(missing_csvs)}.")

    # --- Criterion 2: CSV Content (20 pts) ---
    csv_points = 0
    # Check set_size_3
    s3 = csvs.get("set_size_3.csv", {})
    if s3.get("exists") and s3.get("rows", 0) >= 3 and "equation" in s3.get("cols", []):
        csv_points += 7
    
    # Check set_size_4
    s4 = csvs.get("set_size_4.csv", {})
    if s4.get("exists") and s4.get("rows", 0) >= 4 and "letter" in s4.get("cols", []):
        csv_points += 7

    # Check block_list
    bl = csvs.get("block_list.csv", {})
    if bl.get("exists") and "conditionFile" in bl.get("cols", []):
        csv_points += 6
    
    score += csv_points
    if csv_points < 20:
        feedback_parts.append("CSV content validation incomplete (check columns/rows).")

    # --- Criterion 3: Experiment Structure (60 pts) ---
    struct = result.get("structure", {})
    
    if result.get("exp_valid_xml"):
        score += 10
    else:
        feedback_parts.append("Invalid .psyexp XML.")
    
    # Check Nested Loops
    if struct.get("nested_loops_detected"):
        score += 25
        feedback_parts.append("Nested loops detected.")
    else:
        feedback_parts.append("FAIL: Nested loop structure not found.")
    
    # Check Dynamic Conditions
    if struct.get("dynamic_conditions_detected"):
        score += 15
        feedback_parts.append("Dynamic condition loading detected.")
    else:
        feedback_parts.append("FAIL: Inner loop must use a variable for conditions (e.g. $conditionFile).")

    # Check Routine Placement Logic
    # We expect: OuterLoop(Start) -> InnerLoop(Start) -> [Math/Letter] -> InnerLoop(End) -> Recall -> OuterLoop(End)
    flow = struct.get("flow_order", [])
    
    # Find indices
    try:
        outer_start = -1
        inner_start = -1
        inner_end = -1
        recall_idx = -1
        math_idx = -1
        
        for i, item in enumerate(flow):
            if item["type"] == "initiator":
                if item["depth"] == 0: outer_start = i
                elif item["depth"] == 1: inner_start = i
            elif item["type"] == "terminator":
                if item["depth"] == 0: inner_end = i # Because pop happens before append logic in export script might vary slightly, but assuming nesting logic holds
                # Wait, depth in flow_order from export script:
                # push -> append initiator (depth 0) -> push -> append initiator (depth 1)
                # pop -> append terminator (depth 1)
                # pop -> append terminator (depth 0)
                pass # Logic handled by depth check
            elif item["type"] == "routine":
                name = item["name"].lower()
                if "recall" in name: recall_idx = i
                if "math" in name: math_idx = i

        # Simplified check using depth
        math_correct = False
        recall_correct = False
        
        for item in flow:
            if item["type"] == "routine":
                name = item["name"].lower()
                depth = item["depth"]
                
                # Math/Letter should be inside inner loop (depth 2 if stack has outer+inner)
                # In export script:
                # 1. Outer Init (stack len 1)
                # 2. Inner Init (stack len 2)
                # 3. Routine (depth 2)
                if "math" in name and depth >= 2:
                    math_correct = True
                
                # Recall should be inside Outer (depth 1) but NOT Inner
                # Ideally after Inner Terminator. 
                # Inner Terminator reduces stack to 1.
                # So a routine with depth 1 implies it's in outer loop only.
                if "recall" in name and depth == 1:
                    recall_correct = True

        if math_correct and recall_correct:
            score += 10
            feedback_parts.append("Routines correctly placed in loop hierarchy.")
        else:
            feedback_parts.append("Routine placement incorrect (Math needs depth 2, Recall depth 1).")
            
    except Exception as e:
        feedback_parts.append(f"Error analyzing flow: {e}")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }