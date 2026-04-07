#!/usr/bin/env python3
"""Verifier for zoning_non_conformance_analysis task."""

import json
import tempfile
import os
import csv
import math

def verify_zoning_non_conformance(traj, env_info, task_info):
    """
    Verify the zoning non-conformance analysis task.
    
    Scoring System (100 points total):
    - Notebook Exists & Executed (10 points)
    - Code Logic/Analysis (10 points)
    - Scatter Plot Created & Valid (10 points)
    - Zone Summary CSV Created (10 points)
    - Non-Conforming CSV Created (10 points)
    - Mathematical Correctness of CSV (50 points)
        - Correct columns present (10)
        - built_far > max_far filter correctly applied (10)
        - built_far calculated correctly (10)
        - excess_sqft calculated correctly (10)
        - Sorted descending by excess_sqft (10)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # Part 1: Read the high-level export result
    result = None
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback.append(f"Could not read export result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result is None:
        return {"passed": False, "score": 0, "feedback": "; ".join(feedback)}

    # Notebook Exists & Executed (10 pts)
    if result.get('notebook_exists') and result.get('notebook_modified'):
        score += 5
    
    nb_a = result.get('notebook_analysis', {})
    num_exec = nb_a.get('num_executed_cells', 0)
    if num_exec and num_exec >= 4:
        score += 5
    elif num_exec and num_exec > 0:
        score += 2

    # Code Logic (10 pts)
    logic_score = 0
    if nb_a.get('has_pandas') and nb_a.get('has_hdf'):
        logic_score += 2
    if nb_a.get('has_groupby') and nb_a.get('has_merge'):
        logic_score += 3
    if nb_a.get('has_sqft_calc'):
        logic_score += 2
    if nb_a.get('has_far_calc') and nb_a.get('has_excess_calc'):
        logic_score += 3
    score += logic_score
    feedback.append(f"Notebook Code Logic: {logic_score}/10")

    # Plot verification (10 pts)
    if result.get('plot_exists'):
        score += 5
        if result.get('plot_created'):
            score += 3
        if result.get('plot_size_kb', 0) >= 15:
            score += 2
        feedback.append("Scatter plot verified")
    else:
        feedback.append("Scatter plot missing")

    # Zone Summary CSV (10 pts)
    if result.get('csv2_exists'):
        score += 5
        if result.get('csv2_created'):
            score += 5
        feedback.append("Zone summary CSV verified")
    else:
        feedback.append("Zone summary CSV missing")

    # Part 2: Rigorous Mathematical Check of Non-Conforming CSV (60 pts)
    csv_math_score = 0
    
    if not result.get('csv1_exists'):
        feedback.append("Non-conforming parcels CSV missing; failing math checks.")
    else:
        csv_math_score += 10 # CSV Created
        
        # Download and read the CSV directly
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/home/ga/urbansim_projects/output/non_conforming_parcels.csv", temp_csv.name)
            with open(temp_csv.name, 'r') as f:
                reader = csv.DictReader(f)
                columns = reader.fieldnames or []
                rows = list(reader)
                
            cols_lower = [c.lower().strip() for c in columns]
            expected_cols = ["parcel_id", "total_building_sqft", "parcel_sqft", "built_far", "max_far", "excess_sqft"]
            missing_cols = [c for c in expected_cols if not any(c in cl for cl in cols_lower)]
            
            # Map actual column names to expected semantics to handle slight naming variations
            col_map = {}
            for exp in expected_cols:
                for actual in cols_lower:
                    if exp in actual:
                        col_map[exp] = actual
                        break
            
            if len(missing_cols) == 0:
                csv_math_score += 10
                feedback.append("All required CSV columns present")
                
                # Check Math on Rows
                if len(rows) > 0:
                    filter_correct = True
                    far_correct = True
                    excess_correct = True
                    sort_correct = True
                    
                    prev_excess = float('inf')
                    
                    for row in rows:
                        # Normalize keys
                        r = {k.lower().strip(): v for k, v in row.items()}
                        
                        try:
                            built_far = float(r[col_map['built_far']])
                            max_far = float(r[col_map['max_far']])
                            excess = float(r[col_map['excess_sqft']])
                            tot_sqft = float(r[col_map['total_building_sqft']])
                            pcl_sqft = float(r[col_map['parcel_sqft']])
                            
                            # Check filter (built_far > max_far)
                            if built_far <= max_far:
                                filter_correct = False
                                
                            # Check built_far calculation
                            if pcl_sqft > 0:
                                expected_far = tot_sqft / pcl_sqft
                                if abs(built_far - expected_far) > 0.01:
                                    far_correct = False
                                    
                            # Check excess calculation
                            expected_excess = tot_sqft - (max_far * pcl_sqft)
                            if abs(excess - expected_excess) > 10.0: # Allow small rounding tolerance
                                excess_correct = False
                                
                            # Check sort (descending by excess_sqft)
                            if excess > prev_excess + 0.1: # Allow slight floating point jitter
                                sort_correct = False
                            prev_excess = excess
                            
                        except (ValueError, ZeroDivisionError, KeyError) as e:
                            # If parsing fails, math is broken
                            filter_correct = False
                            far_correct = False
                            excess_correct = False
                            sort_correct = False
                            break
                            
                    if filter_correct:
                        csv_math_score += 10
                        feedback.append("built_far > max_far filter correct")
                    else:
                        feedback.append("built_far > max_far filter failed")
                        
                    if far_correct:
                        csv_math_score += 10
                        feedback.append("built_far calculated correctly")
                    else:
                        feedback.append("built_far formula failed")
                        
                    if excess_correct:
                        csv_math_score += 10
                        feedback.append("excess_sqft calculated correctly")
                    else:
                        feedback.append("excess_sqft formula failed")
                        
                    if sort_correct:
                        csv_math_score += 10
                        feedback.append("Sorted by excess_sqft descending")
                    else:
                        feedback.append("Sorting failed")
                else:
                    feedback.append("CSV is empty, cannot verify math")
            else:
                feedback.append(f"Missing columns: {missing_cols}")
                
        except Exception as e:
            feedback.append(f"Failed to process CSV for math verification: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
                
    score += csv_math_score
    
    # Final evaluation
    passed = score >= 70 and csv_math_score >= 40
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }