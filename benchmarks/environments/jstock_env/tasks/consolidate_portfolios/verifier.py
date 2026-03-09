#!/usr/bin/env python3
import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_portfolios(traj, env_info, task_info):
    """
    Verify that the 'Master' portfolio contains VTI, BND, and COIN with correct details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    expected_txs = task_info.get('metadata', {}).get('expected_transactions', [])
    
    # Files to copy
    result_json_path = "/tmp/task_result.json"
    csv_path = "/tmp/master_buyportfolio.csv"
    
    # Temporary local files
    local_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    local_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name
    
    try:
        # 1. Get Result JSON
        try:
            copy_from_env(result_json_path, local_result)
            with open(local_result, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        if not result_data.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Master portfolio CSV file not found."}
            
        if not result_data.get('file_modified_during_task'):
            return {"passed": False, "score": 0, "feedback": "Master portfolio was not modified during the task."}

        # 2. Get CSV Content
        try:
            copy_from_env(csv_path, local_csv)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve portfolio CSV: {str(e)}"}

        # 3. Analyze CSV
        found_txs = []
        with open(local_csv, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            # Normalize headers (strip quotes just in case, though DictReader handles standard CSV)
            # JStock CSVs are standard quoted CSVs.
            for row in reader:
                # Extract relevant fields
                symbol = row.get('Code', '').strip()
                date = row.get('Date', '').strip()
                try:
                    units = float(row.get('Units', '0').replace(',', ''))
                    price = float(row.get('Purchase Price', '0').replace(',', ''))
                except ValueError:
                    units = 0.0
                    price = 0.0
                
                found_txs.append({
                    "symbol": symbol,
                    "date": date,
                    "units": units,
                    "price": price
                })

        # 4. Score
        score = 0
        feedback = []
        
        # Base points for file existence/mod (already passed checks above)
        score += 10 
        
        # Check each expected transaction
        matches = 0
        for exp in expected_txs:
            exp_sym = exp['symbol']
            exp_date = exp['date']
            exp_units = exp['units']
            exp_price = exp['price']
            
            # Find match
            match = None
            for found in found_txs:
                if found['symbol'] == exp_sym:
                    match = found
                    break
            
            if match:
                item_score = 0
                item_feedback = []
                
                # Check Details
                # Units (allow small float tolerance)
                if abs(match['units'] - exp_units) < 0.01:
                    item_score += 10
                else:
                    item_feedback.append(f"Units mismatch ({match['units']} vs {exp_units})")

                # Price
                if abs(match['price'] - exp_price) < 0.01:
                    item_score += 10
                else:
                    item_feedback.append(f"Price mismatch ({match['price']} vs {exp_price})")
                    
                # Date (Exact string match usually required for JStock format)
                if match['date'] == exp_date:
                    item_score += 10
                else:
                    item_feedback.append(f"Date mismatch ({match['date']} vs {exp_date})")
                
                if item_score == 30:
                    feedback.append(f"✅ {exp_sym}: Perfect match")
                else:
                    feedback.append(f"⚠️ {exp_sym}: " + ", ".join(item_feedback))
                
                score += item_score
                matches += 1
            else:
                feedback.append(f"❌ {exp_sym}: Not found in portfolio")

        # Check for extra rows (Cleaner = better)
        if len(found_txs) > len(expected_txs):
            # No penalty, just feedback
            feedback.append(f"ℹ️ Note: Found {len(found_txs)} transactions, expected {len(expected_txs)}.")
        
        passed = (score >= 85) # Allow minor error or date format issue if everything else perfect
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(local_result):
            os.unlink(local_result)
        if os.path.exists(local_csv):
            os.unlink(local_csv)