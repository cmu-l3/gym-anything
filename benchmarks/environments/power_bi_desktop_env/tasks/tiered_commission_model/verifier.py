#!/usr/bin/env python3
"""
Verifier for Tiered Commission Model task.

Checks:
1. PBIX existence and freshness.
2. Visuals: Matrix and Scatter chart existence.
3. DAX/Logic: Validates the content of the exported CSV against the specified logic.

Logic to verify:
- < 80% attainment: 0% commission
- 80% - 110% attainment: 5% commission
- > 110% attainment: 8% commission
"""

import json
import os
import tempfile
import logging
import csv
import io

logger = logging.getLogger(__name__)

def verify_tiered_commission_model(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Setup temp files
    result_json_path = tempfile.mktemp(suffix='.json')
    csv_path = tempfile.mktemp(suffix='.csv')
    layout_path = tempfile.mktemp(suffix='.json')
    
    score = 0
    feedback = []
    
    try:
        # Copy files
        copy_from_env("/tmp/task_result.json", result_json_path)
        copy_from_env("/tmp/exported_commission.csv", csv_path)
        copy_from_env("/tmp/Layout.json", layout_path)
        
        # Load Result JSON
        with open(result_json_path, 'r') as f:
            res_data = json.load(f)
            
        # 1. File Artifacts (10 pts)
        if res_data.get('pbix_exists') and res_data.get('csv_exists'):
            score += 10
            feedback.append("Both PBIX and CSV files found.")
        else:
            feedback.append("Missing PBIX or CSV output.")
            
        # 2. Anti-Gaming (Timestamp check) (10 pts)
        if res_data.get('pbix_created_during_task') and res_data.get('csv_created_during_task'):
            score += 10
        elif res_data.get('pbix_exists'):
            feedback.append("Files detected but timestamps indicate they may be pre-existing.")

        # 3. Visuals check via Layout JSON (20 pts)
        try:
            with open(layout_path, 'r', encoding='utf-8-sig', errors='ignore') as f:
                layout_data = f.read()
                
            has_matrix = 'pivotTable' in layout_data or 'matrix' in layout_data.lower()
            has_scatter = 'scatterChart' in layout_data
            
            if has_matrix:
                score += 10
                feedback.append("Matrix visual found.")
            else:
                feedback.append("Matrix visual NOT found.")
                
            if has_scatter:
                score += 10
                feedback.append("Scatter chart found.")
            else:
                feedback.append("Scatter chart NOT found.")
                
        except Exception as e:
            feedback.append(f"Could not verify visuals: {e}")

        # 4. Calculation Verification (60 pts)
        # We need to parse the CSV and check the math
        try:
            valid_rows = 0
            correct_calcs = 0
            
            with open(csv_path, 'r', encoding='utf-8-sig', errors='replace') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                
            if not rows:
                feedback.append("Exported CSV is empty.")
            else:
                # Identify columns flexibly
                headers = rows[0].keys()
                
                # Helper to find column by partial match
                def get_col(candidates):
                    for h in headers:
                        if any(c.lower() in h.lower() for c in candidates):
                            return h
                    return None
                
                col_sales = get_col(['Total_Sales', 'Sales', 'Sales_Amount'])
                col_quota = get_col(['Quota', 'Target'])
                col_comm = get_col(['Commission', 'Payout'])
                
                if not (col_sales and col_quota and col_comm):
                    feedback.append(f"Could not identify required columns in CSV headers: {list(headers)}")
                else:
                    feedback.append(f"Verifying math on {len(rows)} rows...")
                    for row in rows:
                        try:
                            # Parse numbers (remove currency symbols, commas)
                            def clean_num(s):
                                return float(str(s).replace('$','').replace(',','').replace('%','').strip() or 0)
                            
                            sales = clean_num(row[col_sales])
                            quota = clean_num(row[col_quota])
                            comm_reported = clean_num(row[col_comm])
                            
                            if quota == 0: continue
                            
                            attainment = sales / quota
                            
                            # Recalculate Logic
                            expected_comm = 0.0
                            if attainment < 0.80:
                                expected_comm = 0.0
                            elif 0.80 <= attainment <= 1.10:
                                expected_comm = sales * 0.05
                            else: # > 1.10
                                expected_comm = sales * 0.08
                                
                            # Check with tolerance
                            if abs(comm_reported - expected_comm) < 5.0: # $5 tolerance
                                correct_calcs += 1
                            else:
                                # debug
                                # feedback.append(f"Row fail: Sales={sales}, Quota={quota}, Att={attainment:.2f}, Exp={expected_comm}, Got={comm_reported}")
                                pass
                                
                            valid_rows += 1
                            
                        except ValueError:
                            continue
                    
                    if valid_rows > 0:
                        accuracy = correct_calcs / valid_rows
                        pts = int(60 * accuracy)
                        score += pts
                        feedback.append(f"Calculation Accuracy: {accuracy:.1%} ({correct_calcs}/{valid_rows} rows correct).")
                    else:
                        feedback.append("No valid numeric rows found to verify.")

        except Exception as e:
            feedback.append(f"Error validating CSV data: {e}")

    except Exception as e:
        feedback.append(f"Fatal verification error: {e}")
    finally:
        # Cleanup
        if os.path.exists(result_json_path): os.unlink(result_json_path)
        if os.path.exists(csv_path): os.unlink(csv_path)
        if os.path.exists(layout_path): os.unlink(layout_path)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }