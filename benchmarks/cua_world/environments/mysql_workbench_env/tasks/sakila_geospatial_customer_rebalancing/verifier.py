#!/usr/bin/env python3
"""Verifier for sakila_geospatial_customer_rebalancing task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_sakila_geospatial_rebalancing(traj, env_info, task_info):
    """
    Verify geospatial rebalancing task.

    Scoring (100 pts):
    - Staging table created and populated: 10 pts
    - Addresses updated with spatial data: 25 pts
    - Store assignment logic (checks 5 specific customers): 30 pts
      - Mary (Japan) -> 2
      - Patricia (USA) -> 1
      - Elizabeth (Taiwan) -> 2
      - Richard (Indonesia) -> 2
      - Linda (Greece) -> 1
    - Store distribution (both stores used significantly): 10 pts
    - CSV export exists with data: 15 pts
    - CSV has correct columns (inferred from rows check): 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/geospatial_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []

    # 1. Staging Table (10 pts)
    staging_rows = result.get('staging_rows', 0)
    if staging_rows > 100:
        score += 10
        feedback_parts.append(f"Staging table populated ({staging_rows} rows)")
    else:
        feedback_parts.append(f"Staging table missing or empty ({staging_rows} rows)")

    # 2. Address Update (25 pts)
    # Sakila has ~600 addresses. We provided ~300 cities. Expect significant updates.
    updated = result.get('address_updated_count', 0)
    if updated > 100:
        score += 25
        feedback_parts.append(f"Address spatial data updated ({updated} addresses)")
    elif updated > 0:
        score += 10
        feedback_parts.append(f"Some addresses updated ({updated}), expected >100")
    else:
        feedback_parts.append("No addresses updated with spatial data")

    # 3. Store Assignment Logic (30 pts - 6 pts each)
    assignments = [
        ('Mary (Japan)', result.get('store_mary_japan'), 2),
        ('Patricia (USA)', result.get('store_patricia_usa'), 1),
        ('Elizabeth (Taiwan)', result.get('store_elizabeth_taiwan'), 2),
        ('Richard (Indonesia)', result.get('store_richard_indonesia'), 2),
        ('Linda (Greece)', result.get('store_linda_greece'), 1)
    ]
    
    correct_assignments = 0
    for name, actual, expected in assignments:
        if actual == expected:
            correct_assignments += 1
    
    logic_score = correct_assignments * 6
    score += logic_score
    feedback_parts.append(f"Store assignment logic: {correct_assignments}/5 correct")

    # 4. Store Distribution (10 pts)
    # Check if both stores have a significant number of customers
    c1 = result.get('count_store_1', 0)
    c2 = result.get('count_store_2', 0)
    if c1 > 50 and c2 > 50:
        score += 10
        feedback_parts.append(f"Balanced distribution (Store 1: {c1}, Store 2: {c2})")
    else:
        feedback_parts.append(f"Unbalanced distribution (Store 1: {c1}, Store 2: {c2})")

    # 5. CSV Export (25 pts total)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)
    
    if csv_exists and csv_rows > 100:
        score += 25
        feedback_parts.append(f"CSV export verified ({csv_rows} rows)")
    elif csv_exists:
        score += 10
        feedback_parts.append(f"CSV exists but has few rows ({csv_rows})")
    else:
        feedback_parts.append("CSV export missing")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }