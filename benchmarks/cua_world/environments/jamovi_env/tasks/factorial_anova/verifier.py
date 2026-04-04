#!/usr/bin/env python3
"""
Verifier for factorial_anova task.

Checks:
1. Jamovi project file (.omv) created and valid.
2. Text report created containing correct F-statistics and p-values.
   - Requires 'dose' to be treated as categorical (F ~ 92.00).
   - If 'dose' is continuous (ANCOVA), F will differ, detecting error.
3. VLM verification of trajectory (ANOVA panel usage).
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_factorial_anova(traj, env_info, task_info):
    # 1. Setup and imports
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Metadata
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {
        "f_supp": 15.57,
        "f_dose": 92.00,
        "f_interaction": 4.11
    })
    
    # 3. Fetch Result JSON from container
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution metadata"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 4. Fetch Report Content from container
    report_content = ""
    if task_result.get("report_exists"):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/anova_report_content.txt", temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                report_content = f.read()
        except Exception as e:
            logger.error(f"Failed to load report content: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # =========================================================
    # SCORING CRITERIA
    # =========================================================
    score = 0
    feedback_log = []
    
    # Criterion 1: Project File Created (10 pts)
    # Anti-gaming: Must be > 1KB and created during task
    if task_result.get("project_exists") and task_result.get("project_created_during_task"):
        if task_result.get("project_size_bytes", 0) > 1000:
            score += 10
            feedback_log.append("Project file saved successfully.")
        else:
            feedback_log.append("Project file exists but is empty/too small.")
    else:
        feedback_log.append("Project file not found or not created during task.")

    # Criterion 2: Report File Created (5 pts)
    if task_result.get("report_exists") and task_result.get("report_created_during_task"):
        score += 5
        feedback_log.append("Report file created.")
    else:
        feedback_log.append("Report file missing.")

    # Criterion 3: Content Accuracy (55 pts)
    # Parse numbers from report_content
    # Expected: F(supp) ~ 15.57, F(dose) ~ 92.00, F(supp*dose) ~ 4.11
    
    # Regex to find floating point numbers associated with keywords
    # We look for patterns like "supp: F=15.57" or "supp ... 15.57"
    # This is lenient on formatting but strict on values.
    
    # Helper to find closest number in text to target
    def find_match(text, target, tolerance=2.0):
        # Find all floats
        floats = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", text)]
        for f in floats:
            if abs(f - target) <= tolerance:
                return f
        return None

    # We try to split text by sections if possible, otherwise search whole text
    lower_text = report_content.lower()
    
    # 3a. Supp Effect (15 pts)
    supp_f = find_match(lower_text, ground_truth['f_supp'], tolerance=2.0)
    if supp_f:
        score += 15
        feedback_log.append(f"Correct 'supp' F-statistic found ({supp_f}).")
    else:
        feedback_log.append(f"Missing or incorrect 'supp' F-statistic (Expected ~{ground_truth['f_supp']}).")

    # 3b. Dose Effect (20 pts)
    # CRITICAL: If dose was left as continuous, F will be different.
    # Typically F_dose_cont ≈ 100+ or different df. 
    # With categorical (correct), F(2,54) = 92.00.
    dose_f = find_match(lower_text, ground_truth['f_dose'], tolerance=5.0)
    if dose_f:
        score += 20
        feedback_log.append(f"Correct 'dose' F-statistic found ({dose_f}).")
    else:
        feedback_log.append(f"Missing or incorrect 'dose' F-statistic (Expected ~{ground_truth['f_dose']}). Did you set 'dose' to Nominal?")

    # 3c. Interaction Effect (20 pts)
    inter_f = find_match(lower_text, ground_truth['f_interaction'], tolerance=1.5)
    if inter_f:
        score += 20
        feedback_log.append(f"Correct Interaction F-statistic found ({inter_f}).")
    else:
        feedback_log.append(f"Missing or incorrect Interaction F-statistic (Expected ~{ground_truth['f_interaction']}).")

    # Criterion 4: VLM Verification (30 pts)
    # Check if ANOVA table was visible on screen using trajectory
    # This proves they actually used the software vs just calculating in Python/R
    
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        images = frames + ([final_screen] if final_screen else [])
        
        if images:
            prompt = """
            Analyze these screenshots of a Jamovi statistical software session.
            
            Look for:
            1. An ANOVA results table (look for 'ANOVA', 'Sum of Squares', 'F', 'p').
            2. A data spreadsheet (rows and columns of numbers).
            3. The 'ToothGrowth' dataset loaded (look for variable names like 'len', 'supp', 'dose').
            
            Return JSON:
            {
                "anova_table_visible": boolean,
                "data_grid_visible": boolean,
                "is_jamovi": boolean
            }
            """
            
            res = query_vlm(images=images, prompt=prompt)
            if res.get('success'):
                parsed = res.get('parsed', {})
                if parsed.get('is_jamovi') and parsed.get('anova_table_visible'):
                    vlm_score = 30
                    feedback_log.append("VLM verified ANOVA table visibility.")
                elif parsed.get('is_jamovi'):
                    vlm_score = 10
                    feedback_log.append("VLM verified Jamovi usage, but ANOVA table not clearly identified.")
            else:
                feedback_log.append("VLM verification failed (API error). Defaulting to partial credit.")
                vlm_score = 15
    except Exception as e:
        logger.error(f"VLM error: {e}")
        vlm_score = 0
        feedback_log.append("VLM verification skipped due to error.")

    score += vlm_score

    # Final tally
    passed = (score >= 60) and (dose_f is not None)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_log)
    }