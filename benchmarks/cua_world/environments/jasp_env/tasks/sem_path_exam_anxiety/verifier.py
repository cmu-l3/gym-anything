#!/usr/bin/env python3
"""
Verifier for sem_path_exam_anxiety task.
Verifies JASP SEM analysis by inspecting the .jasp (zip) file content and report text.
"""

import json
import os
import sys
import tempfile
import zipfile
import re
import logging
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_sem_path_model(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the SEM Path Analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Required metadata
    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve Task Result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json)
        with open(temp_result_json, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution details"}
    finally:
        if os.path.exists(temp_result_json):
            os.unlink(temp_result_json)

    # 2. Check File Existence and Timestamps (Anti-gaming)
    if task_result.get("jasp_exists") and task_result.get("jasp_created_during_task"):
        score += 10
        feedback_parts.append("JASP file created.")
    else:
        feedback_parts.append("JASP file missing or not created during task.")

    if task_result.get("report_exists") and task_result.get("report_created_during_task"):
        score += 5
        feedback_parts.append("Report file created.")
    else:
        feedback_parts.append("Report file missing.")

    if task_result.get("app_was_running"):
        score += 5
        feedback_parts.append("JASP was running.")

    # 3. Analyze JASP File Content
    jasp_valid_score = 0
    jasp_sem_score = 0
    syntax_score = 0
    options_score = 0
    
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp').name
    try:
        if task_result.get("jasp_exists"):
            copy_from_env("/tmp/Exam_Path_Model.jasp", temp_jasp)
            
            if not zipfile.is_zipfile(temp_jasp):
                feedback_parts.append("JASP file is not a valid zip archive.")
            else:
                with zipfile.ZipFile(temp_jasp, 'r') as z:
                    # Look for analyses manifest
                    # Structure usually involves 'analyses/1/analysis.json' or similar
                    # We will search for any json file that looks like an analysis definition
                    analysis_found = False
                    sem_module_found = False
                    model_syntax = ""
                    options = {}
                    
                    # Naive search through all json files in zip
                    for filename in z.namelist():
                        if filename.endswith(".json"):
                            try:
                                with z.open(filename) as f:
                                    data = json.load(f)
                                    # Check if this is a SEM analysis
                                    # Usually structure: { "name": "Sem", "options": { ... } }
                                    # Or JASP 0.16+: { "title": "Structural Equation Modeling", ... }
                                    
                                    # Heuristic 1: Check title/name
                                    title = data.get("title", "")
                                    name = data.get("name", "")
                                    if "Structural Equation Modeling" in title or "Sem" == name:
                                        sem_module_found = True
                                        analysis_found = True
                                        options = data.get("options", {})
                                        model_syntax = options.get("model", "")
                                        # JASP sometimes stores syntax in 'model' or 'syntax' key
                                        if not model_syntax:
                                            model_syntax = options.get("syntax", "")
                                        break
                                    
                                    # Heuristic 2: Look inside 'results' list if top level is different
                                    if "results" in data:
                                        for res in data["results"]:
                                            if "Sem" in res.get("name", ""):
                                                sem_module_found = True
                                                analysis_found = True
                                                # Options might be harder to extract here, assume first match
                                                break
                            except:
                                continue
                    
                    if sem_module_found:
                        jasp_sem_score = 15
                        feedback_parts.append("Correct SEM module used.")
                        
                        # Verify Syntax
                        # Expected: Anxiety ~ Revise AND Exam ~ Anxiety
                        # Forbidden: Exam ~ Revise
                        
                        # Normalize syntax (remove spaces/newlines)
                        norm_syntax = re.sub(r'\s+', '', model_syntax)
                        
                        # Check positive constraints
                        # Anxiety ~ Revise
                        has_anx_rev = "Anxiety~Revise" in norm_syntax or "Anxiety=~Revise" in norm_syntax 
                        # Exam ~ Anxiety
                        has_exam_anx = "Exam~Anxiety" in norm_syntax or "Exam=~Anxiety" in norm_syntax
                        
                        if has_anx_rev and has_exam_anx:
                            syntax_score += 20
                            feedback_parts.append("Model paths correctly defined.")
                        else:
                            feedback_parts.append(f"Model paths missing. Found: {model_syntax}")

                        # Check negative constraint (No direct path)
                        has_direct = "Exam~Revise" in norm_syntax
                        if not has_direct:
                            syntax_score += 25
                            feedback_parts.append("Direct path correctly excluded (Restricted model).")
                        else:
                            feedback_parts.append("FAILED: Direct path 'Exam ~ Revise' was included.")
                            
                        # Verify Options
                        # standardizedEstimates: true
                        # outputPathDiagram: true
                        # outputRSquared: true
                        if options.get("standardizedEstimates", False):
                            options_score += 5
                        if options.get("outputPathDiagram", False) or options.get("plotPathDiagram", False):
                            options_score += 5
                        if options_score >= 5:
                             feedback_parts.append("Output options configured.")

                    elif analysis_found:
                         feedback_parts.append("Analysis found but likely wrong module (not SEM).")
                    else:
                         feedback_parts.append("No valid analysis found in JASP file.")

    except Exception as e:
        logger.error(f"Error processing JASP file: {e}")
        feedback_parts.append(f"Error processing JASP file: {str(e)}")
    finally:
        if os.path.exists(temp_jasp):
            os.unlink(temp_jasp)

    # 4. Analyze Report Content
    report_score = 0
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    try:
        if task_result.get("report_exists"):
            copy_from_env("/tmp/Model_Fit_Report.txt", temp_report)
            with open(temp_report, 'r', errors='ignore') as f:
                content = f.read().lower()
            
            # Search for p-value pattern
            # Matches: p = .05, p-value: 0.043, 0.043, etc.
            p_val_match = re.search(r'p\s*[=:]?\s*0?\.(\d+)', content)
            
            if p_val_match:
                report_score += 10
                # Check interpretation
                if "good fit" in content or "fits the data" in content:
                    # Ground truth: For ExamAnxiety, removing the direct path actually results in 
                    # SIGNIFICANT Chi-square (p < .05), meaning BAD fit (Direct path is needed).
                    # However, if the agent says it fits well or poorly, we check logic.
                    # Logic: p < 0.05 -> Poor fit. p > 0.05 -> Good fit.
                    # We give points if they provide an interpretation logic.
                    report_score += 10
                elif "poor fit" in content or "significant" in content or "bad fit" in content:
                    report_score += 10
                feedback_parts.append("Report contains p-value and interpretation.")
            else:
                feedback_parts.append("Report does not contain a recognizable p-value.")

    except Exception as e:
        feedback_parts.append("Error reading report file.")
    finally:
        if os.path.exists(temp_report):
            os.unlink(temp_report)
            
    # Calculate Final Score
    score += jasp_sem_score + syntax_score + options_score + report_score
    
    # Critical criteria for passing
    # Must use SEM, must have correct syntax (restriction), must have created files
    passed = (score >= 60 and 
              task_result.get("jasp_created_during_task") and 
              syntax_score >= 40) # 20 (paths) + 25 (restriction) >= 45 ideally, allowing small margin

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }