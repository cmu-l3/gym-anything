#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_factorial_anova_interaction_plot(traj, env_info, task_info):
    """
    Verifies the Factorial ANOVA Interaction Plot task.
    
    Criteria:
    1. Result file (oj_dose2_mean.txt) exists and was created during task.
    2. Reported mean is approximately 26.06.
    3. Jamovi project file (.omv) was saved.
    4. VLM Verification:
       - 'dose' variable icon changed to Ordinal/Nominal.
       - Interaction plot visible.
       - ANOVA results visible.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_mean = metadata.get('expected_mean', 26.06)
    tolerance = metadata.get('tolerance', 0.1)

    # 1. Load JSON Result from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_log = []

    # 2. Check Files (Anti-Gaming)
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_created_during_task', False)
    project_exists = result.get('project_exists', False)
    project_fresh = result.get('project_created_during_task', False)

    if project_exists and project_fresh:
        score += 10
        feedback_log.append("Jamovi project file saved.")
    else:
        feedback_log.append("Jamovi project file missing or not saved during task.")

    if report_exists and report_fresh:
        score += 10
        feedback_log.append("Report file created.")
    else:
        feedback_log.append("Report file missing.")

    # 3. Verify Reported Value
    value_correct = False
    if report_exists:
        content = result.get('report_content', '').strip()
        try:
            # Extract float from string (handle potential extra text)
            import re
            numbers = re.findall(r"[-+]?\d*\.\d+|\d+", content)
            if numbers:
                val = float(numbers[0])
                if abs(val - expected_mean) <= tolerance:
                    score += 30
                    value_correct = True
                    feedback_log.append(f"Reported mean {val} is correct (Target: {expected_mean}).")
                else:
                    feedback_log.append(f"Reported mean {val} is incorrect (Target: {expected_mean}). Did you treat 'dose' as Continuous?")
            else:
                feedback_log.append("Could not parse number from report file.")
        except Exception:
            feedback_log.append("Error parsing report content.")

    # 4. VLM Verification (Trajectory Analysis)
    # We need to verify the variable type change and the plot generation
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # Prompt for variable type check (dose icon)
    # Continuous icon is a ruler. Ordinal is a bar chart. Nominal is Venn circles.
    vlm_prompt = """
    Analyze these screenshots of Jamovi.
    
    1. Look at the 'dose' variable in the data panel or variable list. What is its icon?
       - Ruler (Continuous)?
       - Bar chart (Ordinal)?
       - Three circles/Venn (Nominal)?
       
    2. Do you see an ANOVA analysis output panel?
    
    3. Do you see an 'Estimated Marginal Means' interaction plot?
       - It should show lines connecting points (representing supp x dose interaction).
       
    4. Do you see a table of 'Estimated Marginal Means' values?
    
    Answer JSON:
    {
      "dose_is_categorical": boolean, // True if Ordinal/Nominal icons seen, False if Ruler seen
      "anova_visible": boolean,
      "interaction_plot_visible": boolean,
      "marginal_means_table_visible": boolean
    }
    """
    
    vlm_result = query_vlm(
        images=frames + [final_screen],
        prompt=vlm_prompt
    )
    
    vlm_data = vlm_result.get('parsed', {})
    
    if vlm_data.get('dose_is_categorical'):
        score += 20
        feedback_log.append("VLM: Correctly identified 'dose' variable set to Categorical (Ordinal/Nominal).")
    else:
        feedback_log.append("VLM: 'dose' variable appears to remain Continuous (Ruler icon).")
        
    if vlm_data.get('anova_visible'):
        score += 10
        feedback_log.append("VLM: ANOVA output visible.")
        
    if vlm_data.get('interaction_plot_visible'):
        score += 10
        feedback_log.append("VLM: Interaction plot visible.")
        
    if vlm_data.get('marginal_means_table_visible'):
        score += 10
        feedback_log.append("VLM: Marginal means table visible.")

    # Final Evaluation
    passed = (score >= 70) and value_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }