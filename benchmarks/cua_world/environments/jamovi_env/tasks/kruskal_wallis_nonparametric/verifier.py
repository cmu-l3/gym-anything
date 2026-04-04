#!/usr/bin/env python3
"""
Verifier for Kruskal-Wallis Non-Parametric Task in Jamovi.

Verification criteria:
1. Jamovi project file (.omv) exists and was created during the task.
2. The .omv file (which is a zip) contains analysis results matching:
   - Kruskal-Wallis test
   - Chi-squared approx 54.69
   - Epsilon-squared approx 0.77
   - DSCF pairwise comparisons table
3. Report file exists and contains correct values.
4. VLM trajectory verification (workflow progression).
"""

import json
import os
import tempfile
import zipfile
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_kruskal_wallis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_stats = metadata.get('expected_stats', {})
    
    score = 0
    feedback_parts = []
    
    # Load basic result info
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # ------------------------------------------------------------------
    # 1. File Existence and Anti-Gaming (20 pts)
    # ------------------------------------------------------------------
    omv_exists = task_result.get("omv_exists", False)
    omv_fresh = task_result.get("omv_created_during_task", False)
    report_exists = task_result.get("report_exists", False)
    
    if omv_exists and omv_fresh:
        score += 20
        feedback_parts.append("Jamovi project file created successfully.")
    elif omv_exists:
        score += 5
        feedback_parts.append("Jamovi file exists but has old timestamp (pre-task?).")
    else:
        feedback_parts.append("Jamovi project file (.omv) not found.")

    # ------------------------------------------------------------------
    # 2. OMV Content Analysis (40 pts)
    # ------------------------------------------------------------------
    omv_analysis_score = 0
    omv_feedback = []
    
    if omv_exists:
        temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.zip') # .omv is a zip
        try:
            copy_from_env(task_result.get("omv_path"), temp_omv.name)
            
            with zipfile.ZipFile(temp_omv.name, 'r') as z:
                # Jamovi files typically have an index.html containing the report
                # or JSON files defining the analysis.
                # We'll look for index.html first as it contains the rendered numbers.
                
                content_found = False
                try:
                    with z.open('index.html') as f:
                        html_content = f.read().decode('utf-8', errors='ignore')
                        content_found = True
                except KeyError:
                    # Fallback: Check if there are other html files in nested folders
                    html_files = [n for n in z.namelist() if n.endswith('.html')]
                    if html_files:
                        with z.open(html_files[0]) as f:
                            html_content = f.read().decode('utf-8', errors='ignore')
                            content_found = True
                
                if content_found:
                    # Check for Kruskal-Wallis header
                    if "Kruskal-Wallis" in html_content:
                        omv_analysis_score += 10
                        omv_feedback.append("Kruskal-Wallis test found.")
                    
                    # Check for Chi-Squared value (54.69)
                    # Allow flex format like 54.7 or 54.69
                    if re.search(r"54\.[67]", html_content):
                        omv_analysis_score += 10
                        omv_feedback.append("Correct Chi-Squared statistic found.")
                    
                    # Check for Epsilon-Squared (Effect Size) -> ~0.77
                    # Usually labeled as "ε²" or "Epsilon-squared"
                    if "0.77" in html_content or "0.76" in html_content or "0.78" in html_content:
                        omv_analysis_score += 10
                        omv_feedback.append("Effect size (epsilon-squared) found.")
                    
                    # Check for DSCF pairwise comparisons
                    # Look for "DSCF" or specific comparisons like "A" and "C"
                    if "DSCF" in html_content or "Dwass-Steel-Critchlow-Fligner" in html_content:
                        omv_analysis_score += 10
                        omv_feedback.append("DSCF pairwise comparisons found.")
                    
                else:
                    omv_feedback.append("Could not extract analysis results from .omv file.")

        except Exception as e:
            omv_feedback.append(f"Error inspecting .omv file: {str(e)}")
        finally:
            if os.path.exists(temp_omv.name):
                os.unlink(temp_omv.name)
    
    score += omv_analysis_score
    if omv_feedback:
        feedback_parts.append("Analysis check: " + "; ".join(omv_feedback))

    # ------------------------------------------------------------------
    # 3. Report Content Verification (20 pts)
    # ------------------------------------------------------------------
    if report_exists:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(task_result.get("report_path"), temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_text = f.read()
            
            report_score = 0
            # Check for key values
            if "54." in report_text:
                report_score += 5
            if "0.77" in report_text or "0.76" in report_text:
                report_score += 5
            # Check for interpretation (Sprays C, D, E are better/lower)
            if any(x in report_text.upper() for x in ["C", "D", "E"]) and "EFFECTIVE" in report_text.upper():
                report_score += 10
            
            score += report_score
            feedback_parts.append(f"Report verification score: {report_score}/20")
            
        except Exception as e:
            feedback_parts.append(f"Error verifying report: {str(e)}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback_parts.append("Report file not found.")

    # ------------------------------------------------------------------
    # 4. VLM Verification (20 pts)
    # ------------------------------------------------------------------
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if frames and final_frame:
        prompt = """
        You are verifying a user performing a statistical analysis in Jamovi.
        The task is to:
        1. Open the InsectSprays dataset (look for columns 'count' and 'spray').
        2. Run a Non-Parametric Kruskal-Wallis ANOVA.
        3. Enable DSCF pairwise comparisons and Effect Size.

        Review the screenshots.
        1. Is the Jamovi interface visible?
        2. Do you see the "Kruskal-Wallis" results table?
        3. Do you see a table for "Pairwise Comparisons - spray"?
        4. Are there values roughly matching Chi-sq=54.7 or p < .001?

        Return JSON:
        {
            "jamovi_visible": true/false,
            "kruskal_wallis_table_visible": true/false,
            "pairwise_table_visible": true/false,
            "correct_data_loaded": true/false
        }
        """
        
        try:
            vlm_result = query_vlm(images=frames + [final_frame], prompt=prompt)
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("jamovi_visible"): vlm_score += 5
            if parsed.get("kruskal_wallis_table_visible"): vlm_score += 5
            if parsed.get("pairwise_table_visible"): vlm_score += 5
            if parsed.get("correct_data_loaded"): vlm_score += 5
            
            feedback_parts.append(f"VLM verified visual elements: {vlm_score}/20")
            
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            # Fallback: if we have strong file evidence, give some partial credit
            if score >= 50:
                vlm_score += 10
                feedback_parts.append("VLM failed but file evidence is strong.")

    score += vlm_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }