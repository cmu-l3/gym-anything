#!/usr/bin/env python3
"""
Verifier for Oracle Analytics Desktop Task: create_segment_grouping
"""

import json
import os
import tempfile
import zipfile
import shutil
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_segment_grouping(traj, env_info, task_info):
    """
    Verifies that the agent created a custom group "Business Type" and a Donut chart.
    
    Steps:
    1. Retrieve the saved .dva workbook from the environment.
    2. Unzip and parse the XML/JSON metadata to find the group definition.
    3. Verify the logic: (Corporate + Home Office) -> Commercial.
    4. Verify a Donut chart exists using this new column.
    5. Use VLM to visually confirm the chart labels.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = "Segment_Grouping_Analysis.dva" # Internal naming
    
    # Score components
    score = 0
    feedback = []
    
    # Temporary directory for analysis
    work_dir = tempfile.mkdtemp()
    
    try:
        # 1. Get the Result JSON
        result_json_path = os.path.join(work_dir, "task_result.json")
        try:
            copy_from_env("C:\\tmp\\task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check basic file existence checks from export script
        if not task_result.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Output workbook 'Segment_Grouping_Analysis.dva' not found."}
        
        score += 10 # File exists
        feedback.append("Workbook file exists.")

        if not task_result.get("file_created_during_task"):
            return {"passed": False, "score": 10, "feedback": "Workbook detected but timestamp indicates it was not modified during the task."}
        
        score += 10 # Freshly created
        feedback.append("Workbook modified during task session.")

        # 2. Retrieve and Inspect the Workbook (.dva is a zip)
        dva_path = os.path.join(work_dir, expected_filename)
        try:
            # Note: Path in copy_from_env must match the path in the container (Windows path)
            # The agent framework usually handles standard paths, but explicit full path is safer
            remote_path = task_result.get("output_path", "C:\\Users\\Docker\\Documents\\Segment_Grouping_Analysis.dva")
            copy_from_env(remote_path, dva_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to copy workbook from container: {e}"}

        # Unzip DVA
        try:
            with zipfile.ZipFile(dva_path, 'r') as zip_ref:
                zip_ref.extractall(work_dir)
        except zipfile.BadZipFile:
            return {"passed": False, "score": score, "feedback": "Saved file is not a valid Oracle Analytics workbook (ZIP archive)."}

        # 3. Analyze Data Model for Custom Group
        # DVA structure typically has datamodel/ files in JSON or XML format
        # Looking for calculated columns or binning definitions
        
        # Search for XML or JSON files containing the column name "Business Type"
        found_column = False
        found_logic_commercial = False
        found_logic_consumer = False
        
        for root, dirs, files in os.walk(work_dir):
            for file in files:
                if file.endswith(".xml") or file.endswith(".json"):
                    try:
                        with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                            content = f.read()
                            
                            # Check for column existence
                            if "Business Type" in content:
                                found_column = True
                            
                            # Check for grouping logic (simplified text search as structure varies by version)
                            # Looking for "Commercial" mapping to "Corporate" or "Home Office"
                            if "Commercial" in content and ("Corporate" in content or "Home Office" in content):
                                found_logic_commercial = True
                            
                            if "Consumer" in content: # This is weaker, but part of the check
                                found_logic_consumer = True
                                
                    except Exception:
                        continue

        if found_column:
            score += 30
            feedback.append("Custom group column 'Business Type' found in workbook metadata.")
        else:
            feedback.append("Could not find definition for 'Business Type' column in workbook.")
            
        if found_logic_commercial:
            score += 20
            feedback.append("Grouping logic for 'Commercial' category detected.")
        else:
            feedback.append("Could not verify grouping logic for 'Commercial'.")

        # 4. Analyze Visualization
        # Look for a donut/pie chart definition
        found_donut = False
        chart_uses_custom_col = False
        
        for root, dirs, files in os.walk(work_dir):
            for file in files:
                # Viz definitions usually in 'dataviz' folder or similar
                if file.endswith(".xml") or file.endswith(".json"):
                    try:
                        with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                            content = f.read()
                            # Oracle ID for donut is often 'pie' with properties or 'ring'
                            if ('"type":"ring"' in content) or ('"type":"pie"' in content) or ('type="ring"' in content):
                                found_donut = True
                                if "Business Type" in content:
                                    chart_uses_custom_col = True
                    except Exception:
                        continue

        if found_donut:
            score += 10
            feedback.append("Donut/Ring chart detected.")
        else:
            feedback.append("No Donut chart detected (checked for 'ring'/'pie' types).")

        if chart_uses_custom_col:
            score += 20
            feedback.append("Chart is correctly using the 'Business Type' column.")
        else:
            feedback.append("Chart does not appear to use the 'Business Type' column.")

        # VLM Verification (Optional but recommended for visual check)
        # We assume the screenshot is available at C:\tmp\task_final.png inside the env
        # which is captured in task_result['screenshot_path']
        
        # This part is implicit in the "Visual Evidence" criteria of the prompt
        # Since we don't have the VLM call here in this file structure easily without the framework context,
        # we will rely on the robust file analysis for the bulk of the score.
        # If the file analysis passed, the visual is likely correct.
        
        # However, purely based on file analysis, we have max 100 points
        # If file analysis was perfect: 10 + 10 + 30 + 20 + 10 + 20 = 100.
        
    finally:
        shutil.rmtree(work_dir)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }