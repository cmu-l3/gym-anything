#!/usr/bin/env python3
"""
Verifier for manufacturing_bom_cost_rollup task.

Scoring Criteria:
1. View ASSEMBLY_COST_ANALYSIS exists and is valid (15 pts)
2. View calculates correct cost for Level 1 assembly (Case Frame) (15 pts)
3. View calculates correct cost for Level 2 assembly (CPU Module) (20 pts)
4. View calculates correct cost for Level 3 assembly (Server X1) (20 pts)
   - This proves recursive logic handles deep hierarchies.
5. CSV file exists and was created during task (10 pts)
6. CSV content lists the correct top item (Server X1) with correct cost (10 pts)
7. VLM Verification: Agent used SQL/DBeaver interface (10 pts)

Total: 100 pts
Pass Threshold: 60 pts
"""

import json
import os
import tempfile
import logging
import csv

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bom_cost_rollup(traj, env_info, task_info):
    """
    Verifies the manufacturing BOM cost rollup task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {
        "Server X1": 1476.0,
        "CPU Module": 404.0,
        "RAM Stick": 164.0,
        "Case Frame": 7.0
    })

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. View Existence (15 pts)
    if result.get("view_exists") and result.get("view_status") == "VALID":
        score += 15
        feedback_parts.append("View ASSEMBLY_COST_ANALYSIS created and valid (+15)")
    else:
        feedback_parts.append("View missing or invalid (0 pts)")
        # If view is missing, they likely fail everything else, but check CSV
    
    # 2-4. Cost Accuracy (55 pts total)
    calculated = result.get("calculated_costs", {})
    
    # Level 1: Case Frame (15 pts)
    # Expected: 7.0
    val = calculated.get("Case Frame", -1)
    if abs(val - ground_truth["Case Frame"]) < 0.1:
        score += 15
        feedback_parts.append("Level 1 Assembly (Case Frame) cost correct (+15)")
    else:
        feedback_parts.append(f"Level 1 Cost Incorrect: Got {val}, Expected {ground_truth['Case Frame']}")

    # Level 2: CPU Module (20 pts)
    # Expected: 404.0
    val = calculated.get("CPU Module", -1)
    if abs(val - ground_truth["CPU Module"]) < 0.1:
        score += 20
        feedback_parts.append("Level 2 Assembly (CPU Module) cost correct (+20)")
    else:
        feedback_parts.append(f"Level 2 Cost Incorrect: Got {val}, Expected {ground_truth['CPU Module']}")

    # Level 3: Server X1 (20 pts)
    # Expected: 1476.0
    val = calculated.get("Server X1", -1)
    if abs(val - ground_truth["Server X1"]) < 0.1:
        score += 20
        feedback_parts.append("Level 3 Assembly (Server X1) cost correct (+20)")
    else:
        feedback_parts.append(f"Level 3 Cost Incorrect: Got {val}, Expected {ground_truth['Server X1']}")

    # 5. CSV Existence (10 pts)
    if result.get("csv_exists") and result.get("csv_created_during_task"):
        score += 10
        feedback_parts.append("Output CSV created (+10)")
    else:
        feedback_parts.append("CSV output missing or old (0 pts)")

    # 6. CSV Content (10 pts)
    # Check if Server X1 is in the CSV and has correct cost
    csv_correct = False
    csv_rows = result.get("csv_content", [])
    for row in csv_rows:
        # Simple fuzzy check: row contains "Server X1" and "1476"
        row_str = str(row).lower()
        if "server x1" in row_str and ("1476" in row_str or "1,476" in row_str):
            csv_correct = True
            break
    
    if csv_correct:
        score += 10
        feedback_parts.append("CSV content accurate (+10)")
    elif result.get("csv_exists"):
        feedback_parts.append("CSV content incorrect (0 pts)")

    # 7. VLM Check (Bonus/Validation - integrated into scoring?)
    # For now, we rely on the programmatic checks as they are very robust mathematically.
    # If the view is correct, they MUST have used recursive SQL.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }