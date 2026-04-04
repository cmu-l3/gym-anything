#!/usr/bin/env python3
"""
Verifier for compute_hydraulic_geometry task.

Checks:
1. CSV file existence and column structure.
2. Physical consistency: Area and Perimeter must increase with Elevation.
3. Calculation accuracy: Hydraulic Radius = Area / Perimeter.
4. Summary file content checks.
"""

import json
import os
import csv
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hydraulic_geometry(traj, env_info, task_info):
    """
    Verify the hydraulic properties table computed by the agent.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Scoring weights
    SCORE_CSV_EXISTS = 10
    SCORE_COLUMNS_CORRECT = 10
    SCORE_ROWS_SUFFICIENT = 10
    SCORE_MONOTONIC_AREA = 20
    SCORE_MONOTONIC_PERIM = 10
    SCORE_HYDRAULIC_RADIUS_CALC = 20
    SCORE_SUMMARY_MATCH = 10
    SCORE_ANTI_GAMING = 10  # Created during task

    score = 0
    feedback = []
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check existence
    if not result.get('csv_exists'):
        return {"passed": False, "score": 0, "feedback": "Hydraulic properties CSV file not found."}
    score += SCORE_CSV_EXISTS
    feedback.append("CSV file found.")

    if result.get('file_created_during_task'):
        score += SCORE_ANTI_GAMING
        feedback.append("File created during task session.")
    else:
        feedback.append("WARNING: File timestamps suggest pre-existence.")

    # 2. Load and Analyze CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/hydraulic_properties.csv", temp_csv.name)
        
        with open(temp_csv.name, 'r') as f:
            # Handle potential BOM or whitespace
            sample = f.read(1024)
            has_header = csv.Sniffer().has_header(sample)
            f.seek(0)
            
            reader = csv.DictReader(f)
            rows = list(reader)
            headers = reader.fieldnames
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Verify Columns
    required_cols = {'Elevation_ft', 'Area_sqft', 'WettedPerimeter_ft', 'HydraulicRadius_ft', 'TopWidth_ft'}
    # normalize headers to ignore case and whitespace
    clean_headers = {h.strip() for h in headers} if headers else set()
    
    # Allow some variation in naming if clear (e.g., 'Elevation' vs 'Elevation_ft')
    # But strictly checking described names is safer for automated grading
    missing_cols = []
    for req in required_cols:
        if req not in clean_headers:
            missing_cols.append(req)
            
    if not missing_cols:
        score += SCORE_COLUMNS_CORRECT
        feedback.append("Column headers correct.")
    else:
        feedback.append(f"Missing columns: {missing_cols}")
        # Fail early if critical data missing
        if 'Area_sqft' in missing_cols or 'Elevation_ft' in missing_cols:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Verify Data Count
    if len(rows) >= 15:
        score += SCORE_ROWS_SUFFICIENT
        feedback.append(f"Sufficient data points ({len(rows)} rows).")
    else:
        feedback.append(f"Insufficient data points ({len(rows)} < 15).")

    # Verify Physical Consistency
    elevations = []
    areas = []
    perimeters = []
    radii_calc_errors = 0
    monotonicity_errors_area = 0
    monotonicity_errors_perim = 0
    
    try:
        for i, row in enumerate(rows):
            elev = float(row.get('Elevation_ft', 0))
            area = float(row.get('Area_sqft', 0))
            perim = float(row.get('WettedPerimeter_ft', 0))
            radius = float(row.get('HydraulicRadius_ft', 0))
            
            elevations.append(elev)
            areas.append(area)
            perimeters.append(perim)
            
            # Check Hydraulic Radius Calculation: R = A / P
            # Avoid divide by zero
            if perim > 0.001:
                calc_r = area / perim
                if abs(calc_r - radius) > 0.05 * max(calc_r, 1.0): # 5% tolerance
                    radii_calc_errors += 1
            elif radius > 0.001:
                # If perim is 0 but radius is not, that's an error
                radii_calc_errors += 1

            # Check Monotonicity (Current vs Previous)
            if i > 0:
                if area < areas[i-1] - 0.01: # Allow tiny float noise
                    monotonicity_errors_area += 1
                if perim < perimeters[i-1] - 0.01:
                    monotonicity_errors_perim += 1

        # Score Physical Checks
        if monotonicity_errors_area == 0:
            score += SCORE_MONOTONIC_AREA
            feedback.append("Area increases monotonically.")
        else:
            feedback.append(f"Area decreases with elevation in {monotonicity_errors_area} rows (Physical impossibility).")

        if monotonicity_errors_perim == 0:
            score += SCORE_MONOTONIC_PERIM
            feedback.append("Perimeter increases monotonically.")
        else:
            feedback.append(f"Perimeter decreases with elevation in {monotonicity_errors_perim} rows.")

        if radii_calc_errors == 0:
            score += SCORE_HYDRAULIC_RADIUS_CALC
            feedback.append("Hydraulic Radius calculations are correct.")
        else:
            feedback.append(f"Hydraulic Radius mismatch in {radii_calc_errors} rows.")

    except ValueError as e:
        feedback.append("Error parsing numerical values in CSV.")
        
    # 3. Check Summary File
    summary_match = False
    if result.get('summary_exists'):
        temp_sum = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/cross_section_summary.txt", temp_sum.name)
            with open(temp_sum.name, 'r') as f:
                content = f.read()
                # Check for Thalweg match
                if elevations:
                    min_elev = min(elevations)
                    # Check if min_elev appears in text (rough string check)
                    if f"{min_elev:.1f}" in content or f"{min_elev:.2f}" in content:
                        summary_match = True
                    # Also check for River Station keyword
                    if "Station" in content:
                        summary_match = True
        except:
            pass
        finally:
            if os.path.exists(temp_sum.name):
                os.unlink(temp_sum.name)
                
    if summary_match:
        score += SCORE_SUMMARY_MATCH
        feedback.append("Summary file content matches CSV data.")
    elif result.get('summary_exists'):
        feedback.append("Summary file exists but content mismatch or parse error.")

    # Final Pass Decision
    # Need consistent area physics + calculation + file existence
    passed = (score >= 60) and (monotonicity_errors_area == 0) and (result.get('csv_exists'))

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }