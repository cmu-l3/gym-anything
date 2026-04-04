#!/usr/bin/env python3
"""
Verifier for QGIS Model Automation Task.
Verifies:
1. QGIS processing model (.model3) structure (inputs, buffer, intersection).
2. Output GeoJSON validity and content.
"""

import json
import os
import gzip
import shutil
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_airport_proximity_modeler_automation(traj, env_info, task_info):
    """
    Verify the agent created a correct QGIS model and generated the output.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- CRITERION 1: Model File Existence (10 pts) ---
    if result.get("model_exists") and result.get("model_created_during_task"):
        score += 10
        feedback.append("Model file created.")
        
        # --- CRITERION 2: Model Structure Analysis (40 pts) ---
        # Retrieve the model file
        temp_model = tempfile.NamedTemporaryFile(delete=False, suffix='.model3')
        try:
            copy_from_env("/tmp/submitted_model.model3", temp_model.name)
            
            # .model3 files are typically GZIP compressed JSON in QGIS 3
            model_json = None
            try:
                with gzip.open(temp_model.name, 'rb') as f_in:
                    content = f_in.read()
                    model_json = json.loads(content.decode('utf-8'))
            except Exception:
                # Fallback: try reading as plain text
                try:
                    with open(temp_model.name, 'r') as f_in:
                        model_json = json.load(f_in)
                except Exception as e:
                    feedback.append(f"Could not parse model file (invalid format?): {str(e)}")

            if model_json:
                # Analyze algorithms
                algos = model_json.get('values', {}).get('algorithms', {})
                
                has_buffer = False
                buffer_dist_correct = False
                has_overlay = False
                
                for algo in algos.values():
                    algo_id = algo.get('algorithm', {}).get('modelId', '')
                    # Depending on version, might be under 'name' or 'algorithm_id'
                    # More robust check:
                    comp_id = algo.get('algorithm', {}).get('component', '')
                    
                    # Check Buffer
                    if 'native:buffer' in comp_id or 'native:buffer' in str(algo):
                        has_buffer = True
                        # Check params
                        params = algo.get('params', {})
                        # Distance might be a fixed value or input
                        # Looking for 'DISTANCE': 0.05
                        # Parameter structure varies by QGIS version, scanning raw dict often safer
                        if str(params).find('0.05') != -1:
                            buffer_dist_correct = True
                    
                    # Check Intersection or Clip
                    if 'native:intersection' in comp_id or 'native:clip' in comp_id or \
                       'native:intersection' in str(algo) or 'native:clip' in str(algo):
                        has_overlay = True

                if has_buffer:
                    score += 15
                    feedback.append("Model contains Buffer algorithm.")
                else:
                    feedback.append("Model missing Buffer algorithm.")

                if has_overlay:
                    score += 15
                    feedback.append("Model contains Intersection/Clip algorithm.")
                else:
                    feedback.append("Model missing Intersection/Clip algorithm.")
                
                if buffer_dist_correct:
                    score += 10
                    feedback.append("Buffer distance set to 0.05.")
                else:
                    feedback.append("Buffer distance incorrect or not found (expected 0.05).")

        except Exception as e:
            feedback.append(f"Error analyzing model file: {str(e)}")
        finally:
            if os.path.exists(temp_model.name):
                os.unlink(temp_model.name)
    else:
        feedback.append("Model file not found or not created during task.")

    # --- CRITERION 3: Output File Verification (50 pts) ---
    if result.get("output_exists") and result.get("output_created_during_task"):
        score += 10
        feedback.append("Output GeoJSON created.")
        
        if result.get("is_valid_geojson"):
            score += 10
            feedback.append("Output is valid GeoJSON.")
            
            # Check content
            feat_count = result.get("feature_count", 0)
            if feat_count > 0:
                # A reasonable intersection of global airports (buffer 0.05) and urban areas
                # should produce some features. Exact count varies by data version, 
                # but > 0 is a good sanity check.
                score += 30
                feedback.append(f"Output contains {feat_count} features (valid content).")
            else:
                feedback.append("Output is empty (0 features). Expected intersecting areas.")
        else:
            feedback.append("Output is not valid GeoJSON.")
    else:
        feedback.append("Output GeoJSON not found or not created during task.")

    passed = (score >= 65)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }