#!/usr/bin/env python3
"""
Verifier for fleet_technical_manual task.
Checks:
1. Manual text file creation, structure, and content.
2. CSV index file creation, valid CSV structure, and data accuracy against Ground Truth.
3. Scenario creation, valid parameters, and valid model references.
"""

import json
import os
import csv
import io
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fleet_technical_manual(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    # Unpack Data
    manual = result.get('manual', {})
    csv_res = result.get('csv', {})
    scenario = result.get('scenario', {})
    ground_truth = result.get('ground_truth', {})
    
    total_models_available = len(ground_truth)
    if total_models_available == 0:
        # Fallback if ground truth generation failed (shouldn't happen)
        total_models_available = 1 
        feedback.append("WARNING: Ground truth generation failed, scoring may be inaccurate.")

    # ==========================
    # 1. Manual Verification (15 pts)
    # ==========================
    if manual.get('info', {}).get('exists') and manual.get('info', {}).get('created_during_task'):
        score += 8
        content = manual.get('content', '').lower()
        if "fleet technical manual" in content:
            score += 4
            feedback.append("Manual: Header found.")
        else:
            feedback.append("Manual: Missing required header.")
            
        # Check for model summary or count keywords
        if "total" in content or "models" in content:
            score += 3
        else:
            feedback.append("Manual: Missing summary/count.")
    else:
        feedback.append("Manual: File not found or not created during task.")

    # ==========================
    # 2. CSV Verification (45 pts)
    # ==========================
    csv_valid = False
    csv_rows = []
    
    if csv_res.get('info', {}).get('exists') and csv_res.get('info', {}).get('created_during_task'):
        score += 8
        raw_csv = csv_res.get('content', '')
        
        try:
            # Parse CSV
            f_io = io.StringIO(raw_csv)
            reader = csv.reader(f_io)
            header = next(reader, [])
            
            # Check Header
            expected_header = ["ModelDirectory", "DisplayName", "MaxSpeed", "Length", "Beam", "Draft"]
            # Flexible match (remove spaces, lowercase)
            clean_header = [h.replace(" ", "").lower() for h in header]
            clean_expected = [h.replace(" ", "").lower() for h in expected_header]
            
            if clean_header == clean_expected:
                score += 5
                feedback.append("CSV: Header correct.")
            else:
                feedback.append(f"CSV: Header mismatch. Found: {header}")
                
            # Check Rows
            for row in reader:
                if any(row): csv_rows.append(row)
                
            if len(csv_rows) >= 8 or len(csv_rows) == total_models_available:
                score += 5
                feedback.append(f"CSV: {len(csv_rows)} entries found.")
            else:
                feedback.append(f"CSV: Insufficient entries ({len(csv_rows)}).")

            # Coverage Score (12 pts)
            # Match CSV model directories against Ground Truth keys
            matched_models = 0
            # Column 0 is ModelDirectory
            for row in csv_rows:
                if len(row) > 0 and row[0] in ground_truth:
                    matched_models += 1
            
            coverage_pct = matched_models / total_models_available if total_models_available > 0 else 0
            if coverage_pct >= 0.5:
                score += 12
                feedback.append(f"CSV: Coverage Good ({int(coverage_pct*100)}%)")
            elif coverage_pct > 0.1:
                score += 6
                feedback.append(f"CSV: Coverage Partial ({int(coverage_pct*100)}%)")
            
            # Accuracy Score (15 pts) - Random Spot Check
            # Check MaxSpeed (col 2) for first valid row
            accuracy_hits = 0
            checks_made = 0
            for row in csv_rows:
                if len(row) < 3: continue
                model_dir = row[0]
                if model_dir in ground_truth:
                    gt_speed = ground_truth[model_dir].get('max_speed', '0')
                    csv_speed = row[2]
                    # Simple equality check (allowing for string diffs if strictly numbers)
                    try:
                        if abs(float(gt_speed) - float(csv_speed)) < 0.5:
                            accuracy_hits += 1
                    except:
                        if gt_speed == csv_speed: accuracy_hits += 1
                    checks_made += 1
            
            if checks_made > 0 and (accuracy_hits / checks_made) > 0.8:
                score += 15
                feedback.append("CSV: Data Accuracy High.")
            elif checks_made > 0 and (accuracy_hits / checks_made) > 0.5:
                score += 7
                feedback.append("CSV: Data Accuracy Moderate.")
            
            csv_valid = True

        except Exception as e:
            feedback.append(f"CSV: Parsing failed: {e}")
    else:
        feedback.append("CSV: File not found.")

    # ==========================
    # 3. Scenario Verification (40 pts)
    # ==========================
    scen_info = scenario.get('info', {})
    
    # Directory exists (8 pts)
    if scen_info.get('exists'):
        score += 8
        feedback.append("Scenario: Directory exists.")
    else:
        feedback.append("Scenario: Directory missing.")

    # Environment (5 pts)
    env = scenario.get('environment', {})
    try:
        # 08:00 - 16:00
        start_time = float(env.get('start_time', -1))
        vis = float(env.get('visibility', 0))
        wea = float(env.get('weather', 99))
        
        if 8.0 <= start_time <= 16.0 and vis >= 10.0 and wea <= 2.0:
            score += 5
            feedback.append("Scenario: Environment config correct.")
        else:
            feedback.append("Scenario: Environment parameters out of spec.")
    except:
        pass

    # Ownship (5 pts)
    own = scenario.get('ownship', {})
    own_type = own.get('type', '')
    if own_type in ground_truth:
        score += 5
        feedback.append("Scenario: Ownship uses valid model.")
    else:
        feedback.append(f"Scenario: Ownship invalid type '{own_type}'.")

    # Othership (12 + 10 pts)
    other = scenario.get('othership', {})
    count = other.get('count', 0)
    types_str = other.get('types', '')
    types_list = [t.strip() for t in types_str.split(',') if t.strip()]
    
    # Check count (12 pts)
    if count >= 5:
        score += 12
        feedback.append("Scenario: Traffic count met (>=5).")
    elif count > 0:
        score += 5
        feedback.append(f"Scenario: Traffic count low ({count}).")
    
    # Check diversity and validity (10 pts)
    unique_types = set(types_list)
    valid_types = [t for t in unique_types if t in ground_truth]
    
    if len(valid_types) >= 5:
        score += 10
        feedback.append("Scenario: Traffic diversity excellent.")
    elif len(valid_types) >= 3:
        score += 5
        feedback.append("Scenario: Traffic diversity acceptable.")
    elif len(valid_types) > 0:
        feedback.append("Scenario: Traffic diversity low.")
    else:
        feedback.append("Scenario: Traffic uses invalid models.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }