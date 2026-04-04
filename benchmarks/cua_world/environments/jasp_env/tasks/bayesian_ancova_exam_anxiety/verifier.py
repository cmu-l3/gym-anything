#!/usr/bin/env python3
"""
Verifier for Bayesian ANCOVA task in JASP.
Verifies the output .jasp file (ZIP archive) contains the correct analysis configuration.
"""

import json
import os
import zipfile
import tempfile
import shutil
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bayesian_ancova(traj, env_info, task_info):
    """
    Verify JASP Bayesian ANCOVA task.
    
    Criteria:
    1. Output file exists and was created during task (20 pts)
    2. File is a valid JASP archive (10 pts)
    3. JSON Analysis Def: Correct Analysis Type (Bayesian ANOVA) (15 pts)
    4. JSON Analysis Def: DV = Exam (15 pts)
    5. JSON Analysis Def: Fixed Factor = Gender (15 pts)
    6. JSON Analysis Def: Covariate = Anxiety (15 pts)
    7. JSON Analysis Def: Descriptives & Plots enabled (10 pts)
    
    Total: 100 pts. Pass threshold: 70 pts.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # 2. Retrieve Metadata
    meta_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", meta_file.name)
        with open(meta_file.name, 'r') as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task metadata: {str(e)}"}
    finally:
        if os.path.exists(meta_file.name):
            os.unlink(meta_file.name)

    # 3. Verify File Existence & Anti-Gaming
    if not meta.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not meta.get("file_created_during_task", False):
        feedback.append("WARNING: File timestamp indicates it was not created during this session.")
        # We penalize but continue inspection in case clock skew or file overwrite logic is tricky
    else:
        score += 20
        feedback.append("Output file created successfully.")

    # 4. Retrieve and Inspect JASP File
    jasp_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    extract_dir = tempfile.mkdtemp()
    
    try:
        copy_from_env(meta["output_path"], jasp_temp.name)
        
        # Check if valid zip
        if not zipfile.is_zipfile(jasp_temp.name):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid JASP/Zip archive."}
        
        score += 10 # Valid archive
        
        with zipfile.ZipFile(jasp_temp.name, 'r') as zip_ref:
            zip_ref.extractall(extract_dir)
            
        # Recursive search for JSON files containing analysis details
        # JASP structure usually has a 'results' folder with numbered subfolders for analyses
        analysis_found = False
        config_correct = {
            "is_bayesian": False,
            "dv_exam": False,
            "factor_gender": False,
            "cov_anxiety": False,
            "descriptives": False,
            "plots": False
        }
        
        # Helper to search JSON content recursively
        def check_json_content(data):
            # Convert to string for regex-like loose matching, or traverse dict
            s_data = json.dumps(data).lower()
            
            # 1. Check Analysis Type
            if "bayesian" in s_data and "anova" in s_data:
                config_correct["is_bayesian"] = True
            
            # 2. Check Variables assignments
            # Structure often: "dependent": ["Exam"], "fixedFactors": ["Gender"], "covariates": ["Anxiety"]
            # Or in "options" dict
            
            # Dependent Variable
            if '"dependent": "exam"' in s_data or '"dependent": ["exam"]' in s_data:
                config_correct["dv_exam"] = True
            elif "exam" in s_data and "dependent" in s_data: 
                # Loose check for messy JSON structures
                config_correct["dv_exam"] = True

            # Fixed Factor
            if '"fixedfactors": "gender"' in s_data or '"fixedfactors": ["gender"]' in s_data:
                config_correct["factor_gender"] = True
            
            # Covariate
            if '"covariates": "anxiety"' in s_data or '"covariates": ["anxiety"]' in s_data:
                config_correct["cov_anxiety"] = True

            # Options
            if '"descriptives": true' in s_data or '"descriptivestable": true' in s_data:
                config_correct["descriptives"] = True
            
            if '"plothorizontalaxis": "gender"' in s_data or '"descriptivesplot": true' in s_data:
                config_correct["plots"] = True

        # Walk through extracted files
        for root, dirs, files in os.walk(extract_dir):
            for file in files:
                if file.endswith(".json"):
                    try:
                        with open(os.path.join(root, file), 'r') as f:
                            data = json.load(f)
                            check_json_content(data)
                            analysis_found = True
                    except:
                        continue

        # Score based on findings
        if config_correct["is_bayesian"]:
            score += 15
            feedback.append("Correct Analysis Type: Bayesian ANOVA detected.")
        else:
            feedback.append("Incorrect Analysis Type (Bayesian ANOVA not found in file).")

        if config_correct["dv_exam"]:
            score += 15
            feedback.append("Dependent Variable 'Exam' correctly assigned.")
        else:
            feedback.append("Dependent Variable 'Exam' NOT found.")

        if config_correct["factor_gender"]:
            score += 15
            feedback.append("Fixed Factor 'Gender' correctly assigned.")
        else:
            feedback.append("Fixed Factor 'Gender' NOT found.")

        if config_correct["cov_anxiety"]:
            score += 15
            feedback.append("Covariate 'Anxiety' correctly assigned.")
        else:
            feedback.append("Covariate 'Anxiety' NOT found.")

        if config_correct["descriptives"] and config_correct["plots"]:
            score += 10
            feedback.append("Descriptives and Plots enabled.")
        elif config_correct["descriptives"] or config_correct["plots"]:
            score += 5
            feedback.append("Partial credit for options (Descriptives/Plots).")
            
    except Exception as e:
        feedback.append(f"Error parsing JASP file: {str(e)}")
        
    finally:
        if os.path.exists(jasp_temp.name):
            os.unlink(jasp_temp.name)
        shutil.rmtree(extract_dir, ignore_errors=True)

    # 5. VLM Verification (Trajectory check)
    # If score is borderline or verification failed, use VLM to double check visual evidence
    if score < 100:
        frames = sample_trajectory_frames(traj, n=5)
        final_ss = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a JASP statistical analysis session.
        I am looking for evidence of a Bayesian ANCOVA.
        
        Check for:
        1. "Bayesian ANOVA" or "Bayesian ANCOVA" in the results panel.
        2. A "Model Comparison" table containing Bayes Factors (BF10 or BF01).
        3. A "Descriptives" table showing Mean/SD for Gender groups.
        4. A plot showing Exam scores by Gender.
        
        Does the final state or trajectory show these elements?
        """
        
        vlm_res = query_vlm(images=frames + [final_ss], prompt=prompt)
        
        if vlm_res.get("success") and "yes" in vlm_res.get("response", "").lower():
            # If VLM is confident, we can bump the score if file parsing failed due to format changes
            # But we trust the file parser more. We'll use this mostly for feedback context.
            feedback.append(f"VLM Analysis: Visual evidence suggests task completion. ({vlm_res.get('response')[:50]}...)")
            # Grant partial points if file failed but visual evidence is strong
            if score < 70:
                score += 20
                feedback.append("Bumped score based on visual evidence.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }