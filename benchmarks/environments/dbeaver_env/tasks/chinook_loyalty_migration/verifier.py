#!/usr/bin/env python3
"""
Verifier for Chinook Loyalty Migration Task
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_loyalty_migration(traj, env_info, task_info):
    """
    Verify schema migration and data backfill correctness.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. DBeaver Connection (10 pts)
    if result.get('dbeaver_connection_found'):
        score += 10
        feedback.append("DBeaver connection 'ChinookLoyalty' found.")
    else:
        feedback.append("Missing DBeaver connection.")

    # 2. Schema Changes (30 pts)
    schema = result.get('schema', {})
    if schema.get('has_tier_col'): score += 10
    else: feedback.append("Missing 'LoyaltyTier' column.")
    
    if schema.get('has_spend_col'): score += 5
    else: feedback.append("Missing 'TotalSpend' column.")
    
    if schema.get('has_join_col'): score += 5
    else: feedback.append("Missing 'JoinDate' column.")
    
    if schema.get('has_rewards_table') and schema.get('rewards_schema_valid'):
        score += 10
        feedback.append("Loyalty Rewards table created correctly.")
    else:
        feedback.append("Loyalty Rewards table missing or invalid schema.")

    # 3. Data Backfill Accuracy (30 pts)
    data = result.get('data', {})
    total = data.get('total_customers', 59)
    if total == 0: total = 1 # avoid div zero
    
    spend_acc = data.get('spend_match_count', 0) / total
    tier_acc = data.get('tier_match_count', 0) / total

    if spend_acc >= 0.9: 
        score += 15
        feedback.append(f"TotalSpend backfill accurate ({int(spend_acc*100)}%).")
    elif spend_acc > 0:
        score += 5
        feedback.append(f"TotalSpend backfill partially correct ({int(spend_acc*100)}%).")
    else:
        feedback.append("TotalSpend values incorrect.")

    if tier_acc >= 0.9:
        score += 15
        feedback.append(f"LoyaltyTier assignments accurate ({int(tier_acc*100)}%).")
    else:
        feedback.append(f"LoyaltyTier assignments incorrect ({int(tier_acc*100)}% match).")

    # 4. Rewards Table Content (10 pts)
    actual_rewards = data.get('rewards_row_count', 0)
    expected_rewards = data.get('rewards_row_expected', 0)
    
    if actual_rewards == expected_rewards and expected_rewards > 0:
        score += 5
    else:
        feedback.append(f"Rewards table row count mismatch (Found {actual_rewards}, Expected {expected_rewards}).")
        
    if data.get('rewards_data_valid'):
        score += 5
    else:
        feedback.append("Rewards discount percentages incorrect.")

    # 5. File Deliverables (20 pts)
    if result.get('csv_exists'): 
        score += 10
        feedback.append("CSV report exported.")
    else:
        feedback.append("Missing CSV report.")

    if result.get('sql_exists'):
        score += 10
        feedback.append("SQL script saved.")
    else:
        feedback.append("Missing SQL script.")

    # Anti-gaming check
    if not result.get('db_modified') and result.get('db_exists'):
        score = 0
        feedback = ["Anti-gaming: Database file was not modified after task start."]

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }