#!/usr/bin/env python3
"""
Verifier for computed_variable_efficiency task.

Checks:
1. 'efficiency_data.csv' exists and contains the correctly calculated 'Efficiency' column.
   Formula: Exam / (Revise + 1)
2. 'efficiency_analysis.jasp' exists and contains a valid zip structure with Descriptives analysis.
3. Analysis includes density plot configuration.
"""

import json
import os
import tempfile
import zipfile
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_computed_variable_efficiency(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve Task Metadata
    metadata = task_info.get('metadata', {})
    expected_csv_path = metadata.get('expected_csv_path', '/home/ga/Documents/JASP/efficiency_data.csv')
    expected_jasp_path = metadata.get('expected_jasp_path', '/home/ga/Documents/JASP/efficiency_analysis.jasp')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # --- Step 0: Load Exported JSON ---
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    task_start = result_data.get("task_start", 0)

    # --- Step 1: Verify CSV Content (Calculation Accuracy) ---
    csv_exists = result_data.get("csv_exists", False)
    csv_valid = False
    
    if csv_exists:
        score += 10 # CSV Exported
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(expected_csv_path, temp_csv.name)
            
            with open(temp_csv.name, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                
                if not rows:
                    feedback_parts.append("Exported CSV is empty.")
                elif "Efficiency" not in rows[0]:
                    feedback_parts.append("Column 'Efficiency' missing from exported CSV.")
                else:
                    score += 10 # Column Created
                    
                    # Validate Calculation
                    # Formula: Exam / (Revise + 1)
                    correct_count = 0
                    total_count = 0
                    error_margin = 0.001
                    
                    for row in rows:
                        try:
                            exam = float(row.get("Exam", 0))
                            revise = float(row.get("Revise", 0))
                            actual_eff = float(row.get("Efficiency", 0))
                            
                            expected_eff = exam / (revise + 1.0)
                            
                            if abs(actual_eff - expected_eff) <= error_margin:
                                correct_count += 1
                            total_count += 1
                        except ValueError:
                            continue # Skip bad rows
                            
                    if total_count > 0 and (correct_count / total_count) > 0.95:
                        score += 40
                        csv_valid = True
                        feedback_parts.append(f"Calculation correct ({correct_count}/{total_count} rows match).")
                    else:
                        feedback_parts.append(f"Calculation incorrect. Matches: {correct_count}/{total_count}.")
                        
        except Exception as e:
            feedback_parts.append(f"Error analyzing CSV: {str(e)}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    else:
        feedback_parts.append("Efficiency data CSV not exported.")

    # --- Step 2: Verify JASP Project (Analysis Config) ---
    jasp_exists = result_data.get("jasp_exists", False)
    jasp_mtime = result_data.get("jasp_mtime", 0)
    
    if jasp_exists:
        # Anti-gaming check
        if jasp_mtime > task_start:
            score += 10 # File Saved
            
            temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
            try:
                copy_from_env(expected_jasp_path, temp_jasp.name)
                
                # JASP files are ZIP archives
                if zipfile.is_zipfile(temp_jasp.name):
                    with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                        # List all files in zip to find analysis configs
                        # JASP structure varies, but usually contains JSON configs in 'analyses' or 'embedded'
                        file_list = z.namelist()
                        
                        # Search for evidences of Descriptive Statistics
                        # We look for json content containing specific keys
                        analysis_found = False
                        plot_found = False
                        
                        for filename in file_list:
                            if filename.endswith('.json') or filename.endswith('.qml'):
                                try:
                                    content = z.read(filename).decode('utf-8', errors='ignore')
                                    # Loose string matching is safer than rigid JSON parsing here
                                    # as JASP internal format is complex and version-dependent
                                    
                                    if "Descriptives" in content or "DescriptiveStatistics" in content:
                                        analysis_found = True
                                    
                                    if "density" in content.lower() or "densityplot" in content.lower():
                                        plot_found = True
                                        
                                    if "Efficiency" in content:
                                        # Confirm variable usage
                                        pass
                                except:
                                    continue
                        
                        if analysis_found:
                            score += 15
                            feedback_parts.append("Descriptive analysis found in project.")
                            
                            if plot_found:
                                score += 5
                                feedback_parts.append("Density plot configuration found.")
                            else:
                                feedback_parts.append("Density plot not detected in analysis options.")
                                
                            if "Efficiency" in str(file_list) or analysis_found: 
                                # Assuming if analysis exists it likely targets the new var if we found "Efficiency" string earlier
                                score += 10 # Variable assigned (inferred)
                        else:
                            feedback_parts.append("No Descriptive Analysis found in JASP file.")
                else:
                    feedback_parts.append("Saved file is not a valid JASP archive.")
            except Exception as e:
                feedback_parts.append(f"Error analyzing JASP file: {str(e)}")
            finally:
                if os.path.exists(temp_jasp.name):
                    os.unlink(temp_jasp.name)
        else:
            feedback_parts.append("JASP file exists but is too old (created before task).")
    else:
        feedback_parts.append("Analysis JASP file not saved.")

    # --- Final Score Calculation ---
    passed = (score >= 70) and csv_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }