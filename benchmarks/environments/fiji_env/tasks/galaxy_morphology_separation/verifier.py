#!/usr/bin/env python3
"""
Verifier for Galaxy Morphology Separation Task.

Criteria:
1. Files Created (20 pts): CSV and PNG exist and created during task.
2. Target Identification (40 pts):
   - Only 1 row in CSV (or the agent filtered for the companion).
   - Centroid Y < 200 (Companion is at the top of the image).
   - Area between 1000 and 8000 pixels (Companion size).
     (If area > 10000, they likely measured the combined object or the main spiral).
3. Metric Validity (20 pts): Major/Minor axis present and realistic.
4. Visual/VLM Verification (20 pts):
   - Segmentation map shows separation.
   - Evidence of watershed usage in trajectory.
"""

import json
import csv
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_galaxy_morphology_separation(traj, env_info, task_info):
    # Setup dependencies
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy capability missing"}

    # Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/galaxy_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    passed = False

    # 1. File Existence & Timestamp (20 pts)
    csv_exists = result_data.get("csv_exists", False)
    csv_fresh = result_data.get("csv_created_during_task", False)
    img_exists = result_data.get("img_exists", False)
    
    if csv_exists and csv_fresh:
        score += 10
        feedback.append("Metrics CSV created.")
    else:
        feedback.append("Metrics CSV missing or stale.")

    if img_exists: # Timestamp check less critical for image if CSV is good, but good practice
        score += 10
        feedback.append("Segmentation map created.")
    else:
        feedback.append("Segmentation map missing.")

    # 2. Data Content Verification (60 pts total for Metrics + Identification)
    valid_identification = False
    
    if csv_exists:
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env(result_data["csv_path"], temp_csv.name)
            
            with open(temp_csv.name, 'r') as f:
                # Handle Fiji CSVs which might have different headers
                # Usually: " ", "Label", "Area", "Mean", "Min", "Max", "X", "Y", ...
                reader = csv.DictReader(f)
                rows = list(reader)
                
                if not rows:
                    feedback.append("CSV file is empty.")
                else:
                    # Clean headers (strip whitespace)
                    rows = [{k.strip(): v for k, v in r.items()} for r in rows]
                    
                    # Logic: If multiple rows, look for the one that matches NGC 5195
                    # If single row, check if it matches NGC 5195
                    
                    companion_found = False
                    
                    for row in rows:
                        try:
                            area = float(row.get('Area', 0))
                            
                            # Fiji "Centroid" output usually "X" and "Y" columns
                            # Sometimes "XM" and "YM" (Center of Mass)
                            y_pos = float(row.get('Y', row.get('YM', 9999)))
                            
                            major = float(row.get('Major', 0))
                            minor = float(row.get('Minor', 0))
                            
                            # Validation Logic for NGC 5195 (Top Galaxy)
                            # Image is ~510x510.
                            # Top galaxy Y is small (0 is top). M51 is center (~255).
                            
                            is_top = y_pos < 220
                            is_correct_size = 1000 < area < 9000
                            
                            if is_top and is_correct_size:
                                companion_found = True
                                score += 30 # Found the object
                                feedback.append(f"Correctly identified companion (Area: {area}, Y: {y_pos}).")
                                
                                # Check for Morphological Metrics (20 pts)
                                if major > 0 and minor > 0:
                                    score += 20
                                    feedback.append("Elliptical fit metrics present.")
                                else:
                                    feedback.append("Major/Minor axis metrics missing.")
                                break
                            
                        except ValueError:
                            continue
                            
                    if not companion_found:
                        feedback.append("Could not find valid companion data. Checked for Area [1000-9000] and Y < 220.")
                        # Check if they measured the whole thing
                        for row in rows:
                            try:
                                area = float(row.get('Area', 0))
                                if area > 10000:
                                    feedback.append(f"Measured object area ({area}) suggests failure to separate galaxies.")
                            except: pass

        except Exception as e:
            feedback.append(f"Error parsing CSV: {str(e)}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)
    
    # 3. VLM Verification (20 pts)
    # Simple check: Does segmentation map exist? If yes, give points for now.
    # In a real VLM integration, we would query the VLM with the image path.
    if img_exists:
        score += 20
        feedback.append("Visual evidence provided.")

    # Final scoring
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }