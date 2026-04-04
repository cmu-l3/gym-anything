#!/usr/bin/env python3
"""
Verifier for BFI Gender Prediction task.
Verifies:
1. .omv file creation and internal structure (Computed variables, Logistic Regression analysis).
2. Report file content (AUC and Accuracy values).
3. Logic check: Reported values must be within valid range for this dataset.
"""

import json
import os
import zipfile
import re
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bfi_gender_prediction_logistic_accuracy(traj, env_info, task_info):
    """
    Verify the Jamovi task using file artifacts and content analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Setup temporary directory for analysis
    work_dir = tempfile.mkdtemp()
    omv_local_path = os.path.join(work_dir, "project.omv")
    result_json_path = os.path.join(work_dir, "task_result.json")
    
    score = 0
    feedback_parts = []
    
    try:
        # 1. Get Result JSON
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {str(e)}"}
            
        # 2. Check File Existence (10 pts)
        if task_result.get("omv_exists") and task_result.get("omv_created_during_task"):
            score += 10
            feedback_parts.append("OMV file created")
        else:
            feedback_parts.append("OMV file missing or not created during task")
            
        if task_result.get("report_exists"):
            score += 5
            feedback_parts.append("Report file created")
        else:
            feedback_parts.append("Report file missing")
            
        # 3. Analyze OMV Structure (50 pts total)
        # OMV is a ZIP file. We look for '0000.json' or similar for analysis defs, and data metadata.
        analysis_found = False
        vars_found = 0
        expected_vars = ["Agreeableness", "Conscientiousness", "Extraversion", "Neuroticism", "Openness"]
        auc_enabled = False
        class_table_enabled = False
        
        if task_result.get("omv_exists"):
            try:
                copy_from_env(metadata["expected_omv_path"], omv_local_path)
                
                if zipfile.is_zipfile(omv_local_path):
                    with zipfile.ZipFile(omv_local_path, 'r') as z:
                        # Inspect Metadata to find computed variables
                        # Usually in metadata.json or xdata.json, depending on Jamovi version.
                        # We scan all json files for variable definitions.
                        json_files = [f for f in z.namelist() if f.endswith('.json')]
                        
                        file_content_str = ""
                        for jf in json_files:
                            try:
                                content = z.read(jf).decode('utf-8')
                                file_content_str += content
                                
                                # Check for Analysis
                                if '"logRegBin"' in content or '"linReg"' in content: # Loose check first
                                    # specific check
                                    pass
                            except:
                                continue
                                
                        # Check for Computed Variables
                        for var in expected_vars:
                            if var in file_content_str:
                                vars_found += 1
                        
                        # Check for Logistic Regression Analysis
                        # Look for analysis configuration in the JSONs
                        # Structure is complex, so we regex for key indicators
                        if 'logRegBin' in file_content_str:
                            analysis_found = True
                            
                        # Check options
                        if '"auc":true' in file_content_str or '"auc": true' in file_content_str:
                            auc_enabled = True
                        if '"class":true' in file_content_str or '"class": true' in file_content_str:
                            class_table_enabled = True
                            
            except Exception as e:
                feedback_parts.append(f"Error analyzing OMV: {str(e)}")

        # Scoring OMV Analysis
        if vars_found >= 5:
            score += 20
            feedback_parts.append("All computed variables found")
        elif vars_found > 0:
            score += int(vars_found * 4)
            feedback_parts.append(f"{vars_found}/5 computed variables found")
        else:
            feedback_parts.append("No computed variables found")
            
        if analysis_found:
            score += 15
            feedback_parts.append("Logistic Regression analysis found")
            
            if auc_enabled:
                score += 10
                feedback_parts.append("AUC option enabled")
            if class_table_enabled:
                score += 5
                feedback_parts.append("Classification table enabled")
        else:
            feedback_parts.append("No Logistic Regression analysis found")

        # 4. Verify Reported Values (35 pts)
        report_content = task_result.get("report_content", "")
        
        # Regex to find numbers
        auc_match = re.search(r"AUC:?\s*0\.(\d+)", report_content)
        acc_match = re.search(r"Accuracy:?\s*(0\.\d+|[\d\.]+%)", report_content)
        
        reported_auc = 0.0
        reported_acc = 0.0
        
        valid_values = False
        
        if auc_match:
            try:
                reported_auc = float("0." + auc_match.group(1))
                # Known approximate range for BFI gender prediction (approx 0.64-0.68 usually)
                if 0.60 <= reported_auc <= 0.75:
                    score += 15
                    feedback_parts.append(f"Reported AUC valid ({reported_auc})")
                    valid_values = True
                else:
                    feedback_parts.append(f"Reported AUC out of expected range ({reported_auc})")
            except:
                pass
        else:
            feedback_parts.append("AUC not found in report")

        if acc_match:
            try:
                val_str = acc_match.group(1)
                if "%" in val_str:
                    reported_acc = float(val_str.replace("%", "")) / 100.0
                else:
                    reported_acc = float(val_str)
                
                # Known approximate range for BFI gender prediction accuracy (approx 0.60-0.65)
                if 0.55 <= reported_acc <= 0.72:
                    score += 20
                    feedback_parts.append(f"Reported Accuracy valid ({reported_acc})")
                    valid_values = True
                else:
                    feedback_parts.append(f"Reported Accuracy out of expected range ({reported_acc})")
            except:
                pass
        else:
            feedback_parts.append("Accuracy not found in report")

        # 5. Anti-gaming / Pass Logic
        passed = (score >= 80) and analysis_found and valid_values
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "; ".join(feedback_parts)
        }
        
    finally:
        shutil.rmtree(work_dir, ignore_errors=True)