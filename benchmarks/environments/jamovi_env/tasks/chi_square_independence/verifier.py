#!/usr/bin/env python3
"""
Verifier for chi_square_independence task.

Checks:
1. Report file contains correct statistical values (Chi-square, df, p, V).
2. Project file (.omv) exists and was created during task.
3. Project file internal structure confirms analysis was run (anti-gaming).
"""

import json
import os
import re
import base64
import zipfile
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chi_square_independence(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_values', {})
    
    score = 0
    max_score = 100
    feedback_parts = []

    # ------------------------------------------------------------------
    # 1. Retrieve Result JSON
    # ------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ------------------------------------------------------------------
    # 2. Verify Report Content (Primary Metric) - 40 points
    # ------------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_b64 = result.get('report_content_b64', "")
    
    if report_exists and report_b64:
        try:
            report_text = base64.b64decode(report_b64).decode('utf-8', errors='ignore')
            feedback_parts.append("Report file found.")
            
            # Check Chi-Square Value (Range: 115.0 - 145.0)
            # Actual value usually around 127.8
            chi_match = re.search(r'(\d{3}\.\d+)', report_text)
            chi_val = float(chi_match.group(1)) if chi_match else 0
            
            if expected.get('chi_square_min', 115.0) <= chi_val <= expected.get('chi_square_max', 145.0):
                score += 15
                feedback_parts.append(f"Chi-square value correct ({chi_val})")
            else:
                feedback_parts.append(f"Chi-square value incorrect or missing (found: {chi_val})")

            # Check Degrees of Freedom (Expected: 2)
            if re.search(r'\bdf\s*[:=]?\s*2\b', report_text, re.IGNORECASE) or \
               re.search(r'degrees of freedom\s*[:=]?\s*2\b', report_text, re.IGNORECASE):
                score += 5
                feedback_parts.append("Degrees of freedom correct")

            # Check p-value (Expected: < 0.001)
            p_match = re.search(r'p\s*[:=<]\s*([<]?\s*\.0+|[<]?\s*0\.0+)', report_text, re.IGNORECASE)
            if p_match or "p < .001" in report_text or "p < 0.001" in report_text:
                score += 10
                feedback_parts.append("p-value correct")

            # Check Cramér's V (Range: 0.28 - 0.36)
            # Actual value usually around 0.31
            v_match = re.search(r'(?:V|Cramer)\D*(\d?\.\d+)', report_text, re.IGNORECASE)
            v_val = float(v_match.group(1)) if v_match else 0
            
            if expected.get('cramers_v_min', 0.28) <= v_val <= expected.get('cramers_v_max', 0.36):
                score += 10
                feedback_parts.append(f"Cramér's V correct ({v_val})")
            else:
                feedback_parts.append(f"Cramér's V incorrect or missing")

        except Exception as e:
            feedback_parts.append(f"Error parsing report: {str(e)}")
    else:
        feedback_parts.append("Report file missing.")

    # ------------------------------------------------------------------
    # 3. Verify Project File (Anti-Gaming) - 60 points
    # ------------------------------------------------------------------
    omv_exists = result.get('omv_exists', False)
    omv_fresh = result.get('omv_created_during_task', False)
    project_path = result.get('project_path', "")

    if omv_exists and omv_fresh:
        score += 20
        feedback_parts.append("Project file (.omv) saved.")
        
        # Deep Inspection: Download and unzip .omv to check internal analysis
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
        try:
            copy_from_env(project_path, temp_omv.name)
            
            is_valid_omv = False
            has_chisq = False
            has_cramer = False
            has_expected = False
            
            if zipfile.is_zipfile(temp_omv.name):
                with zipfile.ZipFile(temp_omv.name, 'r') as z:
                    file_list = z.namelist()
                    
                    # Read all analysis definition files (usually index.html or analysis specific JSONs)
                    content_str = ""
                    for fname in file_list:
                        if fname.endswith('.json') or fname.endswith('.html'):
                            try:
                                content_str += z.read(fname).decode('utf-8', errors='ignore')
                            except:
                                pass
                    
                    # Check for indicators of the correct analysis
                    # Keywords: "contTable" (contingency table), "chiSq", "cramer", "exp" (expected)
                    if "contTable" in content_str or "chiSq" in content_str:
                        has_chisq = True
                    if "cramer" in content_str.lower():
                        has_cramer = True
                    if "expected" in content_str.lower() or "rowPC" in content_str:
                        has_expected = True
                    
                    is_valid_omv = True

            if is_valid_omv:
                if has_chisq:
                    score += 20
                    feedback_parts.append("Verified Chi-Square analysis inside project file.")
                else:
                    feedback_parts.append("Project file does not appear to contain Chi-Square analysis.")
                
                if has_cramer and has_expected:
                    score += 20
                    feedback_parts.append("Verified Cramér's V and Expected Counts enabled.")
                elif has_cramer or has_expected:
                    score += 10
                    feedback_parts.append("Verified partial settings (V or Expected counts).")
            else:
                feedback_parts.append("Project file is not a valid Jamovi archive.")
                
        except Exception as e:
            feedback_parts.append(f"Failed to inspect .omv file: {e}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)
    else:
        feedback_parts.append("Project file missing or not created during task.")

    passed = score >= 80  # Strict passing: needs both correct report and valid project file

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }