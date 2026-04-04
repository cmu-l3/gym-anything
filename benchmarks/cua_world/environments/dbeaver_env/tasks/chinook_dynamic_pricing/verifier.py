#!/usr/bin/env python3
"""
Verifier for Chinook Dynamic Pricing Task.

Scores based on:
1. DBeaver Connection created (10 pts)
2. Track prices updated correctly according to logic (40 pts)
3. Invoice Items updated to match Tracks (15 pts)
4. CSV Report accuracy (25 pts)
5. SQL Script existence (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_dynamic_pricing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    # ----------------------------------------------------------------
    # 1. Connection Check (10 pts)
    # ----------------------------------------------------------------
    if result.get("connection_exists", False):
        score += 10
        feedback.append("DBeaver connection 'ChinookPricing' found.")
    else:
        feedback.append("DBeaver connection 'ChinookPricing' NOT found.")

    # ----------------------------------------------------------------
    # 2. Database Price Verification (40 pts)
    # ----------------------------------------------------------------
    db_state = result.get("db_state", {})
    ground_truth = result.get("ground_truth", {})
    
    actual_prices = db_state.get("actual_prices", {}) # Dict[str(ID), float]
    gt_tracks = ground_truth.get("tracks", {})        # Dict[str(ID), dict]
    
    # Check modification time
    task_start = result.get("task_start", 0)
    db_mtime = db_state.get("db_mtime", 0)
    
    if db_mtime <= task_start:
         feedback.append("Database file was NOT modified during the task.")
         # Fail pricing checks if DB wasn't touched
         price_score = 0
    else:
        # Sample check: Verify all tracks
        total_tracks = len(gt_tracks)
        correct_count = 0
        surcharge_checked = False
        surcharge_correct = False
        
        # We need to handle string/int key mismatch from JSON
        actual_prices_str = {str(k): v for k, v in actual_prices.items()}
        
        for tid, expected_data in gt_tracks.items():
            tid = str(tid)
            expected_price = expected_data["new_price"]
            
            actual = actual_prices_str.get(tid)
            if actual is not None and abs(actual - expected_price) < 0.01:
                correct_count += 1
                
                # Check specific case: Surcharge
                # 1.79 implies Platinum (1.49) + Surcharge (0.30)
                # 1.59 implies Gold (1.29) + Surcharge (0.30)
                if expected_price in [1.79, 1.59, 1.29, 1.09]: 
                    surcharge_checked = True
                    surcharge_correct = True
        
        if total_tracks > 0:
            accuracy = correct_count / total_tracks
            price_score = int(accuracy * 40)
            feedback.append(f"Track pricing accuracy: {accuracy:.1%} ({correct_count}/{total_tracks} tracks correct).")
        else:
            price_score = 0
            feedback.append("No track data found for verification.")

    score += price_score

    # ----------------------------------------------------------------
    # 3. Invoice Items Synchronization (15 pts)
    # ----------------------------------------------------------------
    is_synced = db_state.get("invoice_items_synced", False)
    if is_synced and price_score > 0: # Only award if they actually changed prices
        score += 15
        feedback.append("Invoice items successfully synchronized with new prices.")
    elif is_synced:
         feedback.append("Invoice items synced, but prices didn't change (no points).")
    else:
        feedback.append("Invoice items NOT synchronized (mismatch with track prices).")

    # ----------------------------------------------------------------
    # 4. CSV Report Verification (25 pts)
    # ----------------------------------------------------------------
    csv_exists = result.get("csv_exists", False)
    csv_rows = result.get("csv_content", []) # List of dicts
    gt_summary = ground_truth.get("summary", [])
    
    if csv_exists:
        csv_score = 5 # Points for existence
        
        # Check columns
        if csv_rows and all(k in csv_rows[0] for k in ["Tier", "RevenueImpact"]):
            csv_score += 5
            
            # Verify data accuracy (sample check logic)
            # We look for the 'Platinum' row
            agent_plat = next((r for r in csv_rows if r.get("Tier") == "Platinum"), None)
            gt_plat = next((r for r in gt_summary if r.get("Tier") == "Platinum"), None)
            
            if agent_plat and gt_plat:
                # Compare RevenueImpact
                try:
                    agent_rev = float(agent_plat.get("RevenueImpact", 0))
                    gt_rev = float(gt_plat.get("RevenueImpact", 0))
                    if abs(agent_rev - gt_rev) < 5.0: # $5 tolerance
                        csv_score += 15
                        feedback.append("CSV RevenueImpact values match ground truth.")
                    else:
                        feedback.append(f"CSV RevenueImpact mismatch (Agent: {agent_rev}, GT: {gt_rev}).")
                except ValueError:
                    feedback.append("CSV RevenueImpact is not a number.")
            else:
                feedback.append("CSV missing Platinum tier row.")
        else:
            feedback.append("CSV missing required columns.")
            
        score += csv_score
    else:
        feedback.append("Pricing summary CSV not found.")

    # ----------------------------------------------------------------
    # 5. SQL Script Check (10 pts)
    # ----------------------------------------------------------------
    if result.get("sql_script_exists", False) and result.get("sql_script_size", 0) > 10:
        score += 10
        feedback.append("SQL script saved.")
    else:
        feedback.append("SQL script not found or empty.")

    # Final Result
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }