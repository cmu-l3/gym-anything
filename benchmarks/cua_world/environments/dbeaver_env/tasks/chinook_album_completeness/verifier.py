#!/usr/bin/env python3
"""
Verifier for chinook_album_completeness task.

Verifies:
1. DBeaver connection 'Chinook' exists (10 pts)
2. SQL script exists (10 pts)
3. CSV output exists and has valid structure (20 pts)
4. 'Full Album' logic correctness (Revenue & Count) (30 pts)
5. 'Single/Partial' logic correctness (Revenue & Count) (30 pts)

Uses ground truth calculated during setup for robust verification.
"""

import json
import os
import csv
import logging
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_album_completeness(traj, env_info, task_info):
    """
    Verify the Album vs Single buying behavior analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temp file management
    temp_files = []
    
    def get_file_content(remote_path, is_json=True):
        local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json' if is_json else '.txt')
        temp_files.append(local_tmp.name)
        local_tmp.close()
        try:
            copy_from_env(remote_path, local_tmp.name)
            if is_json:
                with open(local_tmp.name, 'r') as f:
                    return json.load(f)
            else:
                # Return path for non-json files (like CSV)
                return local_tmp.name
        except Exception as e:
            logger.warning(f"Failed to copy/read {remote_path}: {e}")
            return None

    try:
        # 1. Load Task Result Metadata
        task_result = get_file_content("/tmp/task_result.json")
        if not task_result:
            return {"passed": False, "score": 0, "feedback": "Failed to load task result metadata."}

        # 2. Load Ground Truth
        ground_truth = get_file_content("/tmp/ground_truth.json")
        if not ground_truth:
            return {"passed": False, "score": 0, "feedback": "System Error: Ground truth file missing."}

        # 3. Load User CSV (if exists)
        user_csv_path = None
        if task_result.get('csv_exists'):
            user_csv_path = get_file_content(task_result['csv_path'], is_json=False)

        # --- SCORING ---
        score = 0
        feedback = []
        passed = False

        # Crit 1: DBeaver Connection (10 pts)
        if task_result.get('connection_found'):
            score += 10
            feedback.append("DBeaver connection 'Chinook' verified.")
        else:
            feedback.append("Missing DBeaver connection 'Chinook'.")

        # Crit 2: SQL Script Exists (10 pts)
        if task_result.get('sql_exists'):
            score += 10
            feedback.append("SQL script file saved.")
        else:
            feedback.append("SQL script file missing.")

        # Crit 3: CSV Structure (20 pts)
        csv_valid = False
        user_data = {}
        
        if user_csv_path:
            try:
                with open(user_csv_path, 'r', encoding='utf-8-sig') as f:
                    # Sniff format to handle potential variations
                    sample = f.read(1024)
                    f.seek(0)
                    dialect = csv.Sniffer().sniff(sample)
                    reader = csv.DictReader(f, dialect=dialect)
                    
                    # Normalize headers
                    headers = [h.strip() for h in reader.fieldnames]
                    required = ["PurchaseType", "TotalRevenue", "TransactionCount"]
                    
                    # Loose header matching
                    header_map = {}
                    for req in required:
                        match = next((h for h in headers if req.lower() in h.lower()), None)
                        if match:
                            header_map[req] = match
                    
                    if len(header_map) == 3:
                        score += 20
                        csv_valid = True
                        feedback.append("CSV file exists and has correct headers.")
                        
                        # Parse Data
                        for row in reader:
                            # Normalize PurchaseType key
                            p_type = row[header_map['PurchaseType']].strip()
                            
                            # Normalize numbers
                            try:
                                rev = float(row[header_map['TotalRevenue']].replace(',','').replace('$',''))
                                count = int(row[header_map['TransactionCount']].replace(',',''))
                                user_data[p_type] = {"TotalRevenue": rev, "TransactionCount": count}
                            except ValueError:
                                continue # Skip invalid rows
                    else:
                        feedback.append(f"CSV missing required headers. Found: {headers}")
            except Exception as e:
                feedback.append(f"Failed to parse CSV: {str(e)}")
        else:
            feedback.append("CSV output file missing.")

        # Crit 4 & 5: Data Accuracy (60 pts total)
        # We check both categories: 'Full Album' and 'Single/Partial'
        
        # Helper for matching loosely
        def find_category_match(target_cat):
            # Try exact match first
            if target_cat in user_data:
                return user_data[target_cat]
            # Try partial string match
            for k, v in user_data.items():
                if target_cat.lower() in k.lower():
                    return v
            return None

        categories = ["Full Album", "Single/Partial"]
        
        if csv_valid:
            for cat in categories:
                gt = ground_truth.get(cat)
                user_val = find_category_match(cat)
                
                cat_score = 0
                if gt and user_val:
                    # Check Count (Exact) - 15 pts per category
                    if user_val['TransactionCount'] == gt['TransactionCount']:
                        score += 15
                        cat_score += 15
                        feedback.append(f"'{cat}' Count matched ({gt['TransactionCount']}).")
                    else:
                        feedback.append(f"'{cat}' Count mismatch: Got {user_val['TransactionCount']}, Expected {gt['TransactionCount']}.")
                    
                    # Check Revenue (Tolerance +/- 1.0) - 15 pts per category
                    if math.isclose(user_val['TotalRevenue'], gt['TotalRevenue'], abs_tol=1.0):
                        score += 15
                        cat_score += 15
                        feedback.append(f"'{cat}' Revenue matched ({gt['TotalRevenue']:.2f}).")
                    else:
                        diff = abs(user_val['TotalRevenue'] - gt['TotalRevenue'])
                        # Partial credit if within 10%
                        if diff / gt['TotalRevenue'] < 0.1:
                            score += 7
                            cat_score += 7
                            feedback.append(f"'{cat}' Revenue close ({user_val['TotalRevenue']:.2f}).")
                        else:
                            feedback.append(f"'{cat}' Revenue mismatch: Got {user_val['TotalRevenue']:.2f}, Expected {gt['TotalRevenue']:.2f}.")
                else:
                    feedback.append(f"Category '{cat}' not found in user output.")

        # Final Evaluation
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        # Cleanup temp files
        for f in temp_files:
            if os.path.exists(f):
                try:
                    os.unlink(f)
                except:
                    pass