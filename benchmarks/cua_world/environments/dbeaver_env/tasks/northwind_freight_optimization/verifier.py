#!/usr/bin/env python3
"""
Verifier for Northwind Freight Optimization Task.

Scoring Criteria:
1. DBeaver Connection Created (10 pts)
2. Database View 'v_country_shipper_stats' Created (20 pts)
3. SQL Script Saved (15 pts)
4. CSV Export Exists & Created During Task (10 pts)
5. CSV Columns Correct (10 pts)
6. CSV Data Accuracy (35 pts) - Matches ground truth logic

Pass Threshold: 65/100
"""

import json
import csv
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_northwind_freight_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Temp files for artifacts
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    ground_truth_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    csv_file = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')

    try:
        # 1. Load Task Result JSON
        try:
            copy_from_env("/tmp/task_result.json", result_file.name)
            with open(result_file.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

        score = 0
        feedback = []

        # Criterion 1: Connection (10 pts)
        if result.get('connection_found'):
            score += 10
            feedback.append("[SUCCESS] DBeaver connection 'Northwind' found.")
        else:
            feedback.append("[FAIL] DBeaver connection 'Northwind' not found.")

        # Criterion 2: View Exists (20 pts)
        if result.get('view_exists'):
            score += 20
            feedback.append("[SUCCESS] SQL View 'v_country_shipper_stats' exists in database.")
        else:
            feedback.append("[FAIL] SQL View 'v_country_shipper_stats' not found in database.")

        # Criterion 3: SQL Script (15 pts)
        if result.get('sql_exists'):
            score += 15
            feedback.append("[SUCCESS] Analysis SQL script saved.")
        else:
            feedback.append("[FAIL] Analysis SQL script not found.")

        # Criterion 4: CSV Exists & Fresh (10 pts)
        csv_valid = False
        if result.get('csv_exists') and result.get('csv_created_during_task'):
            score += 10
            feedback.append("[SUCCESS] Routing Guide CSV exported.")
            csv_valid = True
        elif result.get('csv_exists'):
            # Exists but old timestamp (anti-gaming)
            feedback.append("[FAIL] CSV file exists but was not created during this task session.")
        else:
            feedback.append("[FAIL] Routing Guide CSV not found.")

        # If CSV is valid, check content
        if csv_valid:
            try:
                # Load Ground Truth
                copy_from_env("/tmp/freight_ground_truth.json", ground_truth_file.name)
                with open(ground_truth_file.name, 'r') as f:
                    ground_truth = json.load(f)

                # Load Agent CSV
                copy_from_env("/home/ga/Documents/exports/routing_guide.csv", csv_file.name)
                
                with open(csv_file.name, 'r', encoding='utf-8-sig') as f:
                    reader = csv.DictReader(f)
                    rows = list(reader)
                    headers = reader.fieldnames if reader.fieldnames else []

                # Criterion 5: Column Headers (10 pts)
                required_cols = ["Country", "Recommended_Shipper", "Avg_Cost", "Potential_Savings"]
                # Normalize headers for check (case insensitive, strip)
                header_map = {h.strip().lower(): h for h in headers}
                missing_cols = [c for c in required_cols if c.lower() not in header_map]

                if not missing_cols:
                    score += 10
                    feedback.append("[SUCCESS] CSV columns match requirements.")
                else:
                    feedback.append(f"[FAIL] Missing CSV columns: {', '.join(missing_cols)}")
                    # Proceed with partial check if possible

                # Criterion 6: Data Accuracy (35 pts)
                # Check 5 random countries or all of them
                total_checks = 0
                passed_checks = 0
                
                # Identify column names from map
                col_country = header_map.get("country")
                col_shipper = header_map.get("recommended_shipper")
                col_savings = header_map.get("potential_savings")
                col_cost = header_map.get("avg_cost")

                if col_country and col_shipper and col_savings:
                    for row in rows:
                        country = row.get(col_country)
                        if country in ground_truth:
                            total_checks += 1
                            gt = ground_truth[country]
                            
                            # Check Shipper
                            agent_shipper = row.get(col_shipper, "").strip()
                            gt_shipper = gt['Recommended_Shipper']
                            
                            # Check Savings (allow small tolerance)
                            try:
                                agent_savings = float(row.get(col_savings, 0))
                                gt_savings = float(gt['Potential_Savings'])
                                savings_match = math.isclose(agent_savings, gt_savings, abs_tol=0.1)
                            except ValueError:
                                savings_match = False
                                
                            if agent_shipper == gt_shipper and savings_match:
                                passed_checks += 1
                    
                    if total_checks > 0:
                        accuracy = passed_checks / total_checks
                        points_awarded = int(accuracy * 35)
                        score += points_awarded
                        feedback.append(f"[INFO] Data Accuracy: {passed_checks}/{total_checks} rows match ground truth. ({points_awarded}/35 pts)")
                    else:
                        feedback.append("[FAIL] No matching country names found in CSV to verify against ground truth.")
                else:
                    feedback.append("[FAIL] Cannot verify data accuracy due to missing columns.")

            except Exception as e:
                feedback.append(f"[FAIL] Error verifying CSV content: {str(e)}")
        
        passed = score >= 65
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    finally:
        # Cleanup
        if os.path.exists(result_file.name): os.unlink(result_file.name)
        if os.path.exists(ground_truth_file.name): os.unlink(ground_truth_file.name)
        if os.path.exists(csv_file.name): os.unlink(csv_file.name)