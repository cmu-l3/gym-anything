#!/usr/bin/env python3
import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_hotel_rankings(traj, env_info, task_info):
    """
    Verifies:
    1. Schema: Hotels.ImpactScore exists (10 pts)
    2. Calculation: ImpactScore = (Stars*10) + (Stays*2) (50 pts)
    3. Coverage: Most hotels have scores (10 pts)
    4. Export: File exists, valid JSON, contains correct filtered data (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    score = 0
    feedback = []

    # --- Load Task Result (DB State) ---
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json", delete=True) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            tmp.seek(0)
            task_result = json.load(tmp)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # 1. Schema Verification (10 pts)
    if task_result.get('property_exists'):
        score += 10
        feedback.append("Schema updated correctly.")
    else:
        feedback.append("Missing 'ImpactScore' property on Hotels class.")

    # 2. Calculation Verification (50 pts)
    db_samples = task_result.get('db_sample', [])
    if not db_samples:
        feedback.append("No database records retrieved for verification.")
    else:
        correct_count = 0
        total_checked = 0
        for row in db_samples:
            stars = row.get('Stars')
            if stars is None: stars = 0
            
            edge_count = row.get('EdgeCount', 0)
            actual_score = row.get('ImpactScore')
            
            # Formula: (Stars * 10) + (EdgeCount * 2)
            expected_score = (stars * 10) + (edge_count * 2)
            
            if actual_score is not None:
                # Floating point tolerance
                if abs(float(actual_score) - float(expected_score)) < 0.1:
                    correct_count += 1
                total_checked += 1
        
        if total_checked > 0:
            accuracy = correct_count / total_checked
            if accuracy == 1.0:
                score += 50
                feedback.append("Score calculations are 100% correct.")
            elif accuracy > 0.8:
                score += 40
                feedback.append(f"Score calculations mostly correct ({int(accuracy*100)}%).")
            elif accuracy > 0.5:
                score += 20
                feedback.append(f"Score calculations partially correct ({int(accuracy*100)}%).")
            else:
                feedback.append(f"Score calculations incorrect (Acc: {int(accuracy*100)}%). Check formula.")
        else:
            feedback.append("Could not verify calculations (no data).")

    # 3. Coverage Verification (10 pts)
    null_count = task_result.get('null_score_count', -1)
    if null_count == 0:
        score += 10
        feedback.append("All records updated.")
    elif null_count > 0:
        feedback.append(f"Some records ({null_count}) have NULL scores.")
    
    # 4. Export File Verification (30 pts)
    # Check if output file was created
    if task_result.get('output_exists') and task_result.get('file_created_during_task'):
        # Load the exported file
        export_data = []
        with tempfile.NamedTemporaryFile(suffix=".json", delete=True) as tmp_exp:
            try:
                copy_from_env("/home/ga/top_tier_hotels.json", tmp_exp.name)
                tmp_exp.seek(0)
                file_content = tmp_exp.read().decode('utf-8', errors='ignore')
                if not file_content.strip():
                     feedback.append("Export file is empty.")
                else:
                    try:
                        # try loading as json
                        tmp_exp.seek(0)
                        export_data = json.load(tmp_exp)
                        score += 10 # File exists and is valid JSON
                        
                        # Verify Logic (> 60)
                        if isinstance(export_data, list) and len(export_data) > 0:
                            logic_fail = False
                            keys_fail = False
                            for item in export_data:
                                if not isinstance(item, dict): continue
                                
                                # Check logic
                                item_score = item.get('ImpactScore')
                                if item_score is None or float(item_score) <= 60:
                                    logic_fail = True
                                
                                # Check keys
                                if 'Name' not in item or 'Stars' not in item:
                                    keys_fail = True

                            if not logic_fail:
                                score += 20
                                feedback.append("Export filtering (>60) correct.")
                            else:
                                score += 5
                                feedback.append("Export file contains records with Score <= 60.")
                                
                            if keys_fail:
                                feedback.append("Exported records missing required fields (Name, Stars).")
                        else:
                            feedback.append("Export JSON is not a list or is empty.")

                    except json.JSONDecodeError:
                        feedback.append("Export file is not valid JSON.")
            except Exception as e:
                feedback.append("Failed to read export file.")
    else:
        feedback.append("Export file was not created.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }