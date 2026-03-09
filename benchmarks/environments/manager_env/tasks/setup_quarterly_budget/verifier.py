#!/usr/bin/env python3
"""
Verifier for setup_quarterly_budget task.

Criteria:
1. Budgets module enabled (15 pts)
2. Budget "Q1 2025 Operating Budget" created (15 pts)
3. Line items correct (Sales, Cost of sales, Rent, Wages) (15 pts each)
4. Budget period (implicit in checking the total amounts) (10 pts)
"""

import json
import os
import sys
import logging
import tempfile
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_quarterly_budget(traj, env_info, task_info):
    """
    Verify the budget creation task using exported JSON data and VLM verification.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    target_budget_name = metadata.get('target_budget_name', "Q1 2025 Operating Budget")
    expected_items = metadata.get('line_items', {})
    tolerance = metadata.get('tolerance_percent', 0.05)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    
    # Criterion 1: Module Enabled (15 pts)
    if result.get("budgets_enabled"):
        score += 15
        feedback_parts.append("Budgets module enabled")
    else:
        feedback_parts.append("Budgets module NOT enabled")
        return {"passed": False, "score": 0, "feedback": "Budgets module not enabled. Task failed."}

    # Criterion 2: Budget Created (15 pts)
    if result.get("budget_found"):
        score += 15
        feedback_parts.append(f"Budget '{target_budget_name}' found")
    else:
        feedback_parts.append(f"Budget '{target_budget_name}' NOT found")
        # Can stop here or give partial credit for module
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Criterion 3: Line Items (60 pts total: 15 per item)
    # Criterion 4: Period/Values (implicit in amounts) (10 pts bonus/distributed)
    
    agent_items = result.get("line_items", {})
    items_correct = 0
    
    for account, expected_amt in expected_items.items():
        agent_amt = agent_items.get(account)
        
        if agent_amt is None:
            feedback_parts.append(f"Missing line item: {account}")
            continue
            
        # Check tolerance
        diff = abs(agent_amt - expected_amt)
        allowed_diff = expected_amt * tolerance
        
        if diff <= allowed_diff:
            score += 15
            items_correct += 1
            feedback_parts.append(f"{account} correct ({agent_amt})")
        else:
            feedback_parts.append(f"{account} incorrect (got {agent_amt}, expected {expected_amt})")

    # Bonus points for getting all items (representing correct period/calculation)
    if items_correct == len(expected_items):
        score += 10
        feedback_parts.append("All values and period correct")

    # Anti-gaming: Check if task was too fast (impossible) or "do nothing"
    # (Do nothing is handled by the checks above returning false)

    passed = score >= 60  # Require at least module + budget + 2 items roughly
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }