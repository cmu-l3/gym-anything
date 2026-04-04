#!/usr/bin/env python3
import json
import os
import zipfile
import tempfile
import shutil

def verify_multivariate_scatterplot_matrix(traj, env_info, task_info):
    """
    Verifies that the agent created a Scatterplot Matrix in Jamovi with:
    - Variables: Exam, Anxiety, Revise
    - Group: Gender
    - Plots: Density (diagonal), Linear (regression)
    - Correlations enabled
    """
    # 1. Setup and retrieve files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    expected_vars = set(["Exam", "Anxiety", "Revise"])
    expected_group = "Gender"
    
    # Temp paths
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    omv_path = os.path.join(temp_dir, "output.omv")
    
    score = 0
    feedback = []
    
    try:
        # 2. Parse execution result
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            exec_result = json.load(f)
            
        if not exec_result.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Output file ExamAnxiety_Matrix.omv not found."}
            
        if not exec_result.get("file_created_during_task"):
            feedback.append("Warning: File timestamp suggests it wasn't created during this session.")
        else:
            score += 10 # File created
            
        # 3. Analyze OMV file content
        copy_from_env(exec_result["output_path"], omv_path)
        
        # .omv files are ZIP archives containing JSON analysis definitions
        if not zipfile.is_zipfile(omv_path):
             return {"passed": False, "score": score, "feedback": "Output file is not a valid OMV archive."}

        analysis_found = False
        correct_vars = False
        correct_group = False
        density_on = False
        linear_on = False
        corrs_on = False
        
        with zipfile.ZipFile(omv_path, 'r') as z:
            # Iterate through files to find analysis definitions
            # Usually in 'index.html' or specific 'analysis' files inside numbered folders
            # We look for any JSON that looks like a scatterplot matrix definition
            
            for filename in z.namelist():
                # Jamovi analysis settings are often in a file simply named 'analysis' (no extension) or similar in subfolders
                if filename.endswith("analysis") or filename.endswith("00"): 
                    try:
                        with z.open(filename) as f:
                            content = f.read().decode('utf-8', errors='ignore')
                            # It might be JSON
                            try:
                                data = json.loads(content)
                            except json.JSONDecodeError:
                                continue
                                
                            # Check if this is a scatterplot matrix
                            # The options key usually contains the settings
                            options = data.get("options", {})
                            
                            # Check for variable presence (heuristic as keys vary by module version)
                            # Standard Jamovi 'scat' analysis
                            vars_in_analysis = options.get("vars", [])
                            group_in_analysis = options.get("group", None)
                            
                            # Verify variables
                            # vars_in_analysis might be a list of dicts or strings
                            current_vars = set()
                            if isinstance(vars_in_analysis, list):
                                for v in vars_in_analysis:
                                    if isinstance(v, str):
                                        current_vars.add(v)
                                    elif isinstance(v, dict) and "name" in v:
                                        current_vars.add(v["name"])
                            
                            # Check if this analysis roughly matches our target variables
                            # We check intersection to see if this is the right analysis block
                            if expected_vars.issubset(current_vars):
                                analysis_found = True
                                correct_vars = True
                                
                                # Check Grouping
                                if group_in_analysis == expected_group:
                                    correct_group = True
                                
                                # Check Plots options
                                # "dens" -> true/false, "line" -> "linear"/"none", "corrs" -> true/false
                                plots_opts = options.get("plots", {}) 
                                # Sometimes flattened in newer versions, check root options too
                                
                                # Density
                                if options.get("dens") is True or plots_opts.get("dens") is True:
                                    density_on = True
                                    
                                # Regression Line
                                line_setting = options.get("line") or plots_opts.get("line")
                                if line_setting == "linear":
                                    linear_on = True
                                    
                                # Correlations
                                if options.get("corrs") is True or plots_opts.get("corrs") is True:
                                    corrs_on = True
                                
                                break # Found the relevant analysis
                    except Exception:
                        continue

        # 4. Calculate Score
        if analysis_found:
            score += 20
            feedback.append("Scatterplot Matrix analysis found.")
        else:
            feedback.append("No Scatterplot Matrix analysis with the correct variables found in the file.")
            
        if correct_vars:
            score += 20
            feedback.append("Variables (Exam, Anxiety, Revise) correctly selected.")
            
        if correct_group:
            score += 20
            feedback.append("Grouping variable (Gender) correctly applied.")
        else:
            feedback.append("Grouping variable missing or incorrect.")
            
        if density_on:
            score += 10
            feedback.append("Density plots enabled.")
        else:
            feedback.append("Density plots missing.")
            
        if linear_on:
            score += 10
            feedback.append("Linear regression lines enabled.")
        else:
            feedback.append("Linear regression lines missing.")
            
        if corrs_on:
            score += 10
            feedback.append("Correlations enabled.")
        else:
            feedback.append("Correlations missing.")

        passed = score >= 70 and correct_vars and correct_group
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir)