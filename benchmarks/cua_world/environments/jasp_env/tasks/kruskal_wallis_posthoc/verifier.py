#!/usr/bin/env python3
"""
Verifier for Kruskal-Wallis Nonparametric Test Task
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

# Import VLM utils (mocked if not available in dev environment)
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing without framework
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_kruskal_wallis_posthoc(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the Kruskal-Wallis task based on:
    1. Existence and valid timestamps of output files.
    2. Content of the text report (H statistic, p-value, post-hoc).
    3. VLM verification of the JASP workflow.
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    expected_H = ground_truth.get('H_statistic', 40.67)
    H_tolerance = ground_truth.get('H_tolerance', 1.0)
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    jasp_info = result.get('jasp_file', {})
    report_info = result.get('report_file', {})
    
    # 2. Check File Existence & Timestamps (Anti-Gaming)
    
    # Check JASP file (Evidence of tool usage)
    if jasp_info.get('exists') and jasp_info.get('created_during_task'):
        if jasp_info.get('size', 0) > 2000:  # >2KB implies content
            score += 10
            feedback_parts.append("JASP analysis file saved.")
        else:
            score += 5
            feedback_parts.append("JASP file saved but appears empty.")
    elif jasp_info.get('exists'):
        feedback_parts.append("JASP file exists but was not created during this task (stale?).")
    else:
        feedback_parts.append("JASP analysis file not found.")

    # Check Report file
    report_content = report_info.get('content_preview', "")
    if report_info.get('exists') and report_info.get('created_during_task'):
        score += 10
        feedback_parts.append("Report text file created.")
    else:
        feedback_parts.append("Report text file not found.")

    # 3. Analyze Report Content (Parsing)
    # Expected format: "Kruskal-Wallis H: 40.67", "p-value: < .001", etc.
    
    # Extract H Statistic
    h_match = re.search(r"Kruskal-Wallis H:\s*([\d\.]+)", report_content, re.IGNORECASE)
    if h_match:
        try:
            h_val = float(h_match.group(1))
            if abs(h_val - expected_H) <= H_tolerance:
                score += 20
                feedback_parts.append(f"H statistic correct ({h_val}).")
            else:
                feedback_parts.append(f"H statistic incorrect (got {h_val}, expected ~{expected_H}).")
        except ValueError:
            feedback_parts.append("Could not parse H statistic value.")
    else:
        feedback_parts.append("H statistic not found in report.")

    # Extract Degrees of Freedom
    df_match = re.search(r"Degrees of Freedom:\s*(\d+)", report_content, re.IGNORECASE)
    if df_match:
        if int(df_match.group(1)) == 2:
            score += 5
            feedback_parts.append("Degrees of freedom correct (2).")
        else:
            feedback_parts.append("Degrees of freedom incorrect.")
    
    # Extract p-value
    # Look for scientific notation, < 0.001, or 0.000
    p_match = re.search(r"p-value:\s*([<>\d\.e-]+)", report_content, re.IGNORECASE)
    if p_match:
        p_str = p_match.group(1)
        if '<' in p_str or 'e-' in p_str or (p_str.replace('.','').isdigit() and float(p_str) < 0.01):
            score += 10
            feedback_parts.append("p-value indicates significance.")
        else:
            feedback_parts.append(f"p-value reported as {p_str} (check significance).")
    
    # Check Post-Hoc Comparisons
    # All dose pairs (0.5 vs 1, 0.5 vs 2, 1 vs 2) are significant in this dataset
    posthoc_score = 0
    comparisons = re.findall(r"Pairwise Comparison.*:\s*(\w[\w\s]*)", report_content, re.IGNORECASE)
    
    significant_keywords = ["significant", "yes", "true", "p < .05", "differ"]
    
    # Simple check: Count how many lines contain "significant" (excluding "not significant" if possible)
    # But regex above captures the status.
    sig_count = 0
    for comp in comparisons:
        if any(k in comp.lower() for k in significant_keywords) and "not" not in comp.lower():
            sig_count += 1
            
    # We expect 3 significant comparisons
    if sig_count >= 3:
        score += 24
        feedback_parts.append("All post-hoc comparisons correctly identified as significant.")
    elif sig_count > 0:
        score += 8 * sig_count
        feedback_parts.append(f"identified {sig_count}/3 post-hoc comparisons correctly.")
    
    # Check Conclusion
    if re.search(r"Conclusion:.+", report_content, re.IGNORECASE):
        score += 6
        feedback_parts.append("Conclusion section present.")

    # 4. VLM Verification (Trajectory Analysis)
    # We want to see:
    # - Variable type changed (icon in data grid)
    # - Kruskal-Wallis Analysis output table
    
    frames = sample_trajectory_frames(traj, n=8)
    final_screen = get_final_screenshot(traj)
    images_to_check = frames + ([final_screen] if final_screen else [])
    
    if images_to_check:
        vlm_prompt = """
        Review these screenshots of a JASP statistical analysis session.
        Check for two specific things:
        1. Did the user open the 'Kruskal-Wallis Test' (or Kruskal-Wallis ANOVA)? Look for a results table with that title.
        2. Did the user change the variable type for 'dose'? In the data grid, the icon next to 'dose' should look like a bar chart (Ordinal) or Venn diagram (Nominal), NOT a ruler (Scale).
        
        Return JSON:
        {
            "kruskal_wallis_visible": boolean,
            "variable_type_changed": boolean,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_res = query_vlm(images=images_to_check, prompt=vlm_prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("kruskal_wallis_visible"):
                score += 10
                feedback_parts.append("VLM confirmed Kruskal-Wallis table visible.")
            
            if parsed.get("variable_type_changed"):
                score += 5
                feedback_parts.append("VLM confirmed variable type change.")
        else:
            feedback_parts.append("VLM verification failed (technical error).")
            # Grant partial credit if programmatic checks passed strongly
            if score >= 50:
                score += 10
                feedback_parts.append("Granting VLM fallback points due to strong programmatic evidence.")

    # 5. Final Result
    passed = score >= 60 and ("H statistic correct" in " ".join(feedback_parts) or score >= 80)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }