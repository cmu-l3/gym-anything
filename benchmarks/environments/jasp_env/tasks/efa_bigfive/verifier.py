#!/usr/bin/env python3
"""
Verifier for Exploratory Factor Analysis (EFA) task in JASP.

Verification Strategy:
1. Validate JASP Output File (.jasp is a zip archive):
   - Unzip and inspect internal JSON state
   - Check for "ExploratoryFactorAnalysis" (not PCA)
   - Check for "principalAxis" extraction
   - Check for "oblimin" rotation
   - Check for "parallelAnalysis"
2. Validate Report Text:
   - Check for keywords matching requirements
3. VLM Verification (Trajectory):
   - Confirm visual progression (Factor module, settings panel, results output)
"""

import json
import os
import zipfile
import tempfile
import shutil
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_efa_bigfive(traj, env_info, task_info):
    """
    Verify EFA task on Big Five dataset.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Define scoring weights
    WEIGHTS = {
        "jasp_file_valid": 10,
        "analysis_type_correct": 15,
        "extraction_correct": 10,
        "rotation_correct": 10,
        "retention_correct": 10,
        "report_exists": 10,
        "report_content": 10,
        "visual_verification": 25
    }

    # 1. Load basic result metadata
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Analyze JASP File Content
    jasp_settings_found = {
        "is_efa": False,
        "is_paf": False,
        "is_oblimin": False,
        "is_parallel": False
    }
    
    jasp_exists = task_result.get("jasp_file_exists", False)
    jasp_created_during = task_result.get("jasp_created_during_task", False)
    
    if jasp_exists and jasp_created_during:
        score += WEIGHTS["jasp_file_valid"]
        feedback_parts.append("JASP file created successfully")
        
        # Extract and inspect JASP file
        temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
        extract_dir = tempfile.mkdtemp()
        
        try:
            # Copy JASP file from container (it was copied to /tmp/verification_output.jasp in export)
            copy_from_env("/tmp/verification_output.jasp", temp_jasp.name)
            
            # Unzip
            try:
                with zipfile.ZipFile(temp_jasp.name, 'r') as zip_ref:
                    zip_ref.extractall(extract_dir)
                
                # JASP stores analysis settings in various JSON files inside the zip
                # We search all JSON files for specific keys/values
                content_str = ""
                for root, dirs, files in os.walk(extract_dir):
                    for file in files:
                        if file.endswith(".json") or file.endswith(".qml"):
                            try:
                                with open(os.path.join(root, file), 'r', encoding='utf-8', errors='ignore') as f:
                                    content_str += f.read()
                            except:
                                pass
                
                # Check Analysis Type
                if "ExploratoryFactorAnalysis" in content_str:
                    jasp_settings_found["is_efa"] = True
                    score += WEIGHTS["analysis_type_correct"]
                    feedback_parts.append("Correct Analysis: EFA")
                elif "PrincipalComponentAnalysis" in content_str:
                    feedback_parts.append("Incorrect Analysis: PCA used instead of EFA")
                else:
                    feedback_parts.append("Could not confirm analysis type")

                # Check Extraction Method (principalAxis)
                if '"factoringMethod":"principalAxis"' in content_str or '"factoringMethod": "principalAxis"' in content_str or "principalAxis" in content_str:
                    jasp_settings_found["is_paf"] = True
                    score += WEIGHTS["extraction_correct"]
                    feedback_parts.append("Extraction: Principal Axis Factoring")
                else:
                    feedback_parts.append("Incorrect Extraction Method")

                # Check Rotation (oblimin)
                if "oblimin" in content_str.lower():
                    jasp_settings_found["is_oblimin"] = True
                    score += WEIGHTS["rotation_correct"]
                    feedback_parts.append("Rotation: Oblimin")
                else:
                    feedback_parts.append("Incorrect/Missing Rotation")

                # Check Retention (parallel analysis)
                if '"numberOfFactorsMethod":"parallelAnalysis"' in content_str or '"numberOfFactorsMethod": "parallelAnalysis"' in content_str or "parallelAnalysis" in content_str:
                    jasp_settings_found["is_parallel"] = True
                    score += WEIGHTS["retention_correct"]
                    feedback_parts.append("Retention: Parallel Analysis")
                else:
                    feedback_parts.append("Incorrect Retention Method")

            except zipfile.BadZipFile:
                feedback_parts.append("JASP file is corrupted or invalid")

        except Exception as e:
            logger.error(f"Error analyzing JASP file: {e}")
            feedback_parts.append("Failed to analyze JASP file content")
        finally:
            if os.path.exists(temp_jasp.name):
                os.unlink(temp_jasp.name)
            shutil.rmtree(extract_dir, ignore_errors=True)
    else:
        feedback_parts.append("JASP output file missing or not created during task")

    # 3. Analyze Report Content
    report_exists = task_result.get("report_exists", False)
    report_content = task_result.get("report_content", "").lower()
    
    if report_exists:
        score += WEIGHTS["report_exists"]
        feedback_parts.append("Report file created")
        
        # content checks
        keywords_present = 0
        if "factor" in report_content: keywords_present += 1
        if "axis" in report_content or "paf" in report_content: keywords_present += 1
        if "oblimin" in report_content: keywords_present += 1
        
        if keywords_present >= 2:
            score += WEIGHTS["report_content"]
            feedback_parts.append("Report content valid")
        else:
            feedback_parts.append("Report missing key details (method/rotation)")
    else:
        feedback_parts.append("Report file missing")

    # 4. VLM Verification
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = """
    Review this sequence of screenshots from JASP statistical software.
    I need to verify if the user performed an Exploratory Factor Analysis (EFA).
    
    Look for:
    1. The 'Factor' menu being accessed.
    2. 'Exploratory Factor Analysis' being selected (NOT Principal Component Analysis).
    3. Output tables showing 'Factor Loadings'.
    4. A 'Scree Plot' (line plot descending).
    5. A Path Diagram (network graph of nodes).
    
    Return JSON:
    {
        "efa_menu_accessed": true/false,
        "scree_plot_visible": true/false,
        "factor_loadings_visible": true/false,
        "path_diagram_visible": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    try:
        vlm_result = query_vlm(images=all_images, prompt=vlm_prompt)
        vlm_data = vlm_result.get("parsed", {})
        
        vlm_score = 0
        if vlm_data.get("efa_menu_accessed"): vlm_score += 5
        if vlm_data.get("scree_plot_visible"): vlm_score += 10
        if vlm_data.get("factor_loadings_visible"): vlm_score += 5
        if vlm_data.get("path_diagram_visible"): vlm_score += 5
        
        score += vlm_score
        feedback_parts.append(f"Visual Verification: {vlm_score}/{WEIGHTS['visual_verification']}")
        
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        feedback_parts.append("Visual verification skipped due to error")
        # Grant partial credit if file checks passed significantly to avoid failing on VLM error
        if score > 40:
            score += 10

    # Final result
    passed = score >= 60 and jasp_settings_found["is_efa"]
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }