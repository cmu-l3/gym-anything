#!/usr/bin/env python3
"""
Verifier for economics_supply_demand_graph task.

Scoring (100 points, pass at 70):
1. File Validation (20pts): File exists, valid format, created during task.
2. Structure (20pts): Exactly 2 pages.
3. Graph Labels (30pts): Price, Quantity, Supply, Demand, Equilibrium, Shift.
4. Diagram Elements (30pts): Sufficient lines drawn for axes/curves + arrow for shift.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_supply_demand_graph(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env function"}

    # Read result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # 1. File Validation (20 pts)
    if result.get('file_found') and result.get('file_valid'):
        if result.get('created_during_task'):
            score += 20
            feedback.append("File created successfully (20/20)")
        else:
            score += 10
            feedback.append("File exists but old timestamp (10/20)")
    else:
        return {"passed": False, "score": 0, "feedback": "No valid flipchart file found"}

    # 2. Structure (20 pts)
    pages = result.get('page_count', 0)
    if pages == 2:
        score += 20
        feedback.append("Correct page count: 2 (20/20)")
    elif pages >= 1:
        score += 10
        feedback.append(f"Incorrect page count: {pages} (10/20)")
    else:
        feedback.append("No pages found (0/20)")

    # 3. Text Labels (30 pts - 5 pts each)
    required = {
        'has_price': 'Price/P',
        'has_quantity': 'Quantity/Q',
        'has_supply': 'Supply/S',
        'has_demand': 'Demand/D',
        'has_equilibrium': 'Equilibrium',
        'has_shift': 'Shift/Increase'
    }
    
    text_score = 0
    for key, name in required.items():
        if result.get(key):
            text_score += 5
    score += text_score
    feedback.append(f"Text labels score: {text_score}/30")

    # 4. Diagram Elements (30 pts)
    # Expecting lines for axes (2) + curves (2 on p1, 3 on p2) = ~7 lines total min
    # Expecting arrow for shift
    line_count = result.get('line_count', 0)
    arrow_count = result.get('arrow_count', 0)
    
    diagram_score = 0
    if line_count >= 6: # Loose threshold allowing for single-segment axes
        diagram_score += 20
        feedback.append(f"Graph lines detected ({line_count}) (20/20)")
    elif line_count >= 3:
        diagram_score += 10
        feedback.append(f"Partial graph lines ({line_count}) (10/20)")
    else:
        feedback.append("Insufficient lines for graphs (0/20)")

    if arrow_count >= 1:
        diagram_score += 10
        feedback.append("Shift arrow detected (10/10)")
    else:
        feedback.append("No shift arrow detected (0/10)")
    
    score += diagram_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }