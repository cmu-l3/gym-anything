#!/usr/bin/env python3
"""
Verifier for calculate_distance_to_river task.
Checks if the output shapefile exists, has a new distance field, and values are plausible.
"""

import json
import os
import sys
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_calculate_distance_to_river(traj, env_info, task_info):
    """
    Verify the distance calculation task.
    
    Criteria:
    1. Output DBF file exists and was created during the task.
    2. Output has more fields than the input (indicating a new distance column).
    3. Output feature count matches input (approx 243 cities).
    4. Distance values are plausible (e.g. Cairo ~0, Riyadh > 0).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    check_cities = metadata.get('check_cities', {})

    # Install pyshp if needed (lightweight pure python)
    try:
        import shapefile
    except ImportError:
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pyshp"])
        import shapefile

    # Load result JSON
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

    # Basic checks
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output shapefile not found at expected path."}
    
    if not result.get('file_created_during_task', False):
        return {"passed": False, "score": 20, "feedback": "Output file exists but was not created during this task execution."}

    # Load DBF for attribute analysis
    temp_dbf = tempfile.NamedTemporaryFile(delete=False, suffix='.dbf')
    try:
        copy_from_env("/tmp/result_shapefile.dbf", temp_dbf.name)
        sf = shapefile.Reader(dbf=temp_dbf.name)
        
        fields = [f[0] for f in sf.fields[1:]] # Skip deletion flag
        records = sf.records()
        
        logger.info(f"Fields found: {fields}")
        logger.info(f"Record count: {len(records)}")
        
        score = 30  # Base score for valid file
        feedback = ["File created successfully."]

        # Check 1: Feature count (Natural Earth cities is usually ~243)
        if len(records) > 200:
            score += 10
            feedback.append(f"Feature count correct ({len(records)}).")
        else:
            feedback.append(f"Warning: Low feature count ({len(records)}).")

        # Check 2: Identify Distance Field
        # Common names: DIST, DISTANCE, Dist, Value, Length
        dist_field_index = -1
        dist_field_name = ""
        
        # Original NE fields usually: SCALERANK, NATSCALE, LABELRANK, NAME, ...
        # We look for a numeric field that might be the distance
        candidate_fields = []
        for i, field_def in enumerate(sf.fields[1:]):
            f_name = field_def[0]
            f_type = field_def[1]
            # N = Numeric, F = Float
            if f_type in ['N', 'F']:
                candidate_fields.append((f_name, i))
                
        # Heuristic: Find a field named like DIST
        for name, idx in candidate_fields:
            if "DIST" in name.upper() or "LENGTH" in name.upper() or "VAL" in name.upper():
                dist_field_index = idx
                dist_field_name = name
                break
        
        # If no obvious name, take the last numeric field added (often appended to end)
        if dist_field_index == -1 and candidate_fields:
             # Assume the last numeric field is the new one
             dist_field_name, dist_field_index = candidate_fields[-1]

        if dist_field_index != -1:
            score += 20
            feedback.append(f"Identified potential distance field: '{dist_field_name}'.")
            
            # Check 3: Value Plausibility
            # Find specific cities to check
            name_field_idx = -1
            for i, f in enumerate(fields):
                if f.upper() == "NAME":
                    name_field_idx = i
                    break
            
            if name_field_idx != -1:
                city_dists = {}
                for r in records:
                    try:
                        city_name = r[name_field_idx]
                        # Handle byte strings if necessary
                        if isinstance(city_name, bytes):
                            city_name = city_name.decode('utf-8', errors='ignore')
                        
                        dist_val = r[dist_field_index]
                        city_dists[city_name] = dist_val
                    except Exception:
                        continue

                # Verify logic
                correct_logic = 0
                checks_made = 0
                
                # Check specific cities defined in metadata
                for city, criteria in check_cities.items():
                    if city in city_dists:
                        val = city_dists[city]
                        checks_made += 1
                        passed_check = True
                        
                        if "max_dist" in criteria and val > criteria["max_dist"]:
                            passed_check = False
                            feedback.append(f"{city} distance too high ({val} > {criteria['max_dist']}).")
                        
                        if "min_dist" in criteria and val < criteria["min_dist"]:
                            passed_check = False
                            feedback.append(f"{city} distance too low ({val} < {criteria['min_dist']}).")
                            
                        if passed_check:
                            correct_logic += 1
                    else:
                        feedback.append(f"City '{city}' not found in output.")

                if checks_made > 0:
                    accuracy_score = (correct_logic / checks_made) * 40
                    score += accuracy_score
                    if accuracy_score == 40:
                        feedback.append("Distance values match expected geography.")
                else:
                    # If we couldn't match names, check if values look like degrees (0-180 range, mostly small)
                    vals = [r[dist_field_index] for r in records if isinstance(r[dist_field_index], (int, float))]
                    if vals:
                        avg = sum(vals)/len(vals)
                        if 0 < avg < 50:
                            score += 20  # Fallback points for plausible range
                            feedback.append(f"Distance values look plausible (Avg: {avg:.2f}).")
                        else:
                            feedback.append(f"Distance values suspicious (Avg: {avg:.2f}).")
            else:
                feedback.append("NAME field not found, skipping specific city checks.")
                score += 10 # Partial credit
        else:
            feedback.append("Could not identify a distance field in the output.")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error analyzing shapefile: {e}"}
    finally:
        if os.path.exists(temp_dbf.name):
            os.unlink(temp_dbf.name)

    passed = score >= 75
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }