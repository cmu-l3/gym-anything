#!/usr/bin/env python3
"""
Verifier for ancova_exam_performance@1

Checks the saved .omv file for correct ANCOVA configuration:
- Analysis type is ANCOVA
- Correct DV (Exam), factor (Gender), covariate (Anxiety)
- Assumption checks (Homogeneity)
- Estimated Marginal Means (Gender)
- Effect size (partial eta-squared)
"""

import json
import os
import zipfile
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ancova_exam_performance(traj, env_info, task_info):
    """
    Verify the agent correctly ran the ANCOVA and saved the OMV file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    details = []
    
    # ================================================================
    # 1. Load Task Result JSON
    # ================================================================
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ================================================================
    # 2. Check File Existence & Timestamp (Anti-Gaming)
    # ================================================================
    output_exists = task_result.get("output_exists", False)
    created_during = task_result.get("file_created_during_task", False)
    
    if output_exists:
        score += 10
        details.append("PASS [10]: Output file exists")
        
        if created_during:
            score += 10
            details.append("PASS [10]: File created during task window")
        else:
            details.append("FAIL [0]: File timestamp outside task window (pre-existing?)")
    else:
        details.append("FAIL [0]: Output file not found")
        # Critical fail if file missing, but we still do VLM check for partial points
    
    # ================================================================
    # 3. Analyze OMV File Content
    # ================================================================
    omv_analysis_passed = False
    
    if output_exists:
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
        try:
            copy_from_env(task_result["output_path"], temp_omv.name)
            
            # Jamovi .omv files are ZIP archives containing JSON analysis specs
            try:
                with zipfile.ZipFile(temp_omv.name, 'r') as zf:
                    analyses = []
                    # Extract analysis definitions
                    for entry in zf.namelist():
                        if "analysis" in entry.lower() and not entry.endswith("/"):
                            try:
                                content = zf.read(entry).decode("utf-8")
                                obj = json.loads(content)
                                if isinstance(obj, dict):
                                    analyses.append(obj)
                            except:
                                continue
                    
                    if not analyses:
                        details.append("FAIL [0]: Valid OMV but no analyses found inside")
                    else:
                        # Score the analysis configuration
                        best_analysis_score = 0
                        best_analysis_details = []
                        
                        for analysis in analyses:
                            a_score = 0
                            a_logs = []
                            options = analysis.get("options", analysis.get("Options", {}))
                            name = analysis.get("name", "").lower()
                            
                            # Check 3.1: Is ANCOVA? (20 pts)
                            # Jamovi often labels it "ancova" or uses jmv::ancova
                            if "ancova" in name:
                                a_score += 20
                                a_logs.append("PASS [20]: ANCOVA analysis type found")
                            else:
                                a_logs.append(f"INFO: Analysis type is {name}")
                            
                            # Check 3.2: Dependent Variable = Exam (10 pts)
                            dep = options.get("dep", "")
                            if isinstance(dep, str) and "exam" in dep.lower():
                                a_score += 10
                                a_logs.append("PASS [10]: Correct Dependent Variable (Exam)")
                            elif isinstance(dep, list) and any("exam" in str(d).lower() for d in dep):
                                a_score += 10
                                a_logs.append("PASS [10]: Correct Dependent Variable (Exam)")
                                
                            # Check 3.3: Fixed Factor = Gender (10 pts)
                            fixed = options.get("fixedFactors", options.get("fixed", []))
                            if any("gender" in str(f).lower() for f in fixed):
                                a_score += 10
                                a_logs.append("PASS [10]: Correct Fixed Factor (Gender)")
                                
                            # Check 3.4: Covariate = Anxiety (10 pts)
                            covs = options.get("covs", options.get("covariates", []))
                            if any("anxiety" in str(c).lower() for c in covs):
                                a_score += 10
                                a_logs.append("PASS [10]: Correct Covariate (Anxiety)")
                                
                            # Check 3.5: Homogeneity Test (5 pts)
                            # Key often "homo", "homoTest"
                            if options.get("homo", False) is True or str(options.get("homo", "")).lower() == "true":
                                a_score += 5
                                a_logs.append("PASS [5]: Homogeneity test enabled")
                                
                            # Check 3.6: Effect Size (5 pts)
                            # Key often "effectSize", "etaSq", "etaSqP"
                            es_keys = ["effectSize", "etaSqP", "partEtaSq"]
                            if any(options.get(k) is True or str(options.get(k)).lower() == "true" for k in es_keys):
                                a_score += 5
                                a_logs.append("PASS [5]: Effect size enabled")
                                
                            # Check 3.7: Estimated Marginal Means (5 pts)
                            # Look for 'emMeans' list or configuration
                            emm = options.get("emMeans", [])
                            if isinstance(emm, list) and len(emm) > 0:
                                a_score += 5
                                a_logs.append("PASS [5]: Estimated Marginal Means configured")
                            elif options.get("emmTables", False) is True:
                                a_score += 5
                                a_logs.append("PASS [5]: Estimated Marginal Means enabled")

                            if a_score > best_analysis_score:
                                best_analysis_score = a_score
                                best_analysis_details = a_logs
                        
                        score += best_analysis_score
                        details.extend(best_analysis_details)
                        if best_analysis_score >= 40:
                            omv_analysis_passed = True

            except zipfile.BadZipFile:
                details.append("FAIL [0]: Output file is not a valid OMV/ZIP archive")
            except Exception as e:
                details.append(f"FAIL [0]: Error parsing OMV file: {str(e)}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)

    # ================================================================
    # 4. VLM Verification (Fallback/Confirmation) (15 pts)
    # ================================================================
    # Only verify visually if programmatic check failed OR to confirm app state
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    vlm_prompt = """
    You are verifying a Jamovi statistical task.
    Goal: Run an ANCOVA with Exam (DV), Gender (Factor), and Anxiety (Covariate).
    
    Check the screenshots for:
    1. An ANCOVA result table (should say "ANCOVA" or "Analysis of Covariance").
    2. A table showing rows for 'Gender' and 'Anxiety'.
    3. Assumption check tables (e.g., Levene's Test/Homogeneity).
    4. Estimated Marginal Means plots or tables.
    
    Return JSON:
    {
        "ancova_table_visible": boolean,
        "variables_correct": boolean,
        "homogeneity_test_visible": boolean,
        "emm_visible": boolean
    }
    """
    
    vlm_score = 0
    if final_screenshot:
        try:
            res = query_vlm(prompt=vlm_prompt, images=frames + [final_screenshot])
            parsed = res.get("parsed", {})
            
            if parsed.get("ancova_table_visible"):
                vlm_score += 5
                details.append("PASS [5]: VLM detected ANCOVA table")
            if parsed.get("variables_correct"):
                vlm_score += 5
                details.append("PASS [5]: VLM detected correct variables in output")
            if parsed.get("homogeneity_test_visible") or parsed.get("emm_visible"):
                vlm_score += 5
                details.append("PASS [5]: VLM detected additional statistics options")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # If OMV analysis passed, we cap VLM points to remaining available score or treat as bonus confirmation
    # If OMV missing, VLM is the only way to get points (but max is lower)
    
    if not output_exists:
        # File missing -> cap score at 40 (only VLM points + partial app running pts)
        score = min(score + vlm_score, 40)
    else:
        # File exists -> add VLM points to fill gaps
        score = min(score + vlm_score, 100)

    # App running check (5 pts)
    if task_result.get("app_was_running", False):
        if score < 100:
            score += 5
            details.append("PASS [5]: Application was running at end")
            score = min(score, 100)
            
    passed = (score >= 70) and omv_analysis_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }