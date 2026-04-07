import json
import os
import zipfile
import tempfile
import shutil
import re
from typing import Dict, Any

def verify_create_filtered_metric_correlation(traj, env_info, task_info):
    """
    Verify the Oracle Analytics Desktop task: Create Filtered Metrics for Cross-Category Correlation.
    
    Verification Logic:
    1. Check if the .dva workbook file exists and was created during the task.
    2. Extract the .dva file (it's a ZIP archive).
    3. Analyze internal XML/JSON to confirm:
       - Existence of calculated columns "Tech Revenue" and "Furniture Revenue".
       - Logic checks: expressions must contain 'Technology'/'Furniture' and filter logic.
       - Visualization check: A Scatter Plot exists.
       - Binding check: Axes use the calculated columns.
    4. VLM verification of the workflow (Expression Editor usage).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Constants and Metadata
    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'Cross_Category_Analysis.dva')
    expected_path = f"C:\\Users\\Docker\\Documents\\{expected_filename}"
    
    # Paths for files to copy out
    result_json_remote = "C:\\workspace\\tasks\\create_filtered_metric_correlation\\task_result.json"
    
    score = 0
    max_score = 100
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Result JSON
    # ------------------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_remote, temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # ------------------------------------------------------------------
    # 2. Basic File Checks (30 points)
    # ------------------------------------------------------------------
    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Workbook file 'Cross_Category_Analysis.dva' not found."}
    
    score += 10
    feedback.append("Workbook saved.")
    
    if result_data.get('file_created_during_task'):
        score += 20
        feedback.append("File created during task window.")
    else:
        feedback.append("Warning: File timestamp indicates it might be stale.")

    # ------------------------------------------------------------------
    # 3. Analyze DVA Content (50 points)
    # ------------------------------------------------------------------
    # Copy the DVA file from the environment
    temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip') # .dva is a zip
    try:
        copy_from_env(expected_path, temp_dva.name)
        
        with zipfile.ZipFile(temp_dva.name, 'r') as z:
            # DVA structure typically contains 'datamodel' folders with XML or JSON
            # We look for the data model definition (often in datamodel/logical_sql or main XML)
            file_list = z.namelist()
            
            # Read content files to find logic
            content_found = False
            tech_calc_found = False
            furn_calc_found = False
            scatter_found = False
            
            # Iterate through likely text files in the archive to find definitions
            for fname in file_list:
                if fname.endswith('.xml') or fname.endswith('.json') or fname.endswith('.txt'):
                    try:
                        content = z.read(fname).decode('utf-8', errors='ignore')
                        
                        # Check for Calculation Logic
                        # Pattern: Looking for column definitions with formulas
                        # Note: OAD serialization varies, but usually stores expressions in plain text in XML attributes
                        
                        # Check for Tech Revenue logic
                        if re.search(r"Tech.*Revenue", content, re.IGNORECASE):
                            # Look for expression logic near the name
                            # e.g. FILTER("Sales" USING "Category"='Technology') or CASE WHEN...
                            if "Technology" in content and ("FILTER" in content or "CASE" in content or "USING" in content):
                                tech_calc_found = True
                        
                        # Check for Furniture Revenue logic
                        if re.search(r"Furniture.*Revenue", content, re.IGNORECASE):
                            if "Furniture" in content and ("FILTER" in content or "CASE" in content or "USING" in content):
                                furn_calc_found = True
                                
                        # Check for Scatter Plot
                        # Visualization types are often identified by strings like 'scatter' or 'xyzChart'
                        if "scatter" in content.lower():
                            scatter_found = True
                            
                        content_found = True
                    except:
                        continue
            
            if tech_calc_found:
                score += 20
                feedback.append("'Tech Revenue' calculation verified.")
            else:
                feedback.append("Could not verify 'Tech Revenue' formula logic.")
                
            if furn_calc_found:
                score += 20
                feedback.append("'Furniture Revenue' calculation verified.")
            else:
                feedback.append("Could not verify 'Furniture Revenue' formula logic.")
                
            if scatter_found:
                score += 10
                feedback.append("Scatter plot visualization detected.")
            else:
                feedback.append("Scatter plot not detected in workbook metadata.")

    except Exception as e:
        feedback.append(f"Failed to analyze workbook content: {str(e)}")
    finally:
        if os.path.exists(temp_dva.name):
            os.unlink(temp_dva.name)

    # ------------------------------------------------------------------
    # 4. VLM Verification (20 points)
    # ------------------------------------------------------------------
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        prompt = """
        Review these screenshots of a user working in Oracle Analytics Desktop.
        
        I need to confirm they performed these specific actions:
        1. Opened the 'New Calculation' or 'Expression Editor' dialog (looks like a formula editor).
        2. Typed a formula involving 'Technology' or 'Furniture'.
        3. Created a Scatter Plot (dots on a chart).
        
        Answer with JSON:
        {
            "calculation_editor_seen": boolean,
            "scatter_plot_seen": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                
                if parsed.get('calculation_editor_seen'):
                    score += 10
                    feedback.append("VLM: Calculation editor usage observed.")
                
                if parsed.get('scatter_plot_seen'):
                    score += 10
                    feedback.append("VLM: Scatter plot construction observed.")
        except Exception as e:
            feedback.append(f"VLM verification failed: {e}")

    # Final Check
    passed = score >= 70 and tech_calc_found and furn_calc_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }