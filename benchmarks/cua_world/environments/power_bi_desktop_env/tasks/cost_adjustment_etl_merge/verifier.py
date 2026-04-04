#!/usr/bin/env python3
"""
Verifier for cost_adjustment_etl_merge task.

Verifies:
1. PBIX file creation and timestamp (Anti-gaming).
2. ETL logic: Checks DataMashup for "NestedJoin" and "ExpandTableColumn".
3. Data Model: Checks if "Corrected_Unit_Cost" exists in the schema.
4. Measure: Checks if "Corrected_Profit" is defined.
5. Visual: Checks for chart in layout.
"""

import json
import os
import tempfile
import zipfile
import logging
import re
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cost_adjustment_etl_merge(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # Prepare temp files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_pbix = tempfile.NamedTemporaryFile(delete=False, suffix='.zip').name # PBIX is a zip
    
    try:
        # 1. Retrieve Result JSON
        try:
            copy_from_env("C:/Windows/Temp/task_result.json", temp_json)
            with open(temp_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # Check basic file existence
        if not result_data.get('output_exists', False):
            return {"passed": False, "score": 0, "feedback": "Cost_Correction.pbix not found on Desktop."}
        
        score += 10 # File Saved
        feedback.append("File saved successfully.")

        if result_data.get('file_created_during_task', False):
             score += 5 # Bonus for timestamp check
        else:
            feedback.append("Warning: File timestamp is older than task start.")

        # 2. Retrieve PBIX File
        try:
            copy_from_env("C:/Users/Docker/Desktop/Cost_Correction.pbix", temp_pbix)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"File exists but could not be copied: {str(e)}"}

        # 3. Analyze PBIX Content
        try:
            with zipfile.ZipFile(temp_pbix, 'r') as z:
                file_list = z.namelist()
                
                # Check 3.1: DataMashup (ETL Logic)
                if 'DataMashup' in file_list:
                    mashup_data = z.read('DataMashup')
                    # Mashup is binary, but M code strings are visible
                    # Look for key Power Query steps
                    # "Table.NestedJoin" implies a merge
                    # "Table.ExpandTableColumn" implies expansion
                    mashup_str = str(mashup_data)
                    
                    if "sales_data.csv" in mashup_str and "product_costs.csv" in mashup_str:
                        score += 10
                        feedback.append("Data sources found in Query.")
                    
                    if "Table.NestedJoin" in mashup_str:
                        score += 30
                        feedback.append("Merge query (NestedJoin) detected.")
                    else:
                        feedback.append("Missing Merge Query step.")

                    if "Table.ExpandTableColumn" in mashup_str:
                        score += 20
                        feedback.append("Expand column step detected.")
                    else:
                        feedback.append("Missing Expand Column step.")
                else:
                    feedback.append("DataMashup not found in PBIX.")

                # Check 3.2: Measure and Column (DataModel check)
                # DataModel is binary. Searching for strings is a heuristic but works for verification.
                if 'DataModel' in file_list:
                    model_data = z.read('DataModel')
                    model_str = str(model_data)
                    # Use a very permissive encoding check (latin-1 or utf-16 usually in parts)
                    # We usually search for the names as byte sequences or just loose string matching
                    
                    # Check for Measure
                    if "Corrected_Profit" in str(model_data):
                        score += 15
                        feedback.append("Measure 'Corrected_Profit' found.")
                    else:
                        feedback.append("Measure 'Corrected_Profit' NOT found.")

                    # Check for Column usage (schema)
                    if "Corrected_Unit_Cost" in str(model_data):
                        # This confirms the column was loaded into the model
                        feedback.append("Column 'Corrected_Unit_Cost' loaded into model.")
                    else:
                        feedback.append("Column 'Corrected_Unit_Cost' NOT found in model.")

                # Check 3.3: Visuals (Report/Layout)
                if 'Report/Layout' in file_list:
                    layout_json = json.loads(z.read('Report/Layout').decode('utf-16-le'))
                    
                    # Recursive search for visual types
                    def find_visuals(obj):
                        visuals = []
                        if isinstance(obj, dict):
                            if 'visualType' in obj:
                                visuals.append(obj)
                            for k, v in obj.items():
                                visuals.extend(find_visuals(v))
                        elif isinstance(obj, list):
                            for item in obj:
                                visuals.extend(find_visuals(item))
                        return visuals

                    visuals = find_visuals(layout_json)
                    has_chart = any(v['visualType'] in ['clusteredBarChart', 'barChart', 'columnChart', 'clusteredColumnChart'] for v in visuals)
                    
                    if has_chart:
                        score += 10
                        feedback.append("Bar chart visual created.")
                    else:
                        feedback.append("No Bar chart visual found.")
                else:
                    feedback.append("Report Layout not found.")

        except zipfile.BadZipFile:
            return {"passed": False, "score": score, "feedback": "PBIX file is not a valid zip archive."}

    finally:
        if os.path.exists(temp_json): os.remove(temp_json)
        if os.path.exists(temp_pbix): os.remove(temp_pbix)

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }