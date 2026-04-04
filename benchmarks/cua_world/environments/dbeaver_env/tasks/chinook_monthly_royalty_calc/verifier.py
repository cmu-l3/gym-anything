#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_monthly_royalty_calc(traj, env_info, task_info):
    """
    Verify the Chinook Royalty Calculation task.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- 1. DBeaver Connection (10 pts) ---
    if result.get("connection_found"):
        score += 10
        feedback.append("DBeaver connection 'ChinookRoyalty' created.")
    else:
        feedback.append("Failed: DBeaver connection 'ChinookRoyalty' not found.")

    # --- 2. Royalty Rates Table (20 pts) ---
    db_data = result.get("database", {})
    if db_data.get("rates_table_exists"):
        rates = db_data.get("rates_data", [])
        if len(rates) == 4:
            # Verify tiers
            tiers_correct = True
            expected_tiers = [
                (0, 10, 10.0, "Bronze"),
                (10.01, 50, 15.0, "Silver"),
                (50.01, 200, 20.0, "Gold"),
                (200.01, None, 25.0, "Platinum") # None for NULL
            ]
            
            # Simple check based on RateId order or MinRevenue
            # Assuming the agent inserted them somewhat correctly
            valid_count = 0
            for r in rates:
                # SQLite json export might turn keys lowercase or keep them
                # Adapting to keys
                min_rev = r.get("MinRevenue")
                pct = r.get("RoyaltyPercent")
                tier = r.get("TierName")
                
                # Check if this row matches one of our expected tiers
                match = False
                for exp_min, exp_max, exp_pct, exp_name in expected_tiers:
                    # Tolerance for floats
                    if abs(float(min_rev) - exp_min) < 0.01 and \
                       abs(float(pct) - exp_pct) < 0.01 and \
                       tier.lower() == exp_name.lower():
                        match = True
                        break
                if match:
                    valid_count += 1

            if valid_count == 4:
                score += 20
                feedback.append("Royalty rates table created with correct tiers.")
            else:
                score += 10
                feedback.append(f"Royalty rates table exists but tiers look incorrect ({valid_count}/4 matched).")
                tiers_correct = False
        else:
            score += 5
            feedback.append("Royalty rates table exists but has wrong number of rows.")
    else:
        feedback.append("Failed: Table 'royalty_rates' not found.")

    # --- 3. Royalties Calculation Table (30 pts) ---
    if db_data.get("royalties_table_exists"):
        if db_data.get("royalties_schema_valid"):
            row_count = int(db_data.get("royalties_row_count", 0))
            if row_count > 100: # Expecting several hundred rows
                score += 10
                feedback.append(f"Royalty table populated with {row_count} rows.")
                
                # Math Verification on sample
                sample = db_data.get("sample_royalties", [])
                math_errors = 0
                checked_rows = 0
                
                for row in sample:
                    try:
                        revenue = float(row.get("GrossRevenue", 0))
                        pct = float(row.get("RoyaltyPercent", 0))
                        amt = float(row.get("RoyaltyAmount", 0))
                        
                        expected_amt = revenue * (pct / 100.0)
                        if abs(amt - expected_amt) > 0.02: # 2 cent tolerance
                            math_errors += 1
                        checked_rows += 1
                    except:
                        pass
                
                if checked_rows > 0 and math_errors == 0:
                    score += 20
                    feedback.append("Royalty calculation logic verified (Math is correct).")
                elif checked_rows > 0:
                    score += 5
                    feedback.append(f"Royalty math errors found in {math_errors}/{checked_rows} sampled rows.")
            else:
                score += 5
                feedback.append(f"Royalty table has very few rows ({row_count}). Warning.")
        else:
            feedback.append("Royalty table exists but missing required columns (GrossRevenue/RoyaltyAmount/TierName).")
    else:
        feedback.append("Failed: Table 'artist_monthly_royalties' not found.")

    # --- 4. CSV Export (20 pts) ---
    csv_info = result.get("csv", {})
    if csv_info.get("exists") and csv_info.get("created_during_task"):
        header = csv_info.get("header", "")
        required_cols = ["ArtistName", "TotalGrossRevenue", "TotalRoyalties", "MonthsActive", "AvgMonthlyRevenue", "MostCommonTier"]
        missing = [c for c in required_cols if c.lower() not in header.lower()]
        
        if not missing:
            score += 20
            feedback.append("Summary CSV exported with correct columns.")
        else:
            score += 10
            feedback.append(f"Summary CSV created but missing columns: {missing}")
    else:
        feedback.append("Failed: Summary CSV not found or not created during task.")

    # --- 5. SQL Script (20 pts) ---
    sql_info = result.get("sql_script", {})
    if sql_info.get("exists") and sql_info.get("created_during_task"):
        score += 20
        feedback.append("SQL script file saved.")
    else:
        feedback.append("Failed: SQL script not found.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }