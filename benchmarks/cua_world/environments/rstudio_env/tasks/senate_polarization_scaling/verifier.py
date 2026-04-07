#!/usr/bin/env python3
"""
Verifier for senate_polarization_scaling task.

Verification Strategy:
1. File Existence & Timestamps (20 pts): CSV and Plot must be created during the task.
2. Script Validation (10 pts): Script modified and contains scaling keywords.
3. Data Integrity (30 pts): 
   - CSV has > 50 rows (Senate size is 100, assuming some dropouts or full membership).
   - CSV has required columns: icpsr, name, party_code, dim1.
4. Political Validity (40 pts):
   - Strong correlation between Party and Dim1 (Polarization check).
   - Joe Manchin (29940) identified as a centrist (Dim1 between Dem median and Rep median).

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
import statistics

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_senate_polarization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Timestamps (20 pts)
    if result.get('csv_exists') and result.get('csv_is_new'):
        score += 10
        feedback_parts.append("CSV output created (10/10)")
    elif result.get('csv_exists'):
        score += 2
        feedback_parts.append("CSV exists but not new (2/10)")
        
    if result.get('plot_exists') and result.get('plot_is_new') and result.get('plot_size_bytes', 0) > 10000:
        score += 10
        feedback_parts.append("Plot output created (10/10)")
    elif result.get('plot_exists'):
        score += 2
        feedback_parts.append("Plot exists but not new/empty (2/10)")

    # 2. Script Validation (10 pts)
    if result.get('script_modified') and result.get('has_scaling_code'):
        score += 10
        feedback_parts.append("Script uses scaling methods (10/10)")
    else:
        feedback_parts.append("Script not modified or missing scaling code (0/10)")

    # 3. Data Integrity (30 pts)
    rows = result.get('csv_data', [])
    if len(rows) > 90:
        score += 10
        feedback_parts.append(f"Correct row count: {len(rows)} (10/10)")
    elif len(rows) > 10:
        score += 5
        feedback_parts.append(f"Low row count: {len(rows)} (5/10)")
    else:
        feedback_parts.append("Empty or missing data (0/10)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Check columns
    required_cols = ['icpsr', 'dim1'] # flexible on others
    first_row = rows[0]
    keys = [k.lower() for k in first_row.keys()]
    
    has_icpsr = any('icpsr' in k for k in keys)
    has_dim1 = any(k == 'dim1' or k == 'coord1d' or 'd1' in k for k in keys)
    has_party = any('party' in k for k in keys)
    
    if has_icpsr and has_dim1 and has_party:
        score += 20
        feedback_parts.append("Required columns present (20/20)")
    else:
        feedback_parts.append(f"Missing columns (Have: {keys}) (0/20)")
        # Cannot proceed with logic check if columns missing
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. Political Validity (40 pts)
    # Parse data for logic checks
    dems = []
    reps = []
    manchin_score = None
    
    try:
        dim1_key = next(k for k in keys if k == 'dim1' or k == 'coord1d' or 'd1' in k)
        party_key = next(k for k in keys if 'party' in k)
        icpsr_key = next(k for k in keys if 'icpsr' in k)

        for row in rows:
            try:
                # Handle Party Code (100 Dem, 200 Rep)
                p_val = int(float(row[party_key]))
                d1_val = float(row[dim1_key])
                icpsr_val = int(float(row[icpsr_key]))
                
                if p_val == 100:
                    dems.append(d1_val)
                elif p_val == 200:
                    reps.append(d1_val)
                
                if icpsr_val == 29940:
                    manchin_score = d1_val
            except (ValueError, TypeError):
                continue
                
        # Metric A: Polarization (Separation)
        if dems and reps:
            median_dem = statistics.median(dems)
            median_rep = statistics.median(reps)
            
            # Check if distributions are distinct (distance between medians > sum of std devs? or just decent gap)
            # Simplest: Are the medians significantly different?
            diff = abs(median_rep - median_dem)
            
            # In W-NOMINATE, range is [-1, 1]. Gap should be large, e.g., > 0.5
            if diff > 0.3: 
                score += 20
                feedback_parts.append(f"Clear partisan separation detected (Gap: {diff:.2f}) (20/20)")
            else:
                feedback_parts.append(f"Weak partisan separation (Gap: {diff:.2f}) (0/20)")
                
            # Metric B: Manchin Centrist Check
            # Manchin should be 'between' the median Dem and median Rep, 
            # OR at least the most conservative Democrat (closest to Rep median)
            
            if manchin_score is not None:
                # Normalized direction: if Reps are positive, Manchin should be > Median Dem
                if median_rep > median_dem:
                    is_centrist = manchin_score > median_dem
                else:
                    is_centrist = manchin_score < median_dem
                    
                if is_centrist:
                    score += 20
                    feedback_parts.append("Manchin identified as centrist relative to party median (20/20)")
                else:
                    feedback_parts.append(f"Manchin score {manchin_score:.2f} not centrist direction (Medians: D={median_dem:.2f}, R={median_rep:.2f}) (0/20)")
            else:
                 feedback_parts.append("Manchin (ICPSR 29940) not found in data (0/20)")

        else:
            feedback_parts.append("Could not parse party data for Dem/Rep (0/40)")

    except Exception as e:
        feedback_parts.append(f"Error validating data logic: {str(e)} (0/40)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }