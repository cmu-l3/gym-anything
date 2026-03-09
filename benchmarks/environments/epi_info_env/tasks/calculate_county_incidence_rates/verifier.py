#!/usr/bin/env python3
"""
Verifier for calculate_county_incidence_rates task.
"""

import json
import tempfile
import os
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_county_rates(traj, env_info, task_info):
    """
    Verify that the agent correctly calculated incidence rates.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    ground_truth_path = metadata.get('ground_truth_path', r'C:\ProgramData\EpiInfo\ground_truth.json')
    output_path = metadata.get('output_path', r'C:\Users\Docker\Documents\CountyAnalysis\FinalRates.csv')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_result_path = f.name
    
    try:
        copy_from_env(r'C:\ProgramData\EpiInfo\task_result.json', temp_result_path)
        with open(temp_result_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_path): os.unlink(temp_result_path)

    # 2. Basic Checks (App running, Project created)
    if task_result.get('app_was_running', False):
        score += 5
        feedback_parts.append("Epi Info was running.")
        
    if task_result.get('project_created', False):
        score += 5
        feedback_parts.append("Project file created.")

    # 3. Check Output File Existence
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": score, "feedback": "Output file FinalRates.csv not found."}
    
    score += 10
    feedback_parts.append("Output file exists.")

    if not task_result.get('file_created_during_task', False):
        feedback_parts.append("WARNING: File timestamp suggests it wasn't created during this session.")
        # We don't fail immediately but penalty applies

    # 4. Retrieve Ground Truth and Output Data
    ground_truth = {}
    output_data = []
    
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        gt_temp = f.name
    with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as f:
        out_temp = f.name
        
    try:
        # Get Ground Truth
        copy_from_env(ground_truth_path, gt_temp)
        with open(gt_temp, 'r') as f:
            ground_truth = json.load(f) # Format: {"County": {"Count": X, "Pop": Y, "Rate": Z}}

        # Get Agent Output
        copy_from_env(output_path, out_temp)
        
        # Parse CSV
        with open(out_temp, 'r', encoding='utf-8-sig') as f:
            reader = csv.DictReader(f)
            # Normalize headers (lowercase)
            reader.fieldnames = [name.lower() for name in reader.fieldnames]
            
            # Check for required columns
            required = ['county', 'incidencerate']
            if not all(any(r in h for h in reader.fieldnames) for r in required):
                 return {"passed": False, "score": score, "feedback": f"Missing required columns. Found: {reader.fieldnames}"}
            
            for row in reader:
                # Find the actual key names in the row that match our lowercased expectation
                county_key = next((k for k in row.keys() if 'county' in k.lower()), None)
                rate_key = next((k for k in row.keys() if 'rate' in k.lower()), None)
                
                if county_key and rate_key:
                    output_data.append({
                        'County': row[county_key],
                        'Rate': row[rate_key]
                    })

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error parsing data: {str(e)}"}
    finally:
        if os.path.exists(gt_temp): os.unlink(gt_temp)
        if os.path.exists(out_temp): os.unlink(out_temp)

    # 5. Data Verification
    
    # Check 5.1: All counties present (20 pts)
    gt_counties = set(ground_truth.keys())
    agent_counties = set([d['County'] for d in output_data])
    
    # Allow loose matching on county names
    matched_counties = 0
    for gtc in gt_counties:
        if any(gtc.lower() in ac.lower() for ac in agent_counties):
            matched_counties += 1
            
    if matched_counties == len(gt_counties):
        score += 20
        feedback_parts.append("All 5 counties present.")
    else:
        feedback_parts.append(f"Missing counties. Found {matched_counties}/{len(gt_counties)}.")

    # Check 5.2: Zero-case handling (20 pts)
    # Find the county with 0 count in GT
    zero_county = next((k for k, v in ground_truth.items() if v['Count'] == 0), None)
    zero_handled_correctly = False
    
    if zero_county:
        # Find this county in output
        agent_row = next((r for r in output_data if zero_county.lower() in r['County'].lower()), None)
        if agent_row:
            try:
                rate = float(agent_row['Rate'])
                if rate == 0.0:
                    score += 20
                    zero_handled_correctly = True
                    feedback_parts.append(f"Zero-case county ({zero_county}) correctly handled.")
                else:
                    feedback_parts.append(f"Zero-case county ({zero_county}) has non-zero rate: {rate}.")
            except:
                feedback_parts.append(f"Invalid rate format for zero-case county.")
        else:
            feedback_parts.append(f"Zero-case county ({zero_county}) missing from output.")
    
    # Check 5.3: Rate Accuracy (40 pts)
    correct_rates = 0
    total_comparisons = 0
    
    for gtc, gtv in ground_truth.items():
        if gtv['Count'] == 0: continue # Already checked
        
        total_comparisons += 1
        agent_row = next((r for r in output_data if gtc.lower() in r['County'].lower()), None)
        
        if agent_row:
            try:
                agent_rate = float(agent_row['Rate'])
                gt_rate = float(gtv['Rate'])
                
                # Tolerance: +/- 0.5 per 100,000 or 1%
                if math.isclose(agent_rate, gt_rate, abs_tol=0.5):
                    correct_rates += 1
            except:
                pass
                
    if total_comparisons > 0:
        rate_score = int((correct_rates / total_comparisons) * 40)
        score += rate_score
        feedback_parts.append(f"Rate accuracy: {correct_rates}/{total_comparisons} correct.")
    
    # 6. Pass/Fail
    # Must have file, all counties, and reasonable accuracy
    passed = (score >= 70) and zero_handled_correctly
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }