#!/usr/bin/env python3
"""
Verifier for anova_planned_contrasts_viagra task.

Verification Strategy:
1. File Check: Confirm .jasp file exists and was created during the task.
2. Content Check: Unzip the .jasp file (it's a zip archive) and inspect internal logs/JSON
   for evidence of 'simple' contrast type and 'Placebo' reference.
3. VLM Verification: Use trajectory and final screenshot to verify the specific
   contrast table structure (e.g., looking for " - Placebo" in row labels).
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anova_contrasts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    score = 0
    feedback_parts = []
    
    # 1. Load basic result metadata
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Criterion: Output file exists and was created during task
    if result_data.get("output_exists") and result_data.get("file_created_during_task"):
        score += 20
        feedback_parts.append("JASP project file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "JASP project file not saved or not created during task."}

    # 2. Inspect JASP File Content (Programmatic Check)
    # The .jasp file is a zip. We look for the Analysis options.
    jasp_file_path = result_data.get("output_path")
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    
    content_verified = False
    contrast_type_found = False
    reference_found = False
    
    try:
        copy_from_env(jasp_file_path, temp_jasp.name)
        
        if zipfile.is_zipfile(temp_jasp.name):
            with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                # JASP stores analysis specs in various JSONs inside the archive.
                # We search all text files for key configuration strings.
                for filename in z.namelist():
                    if filename.endswith('.json') or filename.endswith('.r') or 'state' in filename:
                        try:
                            with z.open(filename) as f:
                                content = f.read().decode('utf-8', errors='ignore')
                                
                                # Check for Simple Contrast
                                if '"contrastType":"simple"' in content or 'contrast = "simple"' in content:
                                    contrast_type_found = True
                                
                                # Check for Placebo reference
                                # Often appears as "ref = 'Placebo'" or in factor level ordering
                                if 'Placebo' in content and ('ref' in content or 'base' in content):
                                    reference_found = True
                                    
                                # Alternative Check: JASP often stores R syntax
                                if 'contrasts' in content and 'simple' in content:
                                    contrast_type_found = True
                        except:
                            continue
    except Exception as e:
        logger.warning(f"Failed to inspect JASP internal content: {e}")
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    if contrast_type_found:
        score += 20
        feedback_parts.append("Programmatic check: Simple contrast detected.")
    
    # 3. VLM Verification (Visual Confirmation)
    # This is critical because "Placebo as reference" might be hard to parse from internal JSON 
    # if it relies on implicit factor ordering. The UI table is the source of truth.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images = frames + [final_screen] if final_screen else frames

    prompt = """
    Review the screenshots of a JASP statistical analysis session.
    The user is performing a One-Way ANOVA on the Viagra dataset.
    
    Check for these specific elements:
    1. Is the ANOVA results table visible?
    2. Is there a "Descriptives" table visible?
    3. CRITICAL: Look for a "Contrasts" table.
    4. In the Contrasts table, do the comparisons look like "Low Dose - Placebo" and "High Dose - Placebo"? 
       (or "Level 1 vs Placebo").
       If the reference was wrong (e.g. alphabetical), it would likely compare against "High Dose".
       We specifically need "Placebo" to be the reference/baseline (the second term in the subtraction or the implied baseline).
       
    Report:
    - "anova_visible": boolean
    - "descriptives_visible": boolean
    - "contrasts_simple_visible": boolean (Is the 'Simple' contrast logic apparent?)
    - "placebo_reference_correct": boolean (Is Placebo used as the reference category?)
    """

    vlm_result = query_vlm(images=images, prompt=prompt).get('parsed', {})
    
    # Scoring VLM results
    if vlm_result.get("anova_visible", False):
        score += 10
    
    if vlm_result.get("descriptives_visible", False):
        score += 10
        
    if vlm_result.get("contrasts_simple_visible", False):
        score += 20
        feedback_parts.append("Visual check: Contrasts table visible.")
        
    if vlm_result.get("placebo_reference_correct", False):
        score += 20
        feedback_parts.append("Visual check: Correctly used Placebo as reference.")
    elif reference_found: # Fallback to programmatic check if VLM is unsure
        score += 20
        feedback_parts.append("Programmatic check: Placebo reference confirmed.")
    else:
        feedback_parts.append("Could not confirm Placebo was set as reference category.")

    # Determine final status
    passed = score >= 70  # Needs at least correct file + partial contrast correctness
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }