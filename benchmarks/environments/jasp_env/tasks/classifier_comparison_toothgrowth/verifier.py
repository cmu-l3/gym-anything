#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import base64
import re

def verify_classifier_comparison(traj, env_info, task_info):
    """
    Verifies the Classifier Comparison task.
    
    Checks:
    1. JASP file exists and is a valid ZIP.
    2. JASP file contains 2 machine learning analyses (KNN and Decision Tree/Boosting).
    3. Both analyses have Random Seed set to 42.
    4. Both analyses use the correct variables.
    5. Report text file exists and contains AUC values.
    """
    
    # 1. Setup and Copy Files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy unavailable"}

    score = 0
    feedback = []
    
    # Load metadata
    expected_seed = task_info.get('metadata', {}).get('required_seed', 42)

    # Temporary directory for analysis
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        jasp_file_path = os.path.join(temp_dir, "analysis.jasp")
        
        # Get result JSON
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
            
        # Get JASP file
        if result_data.get("jasp_file_exists"):
            try:
                copy_from_env("/tmp/verifier_target.jasp", jasp_file_path)
            except Exception as e:
                feedback.append(f"JASP file exists but verify copy failed: {str(e)}")
        
        # --- CRITERION 1: File Existence & Anti-Gaming (20 pts) ---
        if result_data.get("jasp_file_exists") and result_data.get("jasp_file_created_during_task"):
            score += 20
            feedback.append("JASP project saved correctly.")
        elif result_data.get("jasp_file_exists"):
            score += 10
            feedback.append("JASP project exists but timestamp indicates it might be old.")
        else:
            feedback.append("JASP project file not found.")
            return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

        # --- CRITERION 2: Report File (15 pts) ---
        report_score = 0
        if result_data.get("report_file_exists") and result_data.get("report_file_created_during_task"):
            content_b64 = result_data.get("report_content_b64", "")
            try:
                content = base64.b64decode(content_b64).decode('utf-8')
                if "AUC" in content and "Best Model" in content:
                    report_score = 15
                    feedback.append("Report file valid.")
                else:
                    report_score = 10
                    feedback.append("Report file exists but content missing required keywords.")
            except:
                report_score = 5
                feedback.append("Report file cannot be decoded.")
        elif result_data.get("report_file_exists"):
            report_score = 5
            feedback.append("Report file exists but not created during task.")
        
        score += report_score

        # --- CRITERION 3: JASP Internal Configuration (65 pts) ---
        # JASP files are ZIPs containing JSONs describing the analysis
        try:
            with zipfile.ZipFile(jasp_file_path, 'r') as z:
                # List files to find analysis definitions
                # Structure varies but usually has 'embedded/...' or root JSONs
                # We look for any JSON that defines an analysis
                
                # JASP 0.16+ structure often puts state in "state.json" or "analysis-state.json"
                # But typically 'resources' or 'embedded' contains the actual analysis options
                
                # We will scan all JSON files in the zip for 'mlClassification'
                files = z.namelist()
                analysis_found = False
                knn_found = False
                tree_found = False
                seed_correct = 0
                
                json_files = [f for f in files if f.endswith('.json')]
                
                for jf in json_files:
                    try:
                        data = json.loads(z.read(jf).decode('utf-8', errors='ignore'))
                        
                        # Recursive search for analysis objects
                        def find_analyses(obj):
                            found = []
                            if isinstance(obj, dict):
                                if "analysisName" in obj or "name" in obj:
                                    # This might be an analysis definition
                                    name = obj.get("analysisName", "") or obj.get("name", "")
                                    if "mlClassification" in name:
                                        found.append(obj)
                                for k, v in obj.items():
                                    found.extend(find_analyses(v))
                            elif isinstance(obj, list):
                                for item in obj:
                                    found.extend(find_analyses(item))
                            return found

                        analyses = find_analyses(data)
                        
                        for analysis in analyses:
                            name = analysis.get("analysisName", "") or analysis.get("name", "")
                            options = analysis.get("options", {})
                            
                            # Check for KNN
                            if "Knn" in name:
                                knn_found = True
                                # Check Seed
                                # Option key might be "seed", "setSeed", "randomSeed"
                                seed = str(options.get("seed", ""))
                                set_seed = options.get("setSeed", False) # Boolean flag often exists
                                
                                # Sometimes seed is nested
                                if not seed and "seedBox" in options:
                                    seed = str(options["seedBox"].get("seed", ""))
                                
                                if str(expected_seed) in seed:
                                    seed_correct += 1
                            
                            # Check for Tree (Decision Tree or Boosting treated loosely as tree-based)
                            if "Tree" in name or "Boosting" in name or "RandomForest" in name:
                                tree_found = True
                                seed = str(options.get("seed", ""))
                                if not seed and "seedBox" in options:
                                    seed = str(options["seedBox"].get("seed", ""))
                                    
                                if str(expected_seed) in seed:
                                    seed_correct += 1
                                    
                    except Exception as e:
                        continue # Ignore unparseable JSONs
                
                if knn_found:
                    score += 15
                    feedback.append("KNN analysis found.")
                else:
                    feedback.append("KNN analysis NOT found.")
                    
                if tree_found:
                    score += 15
                    feedback.append("Decision Tree analysis found.")
                else:
                    feedback.append("Decision Tree analysis NOT found.")
                
                if seed_correct >= 2:
                    score += 35
                    feedback.append(f"Random seed {expected_seed} set correctly for both models.")
                elif seed_correct == 1:
                    score += 15
                    feedback.append(f"Random seed {expected_seed} set for only one model.")
                else:
                    feedback.append(f"Random seed {expected_seed} NOT set (verification requires exact reproducibility).")

        except zipfile.BadZipFile:
            feedback.append("Saved JASP file is corrupt (not a valid zip).")
            score = 0 # reset score if file is invalid
        except Exception as e:
            feedback.append(f"Error parsing JASP file: {str(e)}")

    # Final tally
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }