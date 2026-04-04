#!/usr/bin/env python3
"""
Verifier for shipping_relationship_model task.

Checks:
1. Backlog_Analysis.pbix exists and was created during task.
2. backlog_data.csv exists and contains data.
3. CSV data shows divergence between 'Orders_Placed' and 'Orders_Shipped' (proof of logic).
4. DataModel contains 'USERELATIONSHIP' string (proof of method).
5. Visual type is Line Chart.
"""

import json
import os
import tempfile
import logging
import csv
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shipping_relationship_model(traj, env_info, task_info):
    """
    Verify the shipping relationship model task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Fetch result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/Desktop/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. PBIX File Existence & Creation (15 pts)
    if result.get('pbix_exists') and result.get('file_created_during_task'):
        score += 15
        feedback_parts.append("PBIX file created successfully")
    elif result.get('pbix_exists'):
        score += 5
        feedback_parts.append("PBIX file exists but creation timestamp uncertain")
    else:
        feedback_parts.append("PBIX file not found")

    # 2. DAX Implementation Check (25 pts)
    # Check for USERELATIONSHIP which is required for the inactive relationship logic
    if result.get('model_contains_userelationship'):
        score += 25
        feedback_parts.append("Correct DAX used (USERELATIONSHIP found)")
    else:
        feedback_parts.append("DAX missing USERELATIONSHIP function")

    measures = result.get('model_measure_names', [])
    if "Orders_Placed" in measures and "Orders_Shipped" in measures:
        score += 10
        feedback_parts.append("Measure names correct")
    else:
        feedback_parts.append(f"Missing required measures (Found: {measures})")

    # 3. Visual Configuration (10 pts)
    visuals = result.get('visual_types', [])
    if "lineChart" in visuals or "cartesian" in visuals:
        score += 10
        feedback_parts.append("Line chart used")
    else:
        feedback_parts.append("Visual type incorrect or not found")

    # 4. Data Export & Logic Verification (40 pts)
    csv_content = result.get('csv_content_sample', '').strip()
    csv_exists = result.get('csv_exists')
    
    if csv_exists and csv_content:
        score += 10
        feedback_parts.append("Data exported to CSV")
        
        # Parse CSV to verify logic
        # Expecting: Date, Orders_Placed, Orders_Shipped
        # If Placed == Shipped for all rows, they failed the inactive relationship
        try:
            reader = csv.reader(io.StringIO(csv_content))
            headers = next(reader)
            
            # Identify columns (case insensitive)
            headers_lower = [h.lower() for h in headers]
            
            # We need at least 2 numeric columns to compare
            if len(headers) >= 3:
                rows_checked = 0
                diff_found = False
                
                for row in reader:
                    if len(row) < 3: continue
                    try:
                        # Assuming format: Date, Val1, Val2 (order varies)
                        # We just check if there are two different numeric values in the row
                        nums = []
                        for cell in row:
                            try:
                                nums.append(float(cell.replace(',','')))
                            except:
                                pass
                        
                        if len(nums) >= 2:
                            # If numbers differ, it implies different calculations (correct)
                            # If they are identical every time, they likely used active rel for both
                            if nums[0] != nums[1]:
                                diff_found = True
                            rows_checked += 1
                    except:
                        pass
                
                if diff_found:
                    score += 30
                    feedback_parts.append("Data values differ correctly (Active vs Inactive logic works)")
                elif rows_checked > 0:
                    feedback_parts.append("Data values are identical for Placed vs Shipped (likely missed USERELATIONSHIP)")
                else:
                    score += 10 # Credit for exporting something readable
                    feedback_parts.append("Could not verify data divergence")
            else:
                feedback_parts.append("CSV has insufficient columns")
                
        except Exception as e:
            feedback_parts.append(f"Error parsing CSV: {str(e)}")
    else:
        feedback_parts.append("CSV export missing or empty")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }