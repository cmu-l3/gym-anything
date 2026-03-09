#!/usr/bin/env python3
"""
Verifier for chinook_regional_market_mapping task.

Verification Logic:
1. DBeaver connection created (10 pts)
2. 'region_mapping' table created and populated (25 pts)
   - Checks row count matches distinct countries
   - Checks specific country-region assignments
3. 'v_regional_sales' view created and correct (30 pts)
   - Checks if view exists
   - Compares view output (Revenue/Count) against calculated ground truth
4. CSV export file exists and contains data (20 pts)
5. SQL script saved (15 pts)

Total: 100 pts
Pass: 70 pts
"""

import json
import logging
import os
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_regional_market_mapping(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # 1. DBeaver Connection (10 pts)
    if result.get("dbeaver_connection", False):
        score += 10
        feedback.append("DBeaver connection confirmed.")
    else:
        feedback.append("DBeaver connection 'Chinook' not found.")

    # 2. Table Creation & Mapping Accuracy (25 pts)
    table_exists = result.get("table_exists", False)
    mapping_count = result.get("mapping_count", 0)
    ground_truth = result.get("ground_truth", {})
    expected_count = ground_truth.get("distinct_country_count", 24) # usually 24 in Chinook

    if table_exists:
        score += 5
        feedback.append("'region_mapping' table exists.")
        
        # Check completeness
        if mapping_count >= expected_count:
            score += 10
            feedback.append(f"Mapping table populated with {mapping_count} rows (Expected >= {expected_count}).")
        else:
            feedback.append(f"Mapping table missing rows. Found {mapping_count}, expected {expected_count}.")

        # Check accuracy of spot checks
        mappings = result.get("mappings", {})
        correct_mappings = 0
        checks = {
            "USA": "NA",
            "Brazil": "LATAM",
            "Germany": "EMEA",
            "India": "APAC"
        }
        
        for country, expected in checks.items():
            if mappings.get(country) == expected:
                correct_mappings += 1
        
        if correct_mappings == 4:
            score += 10
            feedback.append("Spot-checked country mappings are correct.")
        else:
            score += int((correct_mappings / 4) * 10)
            feedback.append(f"Some country mappings were incorrect ({correct_mappings}/4 passed).")

    else:
        feedback.append("'region_mapping' table NOT found.")

    # 3. View Logic & Aggregation (30 pts)
    view_exists = result.get("view_exists", False)
    view_data = result.get("view_data", [])
    
    if view_exists:
        score += 5
        feedback.append("'v_regional_sales' view exists.")
        
        # Verify aggregation values
        # We need to match rows from view_data to ground_truth['regions']
        # The view might use different column names, so we try to be flexible
        
        gt_regions = ground_truth.get("regions", {})
        matched_regions = 0
        total_regions_to_check = len(gt_regions)
        
        # Normalize view data for comparison
        # Detect column names from first row if available
        if isinstance(view_data, list) and len(view_data) > 0:
            first_row = view_data[0]
            # Helper to find value by loosely matching keys
            def get_val(row, *candidates):
                for k in row.keys():
                    if k.lower() in [c.lower() for c in candidates]:
                        return row[k]
                return None

            for row in view_data:
                # Try to identify which region this row is for
                # Look for RegionCode ('NA') or RegionName ('North America')
                r_code = None
                
                # Check against GT keys
                # Row might contain 'North America' instead of 'NA'
                # But our task asked for RegionName in the view.
                # Let's map names to codes if needed, or just look for the revenue match
                
                row_rev = get_val(row, 'TotalRevenue', 'Revenue', 'Total')
                
                if row_rev is not None:
                    try:
                        row_rev = float(row_rev)
                    except:
                        continue
                        
                    # Find matching region in GT by revenue
                    for code, gt_data in gt_regions.items():
                        gt_rev = gt_data['revenue']
                        # Check within 1% tolerance
                        if math.isclose(row_rev, gt_rev, rel_tol=0.01):
                            matched_regions += 1
                            break
            
            # Score based on matches
            # If we matched most regions, the view logic is likely correct
            if matched_regions >= (total_regions_to_check - 1): # Allow 1 miss
                score += 25
                feedback.append(f"View aggregation values match ground truth ({matched_regions} regions matched).")
            elif matched_regions > 0:
                partial = int((matched_regions / total_regions_to_check) * 25)
                score += partial
                feedback.append(f"View aggregation partially correct ({matched_regions}/{total_regions_to_check} regions matched).")
            else:
                feedback.append("View revenue values do not match ground truth.")
        else:
            feedback.append("View returned no data.")
    else:
        feedback.append("'v_regional_sales' view NOT found.")

    # 4. CSV Export (20 pts)
    if result.get("csv_exists", False) and result.get("csv_modified", False):
        score += 20
        feedback.append("CSV export found and modified.")
    elif result.get("csv_exists", False):
        score += 10
        feedback.append("CSV export found but timestamp indicates it wasn't created during this run.")
    else:
        feedback.append("CSV export NOT found.")

    # 5. SQL Script (15 pts)
    if result.get("sql_exists", False):
        score += 15
        feedback.append("SQL script found.")
    else:
        feedback.append("SQL script NOT found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }