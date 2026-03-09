#!/usr/bin/env python3
import json
import os
import tarfile
import csv
import tempfile
import shutil

def verify_migrate_stock_position(traj, env_info, task_info):
    """
    Verify that NVDA was moved from 'My Portfolio' to 'Semiconductor Fund'
    preserving Units (25.0) and Price (615.3).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_symbol = metadata.get('target_symbol', 'NVDA')
    expected_units = float(metadata.get('target_units', 25.0))
    expected_price = float(metadata.get('target_price', 615.3))
    # Date string matching can be tricky due to formatting, but we'll check for partial match
    expected_date_part = "Feb 01" 
    expected_year = "2024"

    score = 0
    feedback = []
    
    # Create temp directory for analysis
    work_dir = tempfile.mkdtemp()
    tar_path = os.path.join(work_dir, "task_result.tar.gz")

    try:
        # Retrieve results
        try:
            copy_from_env("/tmp/task_result.tar.gz", tar_path)
            with tarfile.open(tar_path, "r:gz") as tar:
                tar.extractall(path=work_dir)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task output: {str(e)}"}

        export_dir = os.path.join(work_dir, "jstock_export")
        status_file = os.path.join(export_dir, "file_status.json")
        old_csv_path = os.path.join(export_dir, "old_portfolio.csv")
        new_csv_path = os.path.join(export_dir, "new_portfolio.csv")

        # Load status
        if not os.path.exists(status_file):
            return {"passed": False, "score": 0, "feedback": "Result metadata missing"}
            
        with open(status_file, 'r') as f:
            status = json.load(f)

        # ---------------------------------------------------------
        # Criterion 1: New Portfolio Creation (10 pts)
        # ---------------------------------------------------------
        if status.get("new_portfolio_exists") and status.get("new_dir_created_during_task"):
            score += 10
            feedback.append("New portfolio 'Semiconductor Fund' created successfully.")
        elif status.get("new_portfolio_exists"):
            score += 5
            feedback.append("New portfolio exists but timestamp is old (reused?).")
        else:
            feedback.append("New portfolio 'Semiconductor Fund' NOT found.")

        # ---------------------------------------------------------
        # Criterion 2: NVDA in New Portfolio (50 pts total)
        # ---------------------------------------------------------
        nvda_in_new = False
        nvda_correct_data = False
        
        if os.path.exists(new_csv_path):
            with open(new_csv_path, 'r', encoding='utf-8', errors='ignore') as f:
                reader = csv.reader(f)
                headers = next(reader, None) # Skip header
                
                for row in reader:
                    if not row: continue
                    # JStock CSV structure is robust but let's be defensive
                    # Code is usually col 0
                    if len(row) > 0 and row[0] == expected_symbol:
                        nvda_in_new = True
                        
                        # Parse Data
                        try:
                            # Units is col 3, Price is col 4 (0-indexed based on setup script)
                            # "Code","Symbol","Date","Units","Purchase Price",...
                            units = float(row[3])
                            price = float(row[4])
                            date_str = row[2]
                            
                            units_match = abs(units - expected_units) < 0.01
                            price_match = abs(price - expected_price) < 0.01
                            date_match = (expected_date_part in date_str) and (expected_year in date_str)

                            if units_match and price_match:
                                score += 30 # Base for correct data
                                feedback.append(f"NVDA data transferred correctly (Units: {units}, Price: {price}).")
                                if date_match:
                                    score += 10 # Bonus for date
                                    feedback.append(f"Date preserved correctly ({date_str}).")
                                else:
                                    feedback.append(f"Date mismatch or format changed (Got: {date_str}).")
                                nvda_correct_data = True
                            else:
                                feedback.append(f"NVDA found but data mismatch. Expected Units: {expected_units}, Price: {expected_price}. Got Units: {units}, Price: {price}.")
                                # Partial credit for just finding the stock
                                score += 10
                        except ValueError:
                            feedback.append("Error parsing numeric data in CSV.")
                        
                        break # Found the stock, stop looking
        
        if not nvda_in_new:
            feedback.append("NVDA not found in 'Semiconductor Fund'.")
        else:
             score += 10 # Points for just having the symbol

        # ---------------------------------------------------------
        # Criterion 3: Cleanup Old Portfolio (40 pts total)
        # ---------------------------------------------------------
        nvda_in_old = False
        others_preserved = True
        required_others = ["AAPL", "MSFT"]
        found_others = []

        if os.path.exists(old_csv_path):
            with open(old_csv_path, 'r', encoding='utf-8', errors='ignore') as f:
                reader = csv.reader(f)
                next(reader, None)
                for row in reader:
                    if not row: continue
                    code = row[0]
                    if code == expected_symbol:
                        nvda_in_old = True
                    if code in required_others:
                        found_others.append(code)
        
        # Check NVDA removal
        if not nvda_in_old:
            score += 20
            feedback.append("NVDA successfully removed from 'My Portfolio'.")
        else:
            feedback.append("NVDA still exists in 'My Portfolio' (failed to delete).")

        # Check preservation of others
        if set(found_others) == set(required_others):
            score += 20
            feedback.append("AAPL and MSFT correctly preserved in 'My Portfolio'.")
        else:
            missing = set(required_others) - set(found_others)
            feedback.append(f"Error: Accidental deletion of other stocks ({', '.join(missing)}).")

        # ---------------------------------------------------------
        # Final Verification
        # ---------------------------------------------------------
        passed = (score >= 75) and nvda_correct_data and (not nvda_in_old)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(work_dir)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }