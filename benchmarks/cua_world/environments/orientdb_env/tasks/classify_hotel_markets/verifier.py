#!/usr/bin/env python3
"""
Verifier for classify_hotel_markets task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_classify_hotel_markets(traj, env_info, task_info):
    """
    Verifies the hotel market classification task.
    
    Criteria:
    1. 'Market' property exists on 'Hotels' class (20 pts)
    2. Classification logic is applied correctly (80 pts)
       - International: >= 50% visitors are different nationality
       - Domestic: > 50% visitors are same nationality
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Schema (Market property exists)
    schema_entries = result.get("schema", {}).get("result", [])
    market_prop_exists = any(p.get("name") == "Market" for p in schema_entries)
    
    if market_prop_exists:
        score += 20
        feedback.append("Schema check passed: 'Market' property found on Hotels class.")
    else:
        feedback.append("Schema check failed: 'Market' property NOT found on Hotels class.")
        # If schema is missing, they likely didn't do the rest either, but we check data anyway.

    # 2. Verify Data Classification
    hotels_data = result.get("data", {}).get("result", [])
    
    total_hotels_checked = 0
    correct_classifications = 0
    
    # Logic verification
    for hotel in hotels_data:
        name = hotel.get("Name")
        country = hotel.get("Country")
        agent_market = hotel.get("Market")
        visitor_nationalities = hotel.get("VisitorNationalities", [])
        
        # Skip hotels with no visitors (logic is undefined/optional for them in prompt)
        if not visitor_nationalities:
            continue
            
        total_hotels_checked += 1
        
        # Calculate Ground Truth
        total_visits = len(visitor_nationalities)
        diff_nat_count = sum(1 for nat in visitor_nationalities if nat != country)
        
        # Logic: >= 50% different -> International
        ratio_diff = diff_nat_count / total_visits
        
        if ratio_diff >= 0.5:
            expected_market = "International"
        else:
            expected_market = "Domestic"
            
        # Compare
        if agent_market == expected_market:
            correct_classifications += 1
        else:
            feedback.append(f"Hotel '{name}': Expected {expected_market} (Ratio Diff={ratio_diff:.2f}), Got '{agent_market}'")

    if total_hotels_checked == 0:
        feedback.append("No hotels with visitors found to verify.")
        logic_score = 0
    else:
        # Scale remaining 80 points by accuracy
        accuracy = correct_classifications / total_hotels_checked
        logic_score = int(accuracy * 80)
        feedback.append(f"Classification Accuracy: {correct_classifications}/{total_hotels_checked} ({int(accuracy*100)}%)")

    score += logic_score
    
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }