#!/usr/bin/env python3
"""
Verifier for neural_network_abalone task.

Verifies:
1. JASP project file exists and is a valid zip.
2. Neural Network analysis is configured correctly (Target, Seed, Architecture).
3. Performance text file exists and contains a number.
"""

import json
import os
import zipfile
import tempfile
import shutil
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_neural_network_abalone(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Check Text File (10 points)
    txt_exists = result.get('txt_file_exists', False)
    txt_content = result.get('txt_content', "").strip()
    
    if txt_exists:
        score += 5
        # Check if content looks like a number (MSE)
        if re.search(r'\d+(\.\d+)?', txt_content):
            score += 5
            feedback.append(f"Performance report found: {txt_content}")
        else:
            feedback.append("Performance report exists but doesn't contain a valid number.")
    else:
        feedback.append("Performance report file missing.")

    # 2. Check JASP File Existence (10 points)
    jasp_exists = result.get('jasp_file_exists', False)
    if not jasp_exists:
        return {"passed": False, "score": score, "feedback": "JASP project file not found. " + " ".join(feedback)}
    
    score += 10
    feedback.append("JASP project file exists.")

    # 3. Analyze JASP File Content (80 points)
    # Copy JASP file out
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    temp_extract_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env(result['jasp_file_path'], temp_jasp.name)
        
        if not zipfile.is_zipfile(temp_jasp.name):
            return {"passed": False, "score": score, "feedback": "Saved file is not a valid JASP archive."}

        with zipfile.ZipFile(temp_jasp.name, 'r') as z:
            z.extractall(temp_extract_dir)
            
        # Search for analysis definition
        # JASP structure varies, but usually embedded in JSONs inside the archive
        analysis_found = False
        correct_analysis_type = False
        seed_correct = False
        architecture_correct = False
        target_correct = False
        
        # Walk through extracted files to find JSONs containing analysis info
        for root, dirs, files in os.walk(temp_extract_dir):
            for file in files:
                if file.endswith('.json'):
                    try:
                        with open(os.path.join(root, file), 'r') as f:
                            data = json.load(f)
                            
                        # Look for "results" or "analyses" list
                        # Structure typically: {"results": [{"title": "Neural Network Regression", ...}]}
                        # Or internal JASP state representation
                        
                        # Recursive search helper
                        def find_key(obj, key):
                            if isinstance(obj, dict):
                                if key in obj: return obj[key]
                                for k, v in obj.items():
                                    res = find_key(v, key)
                                    if res: return res
                            elif isinstance(obj, list):
                                for item in obj:
                                    res = find_key(item, key)
                                    if res: return res
                            return None

                        # Check if this JSON describes the analysis
                        # Note: This is heuristic based on common JASP serialization
                        json_str = json.dumps(data)
                        
                        if "Neural Network Regression" in json_str or "RegressionNeuralNetwork" in json_str:
                            analysis_found = True
                            correct_analysis_type = True
                            
                            # Check Seed (123)
                            # Key might be "seed" or "setSeed"
                            if '"seed": 123' in json_str or '"seed":123' in json_str:
                                seed_correct = True
                            
                            # Check Target ("Rings")
                            if "Rings" in json_str:
                                target_correct = True
                                
                            # Check Architecture (8 and 4)
                            # Config might look like "hiddenUnits": [8, 4] or similar
                            # We'll look for the numbers in context
                            if '"value": 8' in json_str and '"value": 4' in json_str:
                                # Loose check, but plausible in context of this specific file
                                architecture_correct = True
                            elif '[8, 4]' in json_str or '[8,4]' in json_str:
                                architecture_correct = True
                                
                    except:
                        continue
                        
        if correct_analysis_type:
            score += 20
            feedback.append("Neural Network Regression analysis found.")
        else:
            feedback.append("Could not confirm Neural Network analysis type.")
            
        if target_correct:
            score += 20
            feedback.append("Target variable 'Rings' found in analysis.")
        else:
            feedback.append("Target variable configuration not verified.")

        if seed_correct:
            score += 20
            feedback.append("Random seed 123 verified.")
        else:
            feedback.append("Random seed 123 not found in configuration.")

        if architecture_correct:
            score += 20
            feedback.append("Hidden layer architecture (8, 4) verified.")
        else:
            feedback.append("Hidden layer architecture (8, 4) not confirmed.")

    except Exception as e:
        feedback.append(f"Error analyzing JASP file: {str(e)}")
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)
        if os.path.exists(temp_extract_dir):
            shutil.rmtree(temp_extract_dir)

    passed = score >= 70 and correct_analysis_type and seed_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }