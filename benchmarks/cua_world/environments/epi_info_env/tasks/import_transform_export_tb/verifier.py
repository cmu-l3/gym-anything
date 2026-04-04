#!/usr/bin/env python3
"""
Verifier for import_transform_export_tb task.

Verifies:
1. Output CSV exists and was created during task.
2. Correct columns were created (TotalCases, IncidenceRate, IncidenceTier).
3. Logic for calculations is correct.
4. Filtering is correct (AFR region, 2015-2020).
5. VLM verification of UI interaction.
"""

import json
import os
import io
import csv
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_transform_export_tb(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Basic File Checks (30 points)
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
    
    score += 10
    feedback.append("Output file created.")

    if result.get('file_created_during_task'):
        score += 20
        feedback.append("File created during task window.")
    else:
        feedback.append("WARNING: File timestamp check failed (pre-existing?).")

    # 3. Content Verification (50 points)
    csv_content = result.get('csv_content', "")
    ground_truth_count = result.get('ground_truth_count', 0)
    
    if not csv_content:
        return {"passed": False, "score": score, "feedback": "Output file is empty."}

    try:
        # Parse CSV
        f = io.StringIO(csv_content)
        reader = csv.DictReader(f)
        rows = list(reader)
        
        # Check Columns
        required_cols = ["TotalCases", "IncidenceRate", "IncidenceTier", "who_region", "year"]
        missing_cols = [c for c in required_cols if c not in reader.fieldnames]
        
        if not missing_cols:
            score += 10
            feedback.append("All required columns present.")
        else:
            feedback.append(f"Missing columns: {', '.join(missing_cols)}")

        # Check Filter Logic (AFR + Year)
        filter_errors = 0
        row_count = len(rows)
        
        for row in rows:
            if row['who_region'] != "AFR":
                filter_errors += 1
            try:
                yr = int(row['year'])
                if yr < 2015 or yr > 2020:
                    filter_errors += 1
            except:
                filter_errors += 1
        
        if row_count == 0:
            feedback.append("Output contains 0 rows.")
        elif filter_errors == 0:
            score += 15
            feedback.append("Filtering (AFR, 2015-2020) correct.")
        else:
            feedback.append(f"Filtering incorrect: {filter_errors} invalid rows found.")

        # Check Row Count against Ground Truth
        # Allow +/- 1 discrepancy
        if row_count > 0 and abs(row_count - ground_truth_count) <= 1:
            score += 10
            feedback.append(f"Row count ({row_count}) matches expected.")
        elif row_count > 0:
            feedback.append(f"Row count ({row_count}) mismatch (expected approx {ground_truth_count}).")

        # Check Calculations (Spot check)
        calc_correct = 0
        calc_checked = 0
        tier_correct = 0
        
        for row in rows[:20]: # Check first 20
            try:
                # Parse
                new = float(row['tb_cases_new'])
                rel = float(row['tb_cases_relapse'])
                pop = float(row['population'])
                
                # Check Total
                total = float(row['TotalCases'])
                if abs(total - (new + rel)) < 1.0:
                    
                    # Check Rate
                    rate = float(row['IncidenceRate'])
                    expected_rate = (total / pop) * 100000
                    if abs(rate - expected_rate) < 1.0:
                        calc_correct += 1
                        
                        # Check Tier
                        tier = row['IncidenceTier']
                        expected_tier = "Very High"
                        if rate < 50: expected_tier = "Low"
                        elif rate < 150: expected_tier = "Medium"
                        elif rate < 300: expected_tier = "High"
                        
                        if tier == expected_tier:
                            tier_correct += 1
                calc_checked += 1
            except:
                pass
        
        if calc_checked > 0 and calc_correct == calc_checked:
            score += 10
            feedback.append("Calculations (Total & Rate) correct.")
        
        if calc_checked > 0 and tier_correct == calc_checked:
            score += 5
            feedback.append("Recoding (Tier) correct.")

    except Exception as e:
        feedback.append(f"Error parsing CSV content: {e}")

    # 4. VLM Verification (20 points)
    # Check trajectory for Epi Info usage
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user working in Epi Info 7.
    Did the user:
    1. Open the "Classic Analysis" module (looks like a command console)?
    2. Execute commands like READ/IMPORT, DEFINE, RECODE, or SELECT?
    3. Export data (WRITE command)?
    
    Answer JSON: {"commands_visible": bool, "classic_analysis_used": bool}
    """
    
    try:
        vlm_res = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)
        parsed = vlm_res.get('parsed', {})
        if parsed.get('classic_analysis_used', False):
            score += 20
            feedback.append("VLM confirmed usage of Classic Analysis.")
    except:
        # Fallback if VLM fails but data is perfect
        if score >= 80:
            score += 20
            feedback.append("VLM skipped, assuming success based on perfect data.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }