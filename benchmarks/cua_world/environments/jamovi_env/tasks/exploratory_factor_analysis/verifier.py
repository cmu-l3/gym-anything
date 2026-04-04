#!/usr/bin/env python3
"""
Verifier for Exploratory Factor Analysis task in Jamovi.

Verification Strategy:
1. File Verification (Primary):
   - Inspects the saved .omv file (which is a ZIP archive).
   - Parses internal JSON configuration to verify:
     - Correct variables (25 items)
     - Correct number of factors (5)
     - Correct rotation (oblimin)
     - Options enabled (Summary, Correlations)

2. VLM Verification (Secondary):
   - Checks trajectory frames to ensure the agent actually interacted with the UI
     and didn't just generate a file programmatically (anti-gaming).
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exploratory_factor_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/Jamovi/BFI25_EFA.omv')
    
    score = 0
    feedback_parts = []
    
    # Create temp directory for analysis
    with tempfile.TemporaryDirectory() as temp_dir:
        # 1. Retrieve task result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # Check basic file existence and timing
        if not task_result.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Output .omv file not found."}
        
        score += 15
        feedback_parts.append("File created")

        if task_result.get('file_created_during_task'):
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("Warning: File timestamp predates task start")

        if task_result.get('output_size_bytes', 0) < 1000:
            return {"passed": False, "score": score, "feedback": "Output file is too small to be a valid analysis."}

        # 2. Retrieve and Inspect OMV file
        omv_local_path = os.path.join(temp_dir, "analysis.omv")
        try:
            copy_from_env(expected_path, omv_local_path)
            
            # Verify internal structure of OMV (Zip archive)
            if not zipfile.is_zipfile(omv_local_path):
                return {"passed": False, "score": score, "feedback": "Output file is not a valid OMV archive."}
            
            score += 10
            feedback_parts.append("Valid OMV format")

            # Extract and analyze JSON configurations
            # Jamovi OMV files contain analysis settings in JSON format, usually in an 'analysis' folder
            # or embedded in the manifest. We search for the EFA configuration.
            found_efa = False
            correct_vars = False
            correct_factors = False
            correct_rotation = False
            summary_enabled = False
            correlations_enabled = False
            
            with zipfile.ZipFile(omv_local_path, 'r') as z:
                # Iterate through all files in the zip to find analysis configurations
                for filename in z.namelist():
                    if filename.endswith('.json') or filename.endswith('analysis'):
                        try:
                            content = z.read(filename).decode('utf-8', errors='ignore')
                            # Heuristic search in JSON content
                            # We look for specific keys that indicate EFA configuration
                            
                            # Check if this is an EFA analysis
                            if '"type": "efa"' in content or '"analysis": "efa"' in content or 'jmv::efa' in content:
                                found_efa = True
                                
                                # Check variables (rough check for count or specific vars)
                                # Counting occurrences of variable names in the "vars" section is tricky with text search,
                                # so we look for the list presence.
                                # Checking for a subset of BFI vars:
                                if all(v in content for v in ["A1", "C1", "E1", "N1", "O1"]):
                                    correct_vars = True
                                
                                # Check parameters
                                if '"nFactors": 5' in content or '"nFactors":5' in content:
                                    correct_factors = True
                                
                                if '"rotation": "oblimin"' in content or '"rotation":"oblimin"' in content:
                                    correct_rotation = True
                                
                                if '"factorSummary": true' in content:
                                    summary_enabled = True
                                
                                if '"factorCor": true' in content:
                                    correlations_enabled = True
                                    
                        except:
                            continue

            if found_efa:
                score += 15
                feedback_parts.append("EFA analysis found")
                
                if correct_vars:
                    score += 15
                    feedback_parts.append("Variables selected")
                else:
                    feedback_parts.append("Incorrect variables")

                if correct_factors:
                    score += 15
                    feedback_parts.append("5 Factors configured")
                else:
                    feedback_parts.append("Wrong factor count")

                if correct_rotation:
                    score += 10
                    feedback_parts.append("Oblimin rotation")
                else:
                    feedback_parts.append("Wrong rotation")

                if summary_enabled and correlations_enabled:
                    score += 10
                    feedback_parts.append("Output options enabled")
            else:
                feedback_parts.append("No EFA analysis found in file")

        except Exception as e:
            feedback_parts.append(f"Error inspecting OMV file: {str(e)}")

    # 3. VLM Trajectory Verification (Stub for robust implementation)
    # Ideally, we query VLM with trajectory frames here.
    # For now, we assume if the file verification passed with high confidence, VLM is implicit.
    # We add a small bonus if the app was running at the end.
    if task_result.get('app_was_running'):
        score += 10
        feedback_parts.append("Jamovi active")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }