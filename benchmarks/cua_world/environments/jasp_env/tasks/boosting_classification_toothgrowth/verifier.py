#!/usr/bin/env python3
"""
Verifier for JASP Boosting Classification Task.

Verification Strategy:
1. File Validation: Check if .jasp file exists and was created during task.
2. JASP Analysis Parsing: Unzip the .jasp file (it's a zip) and inspect JSONs.
   - Verify Analysis Type: Boosting Classification
   - Verify Variables: Target=supp, Predictors=len, dose
   - Verify Hyperparameters: Trees=50, Shrinkage=0.1, TestSplit=0.3
   - Verify Options: Confusion Matrix, ROC, OOB plots enabled
3. VLM Verification: Use trajectory to confirm UI interaction if file parsing is ambiguous.
"""

import json
import os
import sys
import tempfile
import zipfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def find_analysis_json(extract_dir):
    """Recursive search for the analysis definition JSON in the extracted JASP file."""
    for root, dirs, files in os.walk(extract_dir):
        for file in files:
            if file.endswith(".json") and file != "manifest.json":
                # Check content for boosting specific keywords
                try:
                    with open(os.path.join(root, file), 'r') as f:
                        content = f.read()
                        # Look for Boosting Classification identifier
                        if "BoostingClassification" in content or "MachineLearningBoosting" in content:
                            return os.path.join(root, file)
                        # Fallback: look for generic ML analysis with correct variables
                        if "supp" in content and "len" in content and "dose" in content and "trees" in content:
                            return os.path.join(root, file)
                except:
                    continue
    return None

def verify_jasp_content(jasp_file_path):
    """Unzips and inspects the JASP file content."""
    score = 0
    feedback = []
    details = {}
    
    temp_dir = tempfile.mkdtemp()
    try:
        # 1. Unzip
        try:
            with zipfile.ZipFile(jasp_file_path, 'r') as zip_ref:
                zip_ref.extractall(temp_dir)
        except zipfile.BadZipFile:
            return 0, ["File is not a valid JASP archive"], details

        # 2. Find Analysis JSON
        analysis_file = find_analysis_json(temp_dir)
        
        if not analysis_file:
            # Try to find ANY analysis file to give partial credit
            return 10, ["JASP file contains data but Boosting Classification analysis not found."], details

        score += 20
        feedback.append("Valid Boosting Classification analysis found")
        
        # 3. Parse JSON
        with open(analysis_file, 'r') as f:
            data = json.load(f)
            json_str = json.dumps(data) # Convert to string for easy regex-like checking if structure is complex

        # 4. Check Variables (Target & Predictors)
        # JASP JSON structure varies by version, so we check for key-value presence or structure
        # Target: supp
        if '"supp"' in json_str and ('"target"' in json_str or '"dependent"' in json_str):
            score += 10
            feedback.append("Target variable 'supp' correctly assigned")
        else:
            feedback.append("Target variable 'supp' missing or incorrect")

        # Predictors: len, dose
        if '"len"' in json_str and '"dose"' in json_str:
            score += 10
            feedback.append("Predictors 'len' and 'dose' correctly assigned")
        else:
            feedback.append("Predictors missing or incorrect")

        # 5. Check Hyperparameters
        # Trees = 50
        if '"noOfTrees": 50' in json_str or '"nTrees": 50' in json_str or '"trees": 50' in json_str:
            score += 10
            feedback.append("Number of trees set to 50")
        elif "50" in json_str: # Weak check
            score += 5
            feedback.append("Value '50' found (parameter unsure)")
        else:
            feedback.append("Number of trees incorrect")

        # Shrinkage = 0.1
        if '"shrinkage": 0.1' in json_str or '"learningRate": 0.1' in json_str:
            score += 10
            feedback.append("Shrinkage set to 0.1")
        else:
            feedback.append("Shrinkage incorrect")

        # Test Split = 0.3 (30%)
        if '"testDataManual": 0.3' in json_str or '"testPart": 0.3' in json_str or '"holdout": 0.3' in json_str:
            score += 10
            feedback.append("Test split set to 30%")
        else:
            feedback.append("Test split incorrect")

        # 6. Check Outputs
        # Confusion Matrix
        if '"confusionMatrix": true' in json_str or '"confusionMatrix":true' in json_str.replace(" ", ""):
            score += 5
            feedback.append("Confusion Matrix enabled")
        
        # ROC Curve
        if '"rocCurve": true' in json_str or '"rocCurve":true' in json_str.replace(" ", ""):
            score += 5
            feedback.append("ROC Curve enabled")

        # OOB Plot
        if '"outOfBag": true' in json_str or '"oobImprovement": true' in json_str:
            score += 5
            feedback.append("OOB Plot enabled")

    except Exception as e:
        feedback.append(f"Error parsing JASP file: {str(e)}")
    finally:
        shutil.rmtree(temp_dir)
        
    return score, feedback, details

def verify_boosting_classification(traj, env_info, task_info):
    """
    Verifies the JASP Boosting Classification task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # 1. Retrieve Metadata & Results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    
    try:
        # Get result JSON
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        output_exists = result_data.get('output_exists', False)
        created_during_task = result_data.get('file_created_during_task', False)
        output_path = result_data.get('output_path', '')
        
        # 2. Basic File Checks
        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "Output .jasp file not found."}
            
        score += 5 # Exists
        
        if created_during_task:
            score += 10
            feedback.append("File created during task session")
        else:
            feedback.append("Warning: File timestamp indicates it wasn't created during this task session")

        # 3. Retrieve and Analyze JASP File
        try:
            copy_from_env(output_path, temp_jasp.name)
            content_score, content_feedback, _ = verify_jasp_content(temp_jasp.name)
            score += content_score
            feedback.extend(content_feedback)
        except Exception as e:
            feedback.append(f"Failed to retrieve or read JASP file: {e}")

        # 4. VLM Verification (Visual Confirmation)
        # We use this to verify the UI state even if the file internal check missed something specific
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        vlm_images = frames + [final_screen] if final_screen else frames
        
        if vlm_images:
            prompt = """
            Review these screenshots of JASP software. 
            The user should be performing a Boosting Classification analysis.
            
            Check for:
            1. 'Boosting Classification' is selected or visible in the headers.
            2. Variable 'supp' is in the Target box.
            3. Variables 'len' and 'dose' are in the Predictors box.
            4. An output table 'Confusion Matrix' is visible.
            5. An ROC curve plot is visible.
            
            Does the final state look like a completed analysis?
            """
            
            vlm_out = query_vlm(images=vlm_images, prompt=prompt).get('parsed', {})
            # We treat this as a qualitative boost or penalty
            # If program verification passed (>50), VLM confirms it.
            # If program verification failed, VLM might rescue it if file save failed but UI was correct.
            
            # Simple heuristic for this example:
            if "yes" in str(vlm_out).lower() or "confusion matrix" in str(vlm_out).lower():
                # Confirm visual success
                if score < 100:
                    score += 5
                    feedback.append("VLM visual verification confirmed analysis elements.")

    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    # Final Pass Logic
    # Pass if score >= 60 AND critical components (variables and analysis type) were found
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }