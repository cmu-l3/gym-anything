#!/usr/bin/env python3
"""
Verifier for Evaluate Development Flood Risk task.
Compares agent's CSV output against ground truth calculated during setup.
"""

import json
import csv
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_risk_assessment(traj, env_info, task_info):
    """
    Verify the flood risk assessment task.
    
    Criteria:
    1. Output CSV exists and has correct columns (10 pts)
    2. Max WSE extraction is accurate (30 pts)
    3. Flood Depth calculation is correct (20 pts)
    4. Damage calculation logic is correct (30 pts)
    5. Summary text file matches CSV totals (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Files
    try:
        # Get result metadata
        temp_meta = tempfile.NamedTemporaryFile(delete=False).name
        copy_from_env("/tmp/task_result.json", temp_meta)
        with open(temp_meta) as f:
            meta = json.load(f)
        os.unlink(temp_meta)
        
        if not meta.get("csv_exists", False):
            return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
            
        # Get Agent CSV
        agent_csv_path = tempfile.NamedTemporaryFile(delete=False).name
        copy_from_env("/tmp/agent_output.csv", agent_csv_path)
        
        # Get Ground Truth CSV
        gt_csv_path = tempfile.NamedTemporaryFile(delete=False).name
        copy_from_env("/tmp/ground_truth_export.csv", gt_csv_path)
        
        # Get Summary Text
        summary_path = tempfile.NamedTemporaryFile(delete=False).name
        has_summary = meta.get("txt_exists", False)
        if has_summary:
            copy_from_env("/tmp/agent_summary.txt", summary_path)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error retrieving files: {str(e)}"}

    # 2. Parse CSVs
    try:
        with open(agent_csv_path, 'r') as f:
            agent_data = list(csv.DictReader(f))
            
        with open(gt_csv_path, 'r') as f:
            gt_data = list(csv.DictReader(f))
            
        # Index GT by Site_ID
        gt_map = {row['Site_ID']: row for row in gt_data}
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing CSV files: {str(e)}"}
    finally:
        if os.path.exists(agent_csv_path): os.unlink(agent_csv_path)
        if os.path.exists(gt_csv_path): os.unlink(gt_csv_path)

    # 3. Verify Columns (10 pts)
    required_cols = ['Site_ID', 'Max_WSE_ft', 'Flood_Depth_ft', 'Damage_USD']
    if not agent_data:
        return {"passed": False, "score": 0, "feedback": "Agent CSV is empty"}
        
    agent_cols = agent_data[0].keys()
    missing_cols = [c for c in required_cols if c not in agent_cols]
    
    if not missing_cols:
        score += 10
        feedback_parts.append("CSV format correct")
    else:
        feedback_parts.append(f"Missing columns: {', '.join(missing_cols)}")
        # Can't proceed safely if cols missing
        return {"passed": False, "score": score, "feedback": "; ".join(feedback_parts)}

    # 4. Data Verification
    total_sites = len(gt_data)
    wse_correct = 0
    depth_correct = 0
    damage_correct = 0
    
    agent_total_damage = 0
    
    for row in agent_data:
        site_id = row.get('Site_ID')
        if site_id not in gt_map:
            continue
            
        gt = gt_map[site_id]
        
        try:
            # Parse values
            a_wse = float(row.get('Max_WSE_ft', 0))
            a_depth = float(row.get('Flood_Depth_ft', 0))
            a_damage = float(str(row.get('Damage_USD', 0)).replace('$','').replace(',',''))
            
            gt_wse = float(gt['Max_WSE_ft'])
            gt_depth = float(gt['Flood_Depth_ft'])
            gt_damage = float(gt['Damage_USD'])
            
            agent_total_damage += a_damage
            
            # Check WSE (Tolerance 0.1 ft)
            if abs(a_wse - gt_wse) <= 0.1:
                wse_correct += 1
                
            # Check Depth (Tolerance 0.1 ft)
            if abs(a_depth - gt_depth) <= 0.1:
                depth_correct += 1
                
            # Check Damage (Tolerance 5% or $100)
            diff_damage = abs(a_damage - gt_damage)
            if diff_damage <= 100 or (gt_damage > 0 and diff_damage/gt_damage <= 0.05):
                damage_correct += 1
                
        except ValueError:
            pass

    # Score Calculation
    # Normalize to points
    wse_score = (wse_correct / total_sites) * 30
    depth_score = (depth_correct / total_sites) * 20
    damage_score = (damage_correct / total_sites) * 30
    
    score += wse_score + depth_score + damage_score
    
    feedback_parts.append(f"WSE Accuracy: {wse_correct}/{total_sites}")
    feedback_parts.append(f"Depth Calculation: {depth_correct}/{total_sites}")
    feedback_parts.append(f"Damage Logic: {damage_correct}/{total_sites}")

    # 5. Summary File Verification (10 pts)
    if has_summary:
        try:
            with open(summary_path, 'r') as f:
                content = f.read().lower()
            
            # Check for total damage number in text
            # We look for a number close to the agent's sum
            import re
            numbers = re.findall(r'[\d,]+', content)
            found_sum = False
            for num_str in numbers:
                try:
                    val = float(num_str.replace(',',''))
                    if abs(val - agent_total_damage) < 1000: # Loose check for summary
                        found_sum = True
                        break
                except:
                    continue
            
            if found_sum:
                score += 10
                feedback_parts.append("Summary text matches CSV total")
            else:
                feedback_parts.append("Summary total incorrect or not found")
        except:
            feedback_parts.append("Could not read summary file")
        finally:
            if os.path.exists(summary_path): os.unlink(summary_path)
    else:
        feedback_parts.append("Summary file missing")

    # Final check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }