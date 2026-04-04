#!/usr/bin/env python3
import json
import os
import tempfile
import pandas as pd
import re

def verify_feature_engineering_survival_analysis(traj, env_info, task_info):
    """
    Verifies that the agent correctly calculated survival rates for Children, Women, and Men.
    
    Strategy:
    1. Calculate Ground Truth: Load the raw dataset and apply the logic (Age < 16, etc.) 
       to compute the exact survival percentages.
    2. Check Outputs: Verify the .omv file exists (proof of using Jamovi).
    3. Verify Report: Parse the text file submitted by the agent and compare with ground truth.
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # ------------------------------------------------------------------
    # 1. Retrieve Task Results JSON
    # ------------------------------------------------------------------
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {str(e)}"}

    # ------------------------------------------------------------------
    # 2. Retrieve Agent's Report
    # ------------------------------------------------------------------
    agent_report_content = ""
    if task_result.get("report_exists"):
        with tempfile.NamedTemporaryFile(suffix='.txt') as f:
            try:
                copy_from_env(task_result["report_path"], f.name)
                f.seek(0)
                agent_report_content = f.read().decode('utf-8', errors='ignore')
            except Exception as e:
                return {"passed": False, "score": 0, "feedback": f"Report file exists but could not be read: {str(e)}"}
    else:
        return {"passed": False, "score": 0, "feedback": "The required report file 'survival_rates.txt' was not created."}

    # ------------------------------------------------------------------
    # 3. Retrieve Dataset for Ground Truth Calculation
    # ------------------------------------------------------------------
    # We copy the actual dataset used in the env to ensure 100% consistency
    dataset_path = task_result.get("dataset_path", "/home/ga/Documents/Jamovi/TitanicSurvival.csv")
    
    with tempfile.NamedTemporaryFile(suffix='.csv') as f:
        try:
            copy_from_env(dataset_path, f.name)
            # Load data using pandas
            df = pd.read_csv(f.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve dataset for verification: {str(e)}"}

    # ------------------------------------------------------------------
    # 4. Calculate Ground Truth
    # ------------------------------------------------------------------
    # Logic:
    # IF Age is Missing -> Exclude (Jamovi default behavior for computed variables using that column)
    # IF Age < 16 -> Child
    # ELSE IF Sex == 'female' -> Woman
    # ELSE -> Man
    
    # Drop rows where Age is NaN
    df_clean = df.dropna(subset=['age']).copy()
    
    def classify_person(row):
        if row['age'] < 16:
            return 'Child'
        elif row['sex'] == 'female':
            return 'Woman'
        else:
            return 'Man'
            
    df_clean['PersonType'] = df_clean.apply(classify_person, axis=1)
    
    # Calculate survival rates (survived='yes' / total)
    # 'survived' column usually contains "yes"/"no"
    ground_truth = {}
    for group in ['Child', 'Woman', 'Man']:
        group_data = df_clean[df_clean['PersonType'] == group]
        total = len(group_data)
        if total == 0:
            ground_truth[group] = 0.0
        else:
            survived_count = len(group_data[group_data['survived'] == 'yes'])
            percentage = (survived_count / total) * 100
            ground_truth[group] = percentage

    # ------------------------------------------------------------------
    # 5. Parse Agent Report
    # ------------------------------------------------------------------
    # Expected format: "Child survival rate: 45.2%"
    # We look for the keyword (Child/Woman/Man) and the first number following it.
    
    def parse_value(text, keyword):
        # Regex to find float/int near the keyword
        # Matches: "Child... 59.5" or "Child... 59.5%"
        pattern = re.compile(rf"{keyword}.*?(\d+\.?\d*)", re.IGNORECASE)
        match = pattern.search(text)
        if match:
            try:
                return float(match.group(1))
            except ValueError:
                return None
        return None

    agent_values = {
        'Child': parse_value(agent_report_content, 'Child'),
        'Woman': parse_value(agent_report_content, 'Woman'),
        'Man': parse_value(agent_report_content, 'Man')
    }

    # ------------------------------------------------------------------
    # 6. Scoring
    # ------------------------------------------------------------------
    score = 0
    feedback = []
    
    # Criterion 1: Project file exists (10 pts)
    if task_result.get("project_exists") and task_result.get("project_fresh"):
        score += 10
        feedback.append("Project file saved successfully.")
    else:
        feedback.append("Project file not saved or not new.")

    # Criteria 2, 3, 4: Accuracy of rates (30 pts each)
    tolerance = 1.0 # Allow +/- 1.0% rounding difference
    
    for group in ['Child', 'Woman', 'Man']:
        gt = ground_truth[group]
        agent_val = agent_values[group]
        
        if agent_val is not None:
            if abs(agent_val - gt) <= tolerance:
                score += 30
                feedback.append(f"{group} rate correct ({agent_val}% vs GT {gt:.1f}%).")
            else:
                feedback.append(f"{group} rate incorrect (Got {agent_val}%, Expected {gt:.1f}%).")
        else:
            feedback.append(f"{group} rate not found in report.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "ground_truth": ground_truth,
            "agent_values": agent_values
        }
    }