#!/usr/bin/env python3
"""
Verifier for recursive_demand_forecasting task.

Verification Logic:
1. Re-calculate the "Gold Standard" forecast using the exact formula provided in the task.
   Formula: Qty(n) = ROUND( (0.5 * Qty(n-1)) + (0.3 * Qty(n-2)) + (0.2 * Qty(n-3)), 2 )
2. Compare agent's `DEMAND_FORECAST` table against this gold standard.
3. Check for structural correctness (columns, row counts).

Scoring:
- Structure (Table exists, correct cols): 10 pts
- Row count (75 rows): 10 pts
- History accuracy (Weeks 1-10 match source): 20 pts
- Forecast accuracy (Weeks 11-15): 60 pts (12 pts per week avg, checks recursive precision)
"""

import json
import logging
import os
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_recursive_forecast(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/forecast_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Check 1: Infrastructure ---
    if not data.get("table_exists"):
        return {"passed": False, "score": 0, "feedback": "Table DEMAND_FORECAST was not created."}
    
    if data.get("error"):
        return {"passed": False, "score": 5, "feedback": f"Table created but query failed: {data['error']}"}

    score += 10
    feedback.append("Table DEMAND_FORECAST exists.")

    agent_rows = data.get("agent_data", [])
    source_rows = data.get("source_data", [])
    
    # --- Check 2: Row Count ---
    # Expected: 5 products * 15 weeks = 75 rows
    if len(agent_rows) == 75:
        score += 10
        feedback.append("Row count is correct (75).")
    else:
        feedback.append(f"Row count incorrect: found {len(agent_rows)}, expected 75.")

    # --- Prepare Data Structures ---
    # Group source data by product
    history = {} # {product: {week: qty}}
    products = set()
    for row in source_rows:
        p = row['product']
        w = row['week']
        q = row['qty']
        if p not in history: history[p] = {}
        history[p][w] = q
        products.add(p)

    # Group agent data
    agent_map = {} # {product: {week: qty}}
    for row in agent_rows:
        p = row['product']
        w = row['week']
        q = row['qty']
        if p not in agent_map: agent_map[p] = {}
        agent_map[p][w] = q

    # --- Check 3: History Fidelity (Weeks 1-10) ---
    history_correct = True
    for p in products:
        for w in range(1, 11):
            expected = history.get(p, {}).get(w)
            actual = agent_map.get(p, {}).get(w)
            # Use small epsilon for float comparison, though exact match expected for history
            if actual is None or abs(actual - expected) > 0.001:
                history_correct = False
                break
        if not history_correct: break
    
    if history_correct:
        score += 20
        feedback.append("History data (Weeks 1-10) matches source perfectly.")
    else:
        feedback.append("History data mismatch. Agent modified actuals or failed to copy them.")

    # --- Check 4: Forecast Accuracy (Weeks 11-15) ---
    # We must calculate the recursive forecast ourselves to verify.
    
    forecast_points_total = 60
    forecast_points_earned = 0
    total_forecast_weeks = 5 * len(products) # 5 products * 5 weeks = 25 checks
    points_per_week = forecast_points_total / total_forecast_weeks

    # Rounding function that matches Oracle's ROUND(n, 2) behavior
    # Python's round() rounds to nearest even number for .5, Oracle rounds away from zero (usually).
    # However, for simple currency/qty, standard round is usually fine, but to be safe we check strict tolerance.
    def oracle_round(val):
        return round(val, 2)

    correct_forecasts = 0
    
    for p in products:
        # Clone history to extend with forecast
        ts = history[p].copy()
        
        # Calculate Weeks 11-15
        for w in range(11, 16):
            # Qty(n) = ROUND( (0.5 * Qty(n-1)) + (0.3 * Qty(n-2)) + (0.2 * Qty(n-3)), 2 )
            prev1 = ts.get(w-1, 0)
            prev2 = ts.get(w-2, 0)
            prev3 = ts.get(w-3, 0)
            
            val = (0.5 * prev1) + (0.3 * prev2) + (0.2 * prev3)
            val_rounded = oracle_round(val)
            
            # Store for next iteration
            ts[w] = val_rounded
            
            # Compare with Agent
            agent_val = agent_map.get(p, {}).get(w)
            
            if agent_val is not None and abs(agent_val - val_rounded) < 0.011:
                correct_forecasts += 1
            else:
                # Debug info for the first failure
                if correct_forecasts == 0:
                    logger.info(f"Mismatch {p} W{w}: Exp {val_rounded}, Got {agent_val}. Inputs: {prev1}, {prev2}, {prev3}")

    forecast_points_earned = correct_forecasts * points_per_week
    score += forecast_points_earned
    
    feedback.append(f"Forecast Accuracy: {correct_forecasts}/{total_forecast_weeks} correct weeks.")
    
    if correct_forecasts < total_forecast_weeks:
        feedback.append("Hint: Ensure you are using the calculated rounded values for the next step's input (recursion), not the raw values.")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }