#!/usr/bin/env python3
"""
Verifier for check_ancova_homogeneity_exam task.

Verifies:
1. Interaction term calculation accuracy (comparing agent report vs Python ground truth).
2. Correct statistical conclusion based on p-value.
3. Visual evidence of scatterplot with regression lines (VLM).
4. Visual evidence of interaction term in model builder/results (VLM).
"""

import json
import base64
import tempfile
import os
import re
import pandas as pd
import statsmodels.formula.api as smf
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_check_ancova_homogeneity_exam(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Check File Existence & Timestamp (Anti-Gaming)
    if result.get("project_exists") and result.get("project_created_during_task"):
        score += 10
        feedback.append("Project file saved.")
    else:
        feedback.append("Project file missing or not saved during task.")

    # 3. Parse Report Content
    report_exists = result.get("report_exists") and result.get("report_created_during_task")
    agent_b = None
    agent_p = None
    agent_conclusion = None

    if report_exists:
        try:
            content_b64 = result.get("report_content_b64", "")
            content = base64.b64decode(content_b64).decode('utf-8')
            
            # Regex parsing
            b_match = re.search(r"Interaction_B\s*=\s*([-+]?[0-9]*\.?[0-9]+)", content, re.IGNORECASE)
            p_match = re.search(r"Interaction_p\s*=\s*([<>]?\s*[-+]?[0-9]*\.?[0-9]+)", content, re.IGNORECASE)
            conc_match = re.search(r"Conclusion\s*=\s*(.+)", content, re.IGNORECASE)

            if b_match: agent_b = float(b_match.group(1))
            if p_match: 
                # Handle "< .001" notation if present, though likely concrete number here
                p_str = p_match.group(1).replace(" ", "")
                if "<" in p_str:
                    agent_p = 0.0001 # Treat as small
                else:
                    agent_p = float(p_str)
            if conc_match: agent_conclusion = conc_match.group(1).strip().lower()

        except Exception as e:
            feedback.append(f"Error parsing report: {e}")

    # 4. Calculate Ground Truth (Python)
    # Load dataset to compute actual stats
    # We need to copy the dataset from the container or rely on a local copy.
    # Since verifier runs on host, we assume standard dataset is available or we copy it out.
    # Ideally, we copy it out to ensure we use EXACTLY what the agent used.
    
    gt_b = 0.0
    gt_p = 1.0
    
    try:
        data_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        copy_from_env("/home/ga/Documents/Jamovi/ExamAnxiety.csv", data_temp.name)
        
        df = pd.read_csv(data_temp.name)
        
        # Jamovi uses simple coding or dummy coding? Default is usually dummy.
        # Model: Exam ~ Anxiety * Gender
        # Gender is categorical (Male/Female). Statsmodels handles this auto with C()
        model = smf.ols("Exam ~ Anxiety * C(Gender)", data=df).fit()
        
        # Find interaction term. It usually looks like 'Anxiety:C(Gender)[T.Male]'
        # We need to be robust to reference level. The interaction magnitude is what matters.
        interaction_keys = [k for k in model.params.keys() if ":" in k]
        if interaction_keys:
            key = interaction_keys[0]
            gt_b = model.params[key]
            gt_p = model.pvalues[key]
        else:
            feedback.append("Error: Could not compute ground truth interaction.")
        
        os.unlink(data_temp.name)
        
    except Exception as e:
        # Fallback hardcoded values for Exam Anxiety dataset (Field, 2013)
        # Interaction is typically non-significant in this specific dataset demo
        # Exam ~ Anxiety + Gender + Anxiety:Gender
        # B approx 0.35, p > 0.05 usually.
        # Let's rely on the dynamic calc above, but log error if it fails
        feedback.append(f"Ground truth calculation failed: {e}")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

    # 5. Score Numerical Accuracy
    if agent_b is not None:
        # Check absolute difference or relative error
        # Interaction coefficient can be small, so absolute tolerance is safer
        if abs(agent_b - gt_b) < 0.1: # Generous tolerance for rounding
            score += 15
            feedback.append(f"Interaction B correct (Agent: {agent_b}, GT: {gt_b:.4f})")
        else:
            feedback.append(f"Interaction B incorrect (Agent: {agent_b}, GT: {gt_b:.4f})")
    
    if agent_p is not None:
        if abs(agent_p - gt_p) < 0.01:
            score += 15
            feedback.append(f"Interaction p-value correct (Agent: {agent_p}, GT: {gt_p:.4f})")
        else:
            feedback.append(f"Interaction p-value incorrect (Agent: {agent_p}, GT: {gt_p:.4f})")

    # 6. Score Conclusion
    # Homogeneity assumption met if p > 0.05 (Interaction NOT significant)
    # Assumption violated if p <= 0.05
    gt_met = gt_p > 0.05
    if agent_conclusion:
        if ("met" in agent_conclusion and gt_met) or ("violated" in agent_conclusion and not gt_met):
            score += 10
            feedback.append("Conclusion correct.")
        else:
            feedback.append(f"Conclusion incorrect (GT p={gt_p:.3f}, Assumption {'Met' if gt_met else 'Violated'}).")

    # 7. VLM Verification (Visuals)
    # We check: 
    # A) Scatterplot with regression lines
    # B) Interaction term in Results table
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images_to_check = frames + ([final_screen] if final_screen else [])
    
    prompt = """
    Analyze these screenshots of Jamovi.
    I am looking for two things:
    1. A SCATTERPLOT showing 'Exam' vs 'Anxiety', with points grouped by 'Gender' (two colors) AND regression lines drawn for each group.
    2. A LINEAR REGRESSION RESULT table that lists an INTERACTION term (e.g., 'Anxiety ✻ Gender', 'Anxiety * Gender', or 'Anxiety:Gender').
    
    Return JSON:
    {
      "scatterplot_visible": boolean,
      "regression_lines_visible": boolean,
      "interaction_term_visible": boolean,
      "interaction_term_text": "text if seen"
    }
    """
    
    vlm_res = query_vlm(prompt=prompt, images=images_to_check)
    
    if vlm_res and vlm_res.get("success"):
        parsed = vlm_res.get("parsed", {})
        if parsed.get("scatterplot_visible"):
            score += 10
            feedback.append("Scatterplot detected.")
            if parsed.get("regression_lines_visible"):
                score += 10
                feedback.append("Regression lines detected.")
            else:
                feedback.append("Scatterplot found but missing regression lines.")
        
        if parsed.get("interaction_term_visible"):
            score += 20
            feedback.append(f"Interaction term detected visually ({parsed.get('interaction_term_text')}).")
        else:
            feedback.append("Interaction term not visible in results.")
    else:
        feedback.append("VLM verification failed.")

    # 8. Final Check
    passed = score >= 60 and (agent_p is not None and abs(agent_p - gt_p) < 0.05)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }