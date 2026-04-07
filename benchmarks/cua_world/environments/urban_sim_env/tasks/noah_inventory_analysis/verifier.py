#!/usr/bin/env python3
"""Verifier for noah_inventory_analysis task."""

import json
import tempfile
import os
import re
import csv


def verify_noah_inventory(traj, env_info, task_info):
    """Verify NOAH inventory analysis was completed.

    Scoring (100 points total):
    - Notebook Execution (20 pts): Exists, executed, uses pandas/geopandas
    - NOAH Buildings CSV (25 pts): Proper columns and rows
    - Zone Summary CSV (25 pts): Proper aggregate columns
    - Data Integrity Check (15 pts): Math validation of noah_unit_pct
    - Choropleth Map (15 pts): Image exists and > 5KB
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []

    # ==========================================
    # Part 1: Read JSON result
    # ==========================================
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read task result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # ==========================================
    # Part 2: Notebook Execution (20 pts)
    # ==========================================
    nb_score = 0
    if result.get('notebook_exists') and result.get('notebook_modified'):
        nb_score += 5
    
    nb_a = result.get('notebook_analysis', {})
    if nb_a.get('num_executed_cells', 0) >= 3:
        nb_score += 5
    elif nb_a.get('num_executed_cells', 0) > 0:
        nb_score += 2
        
    if nb_a.get('has_pandas') and nb_a.get('has_geopandas'):
        nb_score += 5
    if nb_a.get('has_merge') and nb_a.get('has_groupby'):
        nb_score += 5
        
    score += nb_score
    feedback.append(f"Notebook: {nb_score}/20")

    # ==========================================
    # Part 3: NOAH Buildings CSV (25 pts)
    # ==========================================
    bld_score = 0
    if result.get('bld_csv_exists'):
        bld_score += 5
        if result.get('bld_csv_created'):
            bld_score += 5
            
        bld_cols = result.get('bld_csv_columns', '')
        has_req_cols = all(c in bld_cols for c in ['parcel_id', 'zone_id', 'residential_units', 'residential_sales_price'])
        if has_req_cols:
            bld_score += 10
            
        if result.get('bld_csv_rows', 0) > 50:
            bld_score += 5
            
    score += bld_score
    feedback.append(f"Buildings CSV: {bld_score}/25")

    # ==========================================
    # Part 4: Zone Summary CSV (25 pts)
    # ==========================================
    sum_score = 0
    if result.get('sum_csv_exists'):
        sum_score += 5
        if result.get('sum_csv_created'):
            sum_score += 5
            
        sum_cols = result.get('sum_csv_columns', '')
        has_req_cols = all(c in sum_cols for c in ['noah_building_count', 'noah_total_units', 'zone_total_units', 'noah_unit_pct'])
        if has_req_cols:
            sum_score += 10
            
        if result.get('sum_csv_rows', 0) > 10:
            sum_score += 5
            
    score += sum_score
    feedback.append(f"Summary CSV: {sum_score}/25")

    # ==========================================
    # Part 5: Choropleth Map (15 pts)
    # ==========================================
    plot_score = 0
    if result.get('plot_exists'):
        plot_score += 5
        if result.get('plot_created'):
            plot_score += 5
        if result.get('plot_size_kb', 0) >= 5:
            plot_score += 5
            
    score += plot_score
    feedback.append(f"Map: {plot_score}/15")

    # ==========================================
    # Part 6: Data Integrity Check (15 pts)
    # Validate the math: noah_unit_pct == noah_total_units / zone_total_units * 100
    # ==========================================
    integrity_score = 0
    csv_valid = False
    
    if result.get('sum_csv_exists'):
        csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            # Copy the summary CSV directly from container
            csv_path = metadata.get('expected_summary_csv', '/home/ga/urbansim_projects/output/zone_noah_summary.csv')
            copy_from_env(csv_path, csv_tmp.name)
            
            with open(csv_tmp.name, 'r') as f:
                reader = csv.DictReader(f)
                rows_checked = 0
                math_correct = 0
                
                # Check actual math logic in output
                for i, row in enumerate(reader):
                    if i >= 10:  # Just sample the first 10 rows
                        break
                    
                    try:
                        noah_u = float(row.get('noah_total_units', 0))
                        zone_u = float(row.get('zone_total_units', 0))
                        pct = float(row.get('noah_unit_pct', 0))
                        
                        rows_checked += 1
                        
                        if zone_u > 0:
                            expected_pct = (noah_u / zone_u) * 100
                            # Allow small floating point differences
                            if abs(pct - expected_pct) < 1.0 or abs(pct - expected_pct/100) < 0.01:
                                math_correct += 1
                        else:
                            if pct == 0:
                                math_correct += 1
                    except (ValueError, TypeError):
                        pass
                        
                if rows_checked > 0 and (math_correct / rows_checked) > 0.8:
                    integrity_score = 15
                    csv_valid = True
                    feedback.append(f"Data integrity verified: {math_correct}/{rows_checked} sampled rows had correct math")
                elif rows_checked > 0:
                    feedback.append(f"Data integrity failed: Math mismatch in noah_unit_pct ({math_correct}/{rows_checked} correct)")
                else:
                    feedback.append("Data integrity failed: Could not parse rows")
                    
        except Exception as e:
            feedback.append(f"Data integrity check failed: {e}")
        finally:
            if os.path.exists(csv_tmp.name):
                os.unlink(csv_tmp.name)
    else:
        feedback.append("Data integrity check skipped (no summary CSV)")
        
    score += integrity_score
    
    # Final pass conditions
    passed = score >= 70 and bld_score >= 15 and sum_score >= 15 and plot_score >= 5
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }