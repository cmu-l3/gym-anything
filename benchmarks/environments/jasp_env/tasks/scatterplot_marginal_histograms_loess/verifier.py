#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_scatterplot_loess(traj, env_info, task_info):
    """
    Verifies that the agent created a JASP file with a Descriptives Scatterplot,
    Smooth line (Loess), and Marginal Histograms.
    """
    
    # 1. Setup & Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy access failed"}

    score = 0
    feedback = []
    
    # 2. Retrieve Basic Result JSON
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

    # 3. Check Basic File Requirements (Max 20 pts)
    if not result_data.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file /home/ga/Documents/JASP/ExploratoryPlot.jasp not found."}
    
    score += 10
    feedback.append("File created.")
    
    if result_data.get("file_created_during_task"):
        score += 10
        feedback.append("File verification passed (created during task).")
    else:
        feedback.append("Warning: File timestamp indicates it might be stale.")

    # 4. Inspect JASP File Content (Max 50 pts)
    # JASP files are ZIP archives containing 'analyses.json' or similar structure
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    analysis_found = False
    settings_correct = {
        "variables": False,
        "scatterplot": False,
        "smooth": False,
        "marginals": False,
        "histogram": False
    }
    
    try:
        copy_from_env(result_data["output_path"], temp_jasp.name)
        
        if not zipfile.is_zipfile(temp_jasp.name):
            feedback.append("Error: Output file is not a valid JASP/ZIP archive.")
        else:
            with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                # Look for analysis definitions
                # Usually in 'embedded/1/analyses.json' or just 'analyses.json'
                json_files = [f for f in z.namelist() if f.endswith('json')]
                
                for jf in json_files:
                    try:
                        data = json.loads(z.read(jf).decode('utf-8'))
                        # JASP JSON structure varies, but we look for key indicators
                        # Recursively search or iterate list
                        results_list = data if isinstance(data, list) else data.get("results", [])
                        
                        # Flatten structure to string for fuzzy search if structure is complex
                        # or iterate through analysis objects
                        
                        # Simplified check logic:
                        # 1. Find a Descriptive analysis
                        # 2. Check its settings
                        
                        def check_settings(obj):
                            s_score = 0
                            # Convert object to string for easy keyword search in this specific node
                            obj_str = json.dumps(obj).lower()
                            
                            # Check variables (Anxiety and Exam)
                            if "anxiety" in obj_str and "exam" in obj_str:
                                settings_correct["variables"] = True
                            
                            # Check Scatterplot enabled
                            # Keys often look like "plotScatter": true or "scatter": true
                            if "scatter" in obj_str: 
                                settings_correct["scatterplot"] = True
                                
                            # Check Smooth/Loess
                            # Keys: "plotScatterRegressionLineType": "smooth"
                            if "smooth" in obj_str or "loess" in obj_str:
                                settings_correct["smooth"] = True
                                
                            # Check Marginals
                            # Keys: "plotScatterMarginal": true
                            if "marginal" in obj_str:
                                settings_correct["marginals"] = True
                                
                            # Check Histogram
                            if "histogram" in obj_str or "density" in obj_str:
                                settings_correct["histogram"] = True

                        # Iterate over all components in the JSON
                        if isinstance(data, list):
                            for item in data:
                                check_settings(item)
                        elif isinstance(data, dict):
                            check_settings(data)
                            
                    except:
                        continue

            # Calculate score based on findings
            if settings_correct["scatterplot"] and settings_correct["variables"]:
                score += 10
                feedback.append("Scatterplot configuration found.")
                
                if settings_correct["smooth"]:
                    score += 20
                    feedback.append("Smooth/Loess line configured.")
                else:
                    feedback.append("Missing Smooth/Loess line setting.")
                    
                if settings_correct["marginals"]:
                    score += 10
                    feedback.append("Marginal plots enabled.")
                    if settings_correct["histogram"]:
                        score += 10
                        feedback.append("Marginal type set to Histogram/Density.")
                else:
                    feedback.append("Missing Marginal plots setting.")
            else:
                feedback.append("Could not confirm specific scatterplot settings in file.")

    except Exception as e:
        feedback.append(f"Error inspecting JASP file structure: {str(e)}")
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    # 5. VLM Verification (Max 30 pts)
    # Use trajectory to confirm the user actually interacted with the UI
    # and final screenshot to see the result
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of JASP software.
    1. Is there a Scatterplot visible in the results panel (usually right side)?
    2. Does the scatterplot have a curved/wavy trend line (indicating Loess/Smooth) rather than a straight line?
    3. Are there histograms or density plots attached to the top and right axes of the scatterplot (Marginal plots)?
    
    Return JSON: {"scatterplot_visible": bool, "curved_line": bool, "marginal_plots": bool}
    """
    
    vlm_result = query_vlm(
        images=frames + [final_screen],
        prompt=vlm_prompt
    )
    
    try:
        parsed = vlm_result.get("parsed", {})
        if parsed.get("scatterplot_visible"):
            score += 10
            feedback.append("VLM: Scatterplot visible.")
            
            if parsed.get("curved_line"):
                score += 10
                feedback.append("VLM: Curved smoothing line detected.")
            else:
                feedback.append("VLM: Line appears straight or missing.")
                
            if parsed.get("marginal_plots"):
                score += 10
                feedback.append("VLM: Marginal histograms detected.")
            else:
                feedback.append("VLM: Marginal plots missing.")
        else:
            feedback.append("VLM: No scatterplot detected in final view.")
            
    except Exception as e:
        logger.warning(f"VLM parsing error: {e}")
        # Fallback: if file check passed with high score, assume VLM might be flaky
        if score >= 60:
            score += 10 # Grace points if file verification was perfect

    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }