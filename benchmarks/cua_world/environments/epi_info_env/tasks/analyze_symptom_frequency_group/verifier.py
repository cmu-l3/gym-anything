#!/usr/bin/env python3
"""
Verifier for analyze_symptom_frequency_group task.

Criteria:
1. Output HTML file exists and was created during the task.
2. The HTML file contains the correct frequency counts for the symptom group.
3. Verification relies on parsing the HTML output and comparing with ground truth generated during setup.
"""

import json
import os
import tempfile
import logging
import re
from bs4 import BeautifulSoup

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_symptom_frequency_group(traj, env_info, task_info):
    """
    Verifies that the agent correctly defined a group variable and produced a frequency report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    task_result_remote = "C:\\workspace\\task_result.json"
    output_remote = "C:\\Users\\Docker\\Documents\\TaskData\\symptom_report.htm"
    ground_truth_remote = "C:\\GroundTruth\\symptoms_ground_truth.json"

    score = 0
    max_score = 100
    feedback = []

    # Temporary files
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.htm').name
    temp_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name

    try:
        # 1. Get Task Result Metadata
        try:
            copy_from_env(task_result_remote, temp_result)
            with open(temp_result, 'r') as f:
                result_meta = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result metadata: {str(e)}"}

        # Check existence
        if not result_meta.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Output HTML report not found."}
        
        score += 10
        feedback.append("Output file exists.")

        # Check timestamp
        if not result_meta.get("file_created_during_task", False):
             feedback.append("Warning: Output file timestamp indicates it wasn't created during this session.")
             # We might penalize heavily or fail, but let's check content first.
        else:
            score += 10
            feedback.append("Output file created during task.")

        # 2. Get Ground Truth
        try:
            copy_from_env(ground_truth_remote, temp_truth)
            with open(temp_truth, 'r') as f:
                ground_truth = json.load(f)
        except Exception as e:
            # If we can't get ground truth, we can't verify accuracy.
            return {"passed": False, "score": score, "feedback": f"System error: Could not retrieve ground truth data. {str(e)}"}

        # 3. Analyze Output Content
        try:
            copy_from_env(output_remote, temp_output)
            with open(temp_output, 'r', encoding='utf-8', errors='ignore') as f:
                html_content = f.read()
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve output file content. {str(e)}"}

        # Parse HTML
        soup = BeautifulSoup(html_content, 'html.parser')
        text_content = soup.get_text()

        # Check for Group Variable usage indicators
        # Epi Info Group Frequency tables usually have a header like "Frequency of Group <VarName>"
        if "Frequency of Group" in text_content or "SymptomProfile" in text_content:
            score += 20
            feedback.append("Evidence of Group Variable analysis found.")
        else:
            feedback.append("Could not find explicit 'Group' analysis headers. Checking data values...")

        # Verify Counts
        # We look for the symptom names and their corresponding 'Yes' (1) counts in the table.
        # Epi Info output tables for groups usually list: Variable, Value, Frequency, Percent...
        # Since these are binary 1/0, we look for the count associated with value '1' for each symptom.
        
        # This parsing is tricky because HTML structure varies. 
        # Strategy: Look for the number of '1's (Present) for each symptom.
        # We will search specifically for the pattern of the symptom name near its count.
        
        matches = 0
        total_symptoms = len(ground_truth)
        
        for symptom, expected_count in ground_truth.items():
            # Regex to find symptom followed by expected count within reasonable distance
            # Or just check if the number appears.
            # A more robust check:
            # Look for rows containing the symptom name.
            # Then look for the count in that row.
            
            # Simple heuristic: Does the document contain the symptom name AND the expected count?
            # And is the count not just a coincidence (like '50' appears but it's 50%)?
            # This is hard to perfect without visual layout, but usually 'Count' is a distinct integer.
            
            symptom_found = symptom in text_content
            count_found = str(expected_count) in text_content
            
            if symptom_found and count_found:
                matches += 1
            else:
                feedback.append(f"Missing match for {symptom} (Expected: {expected_count})")

        # Scoring accuracy
        accuracy_score = (matches / total_symptoms) * 60
        score += accuracy_score
        
        if matches == total_symptoms:
            feedback.append("All symptom counts match ground truth.")
        elif matches > 0:
            feedback.append(f"Matched {matches}/{total_symptoms} symptom counts.")
        else:
            feedback.append("No symptom counts could be verified in the output.")

    finally:
        # Cleanup
        for f in [temp_result, temp_output, temp_truth]:
            if os.path.exists(f):
                os.unlink(f)

    passed = score >= 80
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }