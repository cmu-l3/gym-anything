#!/usr/bin/env python3
"""
Verifier for visualize_exam_anxiety_scatterplot task.

Checks:
1. File Existence & Timestamp: .omv file created during task.
2. File Structure: Valid Zip archive (OMV format).
3. Analysis Configuration: Parses internal JSON to verify:
   - Analysis: scatr::scat (Scatterplot)
   - X-Axis: Revise
   - Y-Axis: Exam
   - Group: Gender
   - Regression: Linear + SE
   - Marginals: Density
4. VLM Verification: Checks trajectory for visual evidence of graph creation.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil

# Import VLM helpers from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_visualize_exam_anxiety_scatterplot(traj, env_info, task_info):
    """
    Verifies the scatterplot task by inspecting the OMV file and VLM trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    max_score = 100
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. Metadata & File Retrieval
    # ------------------------------------------------------------------
    # Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = result_data.get("output_exists", False)
    file_created = result_data.get("file_created_during_task", False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file 'ExamScatterplot.omv' was not found."}
    
    if not file_created:
        feedback.append("WARNING: Output file timestamp indicates it wasn't created during this session.")
        # We proceed but penalize slightly if purely file-based, but here we check content.

    score += 10 # File exists
    feedback.append("Output file exists.")

    # Retrieve OMV file for analysis
    temp_omv = tempfile.NamedTemporaryFile(delete=False, suffix='.omv')
    omv_path = temp_omv.name
    temp_omv.close() # Close so we can write to it via copy

    try:
        copy_from_env(result_data["output_path"], omv_path)
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to copy output file for verification: {str(e)}"}

    # ------------------------------------------------------------------
    # 2. OMV File Analysis (Internal JSON Parsing)
    # ------------------------------------------------------------------
    # Jamovi files are ZIPs. We look for analysis definitions in the archive.
    analysis_found = False
    config_correct = {
        "x": False, "y": False, "group": False, 
        "line": False, "se": False, "marg": False
    }

    try:
        if not zipfile.is_zipfile(omv_path):
             return {"passed": False, "score": 10, "feedback": "Output file is not a valid OMV (zip) archive."}

        with zipfile.ZipFile(omv_path, 'r') as z:
            # Iterate over all files to find analysis definitions.
            # Usually located in numbered folders, e.g., '01 scatr/analysis'
            for filename in z.namelist():
                if filename.endswith("analysis"):
                    try:
                        with z.open(filename) as f:
                            content = f.read()
                            # Content is typically JSON
                            try:
                                data = json.loads(content.decode('utf-8'))
                            except:
                                continue

                            # Check if this is the scatterplot analysis
                            # The name might be "scatr::scat" or similar in "name" or "proc" field
                            # Jamovi JSON structure varies by version but usually has 'options'
                            
                            # Heuristic: Check if options contain our variables
                            options = data.get("options", {})
                            if not isinstance(options, dict):
                                continue

                            # Check for Scatterplot signature
                            # Sometimes the key is 'x' or 'xaxis', 'y' or 'yaxis'
                            # In scatr::scat it is typically x, y, group
                            
                            if "x" in options and "y" in options:
                                # Found a candidate analysis
                                analysis_found = True
                                
                                # Check X Axis
                                if options.get("x") == "Revise":
                                    config_correct["x"] = True
                                
                                # Check Y Axis
                                if options.get("y") == "Exam":
                                    config_correct["y"] = True
                                
                                # Check Group
                                if options.get("group") == "Gender":
                                    config_correct["group"] = True
                                
                                # Check Regression Line
                                # Jamovi stores 'line' as string "linear"
                                if options.get("line") == "linear":
                                    config_correct["line"] = True
                                
                                # Check Standard Error
                                # 'se' boolean
                                if options.get("se") is True:
                                    config_correct["se"] = True
                                
                                # Check Marginals
                                # 'marg' string "dens"
                                if options.get("marg") == "dens":
                                    config_correct["marg"] = True
                                
                                # If we found the right analysis, break (assume user made one correct one)
                                if config_correct["x"] and config_correct["y"]:
                                    break
                    except Exception as e:
                        logger.warning(f"Error reading internal file {filename}: {e}")
                        continue

    except Exception as e:
        feedback.append(f"Error parsing OMV file: {e}")
    finally:
        if os.path.exists(omv_path):
            os.unlink(omv_path)

    # Scoring based on file analysis
    if analysis_found:
        score += 20
        feedback.append("Scatterplot analysis found in project.")
        
        if config_correct["x"] and config_correct["y"]:
            score += 20
            feedback.append("Axes correctly configured (Revise vs Exam).")
        else:
            feedback.append(f"Axes incorrect. Found X={config_correct['x']}, Y={config_correct['y']}")

        if config_correct["group"]:
            score += 15
            feedback.append("Grouping by Gender active.")
        else:
            feedback.append("Grouping by Gender missing.")

        if config_correct["line"]:
            score += 10
            feedback.append("Linear regression line enabled.")
        else:
            feedback.append("Linear regression line missing or wrong type.")

        if config_correct["se"]:
            score += 5
            feedback.append("Standard Error shading enabled.")
        else:
            feedback.append("Standard Error shading missing.")

        if config_correct["marg"]:
            score += 10
            feedback.append("Marginal Density plots enabled.")
        else:
            feedback.append("Marginal plots missing or wrong type.")
            
    else:
        feedback.append("No Scatterplot analysis found in the saved project file.")

    # ------------------------------------------------------------------
    # 3. VLM Verification (Visual Check)
    # ------------------------------------------------------------------
    # Use VLM to confirm the chart actually looks right (fallback/anti-gaming)
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        frames.append(final_shot)
        
    vlm_score = 0
    if frames:
        prompt = """
        You are verifying a Jamovi data analysis task.
        The user was asked to create a Scatterplot of 'Revise' (x) vs 'Exam' (y), grouped by 'Gender'.
        They should have added a Linear Regression line and Marginal Density plots (curves on top/right axes).
        
        Review the screenshots. 
        1. Do you see a Jamovi window with a Scatterplot?
        2. Does the plot show two distinct colors/groups (for Gender)?
        3. Do you see straight regression lines through the data?
        4. Do you see density curves (bell shapes) on the axes margins?
        
        Return JSON: {"scatterplot_visible": bool, "grouped_by_color": bool, "regression_lines": bool, "marginal_plots": bool}
        """
        
        result = query_vlm(images=frames, prompt=prompt)
        
        if result and result.get("success"):
            parsed = result.get("parsed", {})
            if parsed.get("scatterplot_visible"): vlm_score += 2
            if parsed.get("grouped_by_color"): vlm_score += 3
            if parsed.get("regression_lines"): vlm_score += 3
            if parsed.get("marginal_plots"): vlm_score += 2
            
            # Normalize VLM score to remaining 10 points
            # (Total file points = 10+20+20+15+10+5+10 = 90. So 10 points left for VLM)
            # Actually, logic above: 10(file) + 20(analysis) + 20(axes) + 15(group) + 10(line) + 5(se) + 10(marg) = 90
            pass
        else:
            # If VLM fails, we trust the file analysis more
            pass

    # Add VLM score (capped at 10)
    score += vlm_score
    feedback.append(f"VLM Visual Verification Score: {vlm_score}/10")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }