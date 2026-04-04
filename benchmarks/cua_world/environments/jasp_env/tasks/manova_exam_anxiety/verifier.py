#!/usr/bin/env python3
"""
Verifier for JASP MANOVA Task (manova_exam_anxiety@1)
"""

import json
import os
import tempfile
import zipfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manova_exam_anxiety(traj, env_info, task_info):
    """
    Verifies the MANOVA task by inspecting the saved .jasp file (which is a zip)
    and using VLM to check the UI trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Initialize scoring
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check File Existence and Timestamp (Anti-gaming)
    if not result_data.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The JASP output file 'ExamAnxiety_MANOVA.jasp' was not found."
        }
    
    score += 10
    feedback_parts.append("File created")

    if result_data.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("WARNING: File timestamp is outside task session")

    # 3. Analyze .jasp File Content
    # JASP files are ZIP archives containing JSON/HTML analysis definitions/results
    jasp_file_path = result_data.get("output_path")
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip') # .jasp is a zip
    
    analysis_verified = False
    vars_verified = False
    descriptives_verified = False
    
    try:
        copy_from_env(jasp_file_path, temp_jasp.name)
        
        if zipfile.is_zipfile(temp_jasp.name):
            with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                # List files to find relevant content (usually 'index.html' or 'analyses/...')
                file_list = z.namelist()
                logger.info(f"JASP file contents: {file_list}")
                
                # JASP saves analysis settings in JSON or embedded in HTML
                # We'll search all text-based files for keywords if specific JSON structure isn't found
                content_text = ""
                for filename in file_list:
                    if filename.endswith('.json') or filename.endswith('.html') or filename.endswith('.qml'):
                        try:
                            with z.open(filename) as f:
                                content_text += f.read().decode('utf-8', errors='ignore')
                        except:
                            pass
                
                # Check 3.1: Analysis Type (MANOVA)
                # JASP stores analysis names like "Manova" or "jaspAnova::Manova"
                if "Manova" in content_text or "Multivariate Analysis of Variance" in content_text:
                    analysis_verified = True
                    score += 25
                    feedback_parts.append("MANOVA analysis detected")
                else:
                    feedback_parts.append("MANOVA analysis NOT detected in file")

                # Check 3.2: Variables (Exam, Anxiety, Gender)
                # Look for evidence these variables were used
                # In JSON it might look like "dependentVariables": ["Exam", "Anxiety"]
                # In HTML it usually appears in table headers
                if "Exam" in content_text and "Anxiety" in content_text and "Gender" in content_text:
                    vars_verified = True
                    score += 20
                    feedback_parts.append("Correct variables used")
                else:
                    feedback_parts.append("Missing required variables (Exam, Anxiety, or Gender)")

                # Check 3.3: Specific Statistics (Pillai/Wilks & Descriptives)
                # These terms appear in the results table HTML/JSON
                multivariate_stats = ["Pillai", "Wilks", "Hotelling", "Roy"]
                if any(stat in content_text for stat in multivariate_stats):
                    score += 15
                    feedback_parts.append("Multivariate test statistics found")
                
                if "Descriptive" in content_text or "Mean" in content_text:
                    descriptives_verified = True
                    score += 5
                    feedback_parts.append("Descriptives found")

        else:
            feedback_parts.append("Output file is not a valid ZIP/JASP archive")

    except Exception as e:
        feedback_parts.append(f"Error analyzing JASP file: {str(e)}")
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    # 4. VLM Verification (Trajectory)
    # Use VLM to confirm the workflow if file parsing was ambiguous or as a second signal
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review the sequence of screenshots from the JASP statistical software.
    I need to verify if the user performed a MANOVA (Multivariate Analysis of Variance).
    
    Look for:
    1. The "ANOVA" menu being open.
    2. "MANOVA" being selected.
    3. Two dependent variables (Exam, Anxiety) being added.
    4. One fixed factor (Gender) being added.
    5. A results table showing "MANOVA" or "Multivariate Tests" (Pillai's Trace, Wilks' Lambda).
    
    Did the user perform the MANOVA task correctly?
    """
    
    vlm_result = query_vlm(
        images=frames + [final_screen],
        prompt=vlm_prompt
    )
    
    vlm_passed = vlm_result.get("passed", False) or "yes" in vlm_result.get("response", "").lower()
    
    if vlm_passed:
        score += 15
        feedback_parts.append("VLM verified workflow")
    else:
        feedback_parts.append("VLM did not verify workflow")

    # Final Score Calculation
    passed = score >= 60 and analysis_verified
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }