#!/usr/bin/env python3
"""
Verifier for Gauge R&R Measurement System Analysis task.

Strategy:
1. Verify JASP project file (.jasp) creation and validity.
2. Inspect JASP file content (it's a zip) to check:
   - Analysis type is 'qualityControlGaugeRrCrossed'
   - Variables are correctly assigned (Part, Operator, Measurement)
   - Variation components chart is enabled
3. Use VLM to visually confirm the results table and chart are visible.
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

def verify_gauge_rr(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_analysis_type = metadata.get('required_analysis_type', 'qualityControlGaugeRrCrossed')
    
    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Retrieve Task Result JSON
    # ================================================================
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
            
    output_exists = result_data.get('output_exists', False)
    file_created = result_data.get('file_created_during_task', False)
    output_path = result_data.get('output_path', '')

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output JASP file not found."}

    score += 20
    feedback_parts.append("JASP file saved.")

    if file_created:
        score += 10
        feedback_parts.append("File created during task.")
    else:
        feedback_parts.append("Warning: File timestamp indicates it might be old.")

    # ================================================================
    # 2. Analyze JASP File Content
    # ================================================================
    # JASP files are ZIP archives containing 'analyses.json'
    temp_jasp = tempfile.NamedTemporaryFile(delete=False, suffix='.jasp')
    analysis_valid = False
    vars_correct = False
    chart_enabled = False
    
    try:
        copy_from_env(output_path, temp_jasp.name)
        
        if not zipfile.is_zipfile(temp_jasp.name):
             feedback_parts.append("Saved file is not a valid JASP archive.")
        else:
            with zipfile.ZipFile(temp_jasp.name, 'r') as z:
                # JASP structure usually has embedded folder, e.g. 'index.html', 'data', 'analyses'
                # Searching for a JSON file that defines analyses
                json_files = [f for f in z.namelist() if f.endswith('.json')]
                
                # Analysis definitions are typically in the specific analysis folder or index
                # We look for the main analysis definition
                found_analysis = False
                
                # Check all JSONs for the analysis type
                for jf in json_files:
                    try:
                        with z.open(jf) as f:
                            content = json.load(f)
                            # Structure varies by version, but often looks like:
                            # {"results": [... "title": "Gauge R&R", "meta": {"name": "qualityControlGaugeRrCrossed"} ...]}
                            # Or deeply nested in 'analyses' list
                            
                            # Helper to search recursively for analysis type
                            def search_analysis(obj):
                                if isinstance(obj, dict):
                                    # Check for specific JASP internal name
                                    if obj.get('name') == expected_analysis_type or \
                                       obj.get('analysisName') == expected_analysis_type:
                                        return obj
                                    for k, v in obj.items():
                                        res = search_analysis(v)
                                        if res: return res
                                elif isinstance(obj, list):
                                    for item in obj:
                                        res = search_analysis(item)
                                        if res: return res
                                return None

                            analysis_obj = search_analysis(content)
                            if analysis_obj:
                                found_analysis = True
                                analysis_valid = True
                                
                                # Check variables
                                # Usually in 'options' dict
                                options = analysis_obj.get('options', {})
                                
                                # Check mappings (keys vary slightly by version but usually match input names)
                                # For Gauge R&R Crossed: part -> 'part', operator -> 'operator', measurement -> 'measurement'
                                part_var = options.get('part', [])
                                op_var = options.get('operator', [])
                                meas_var = options.get('measurement', [])
                                
                                # Variables are often lists of strings
                                if "Part" in str(part_var):
                                    vars_correct = True # Partial credit logic handled later
                                if "Operator" in str(op_var) and "Measurement" in str(meas_var):
                                    vars_correct = True
                                else:
                                    vars_correct = False # Strict check needs all
                                    
                                # Check chart
                                if options.get('componentsChart', False) is True:
                                    chart_enabled = True
                                break
                    except:
                        continue
                
                if analysis_valid:
                    score += 20
                    feedback_parts.append("Correct Gauge R&R (Crossed) analysis found.")
                else:
                    feedback_parts.append("Could not find Gauge R&R analysis in file.")

                if vars_correct:
                    score += 30
                    feedback_parts.append("Variables correctly assigned.")
                else:
                    feedback_parts.append("Variable assignment incorrect.")

                if chart_enabled:
                    score += 10
                    feedback_parts.append("Variation components chart enabled.")
                else:
                    feedback_parts.append("Variation components chart NOT enabled.")

    except Exception as e:
        feedback_parts.append(f"Error analyzing JASP file: {str(e)}")
    finally:
        if os.path.exists(temp_jasp.name):
            os.unlink(temp_jasp.name)

    # ================================================================
    # 3. VLM Verification
    # ================================================================
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, 5)
    
    if final_screenshot:
        # Check visually
        prompt = """
        You are verifying a JASP statistical analysis task.
        The user was asked to perform a Gauge R&R study.
        
        Look at the screenshot.
        1. Is the "Quality Control" module or menu visible?
        2. Is there a result table titled "Gauge R&R" or similar?
        3. Is there a bar chart showing "Components of Variation" (colored bars)?
        """
        
        try:
            vlm_res = query_vlm(
                images=frames + [final_screenshot], 
                prompt=prompt
            )
            
            # Simple keyword matching in VLM response if structured parsing fails
            # But assume VLM helper returns dict or we parse text
            response_text = str(vlm_res).lower()
            
            vlm_score = 0
            if "gauge r&r" in response_text or "table" in response_text:
                vlm_score += 5
            if "chart" in response_text or "graph" in response_text or "variation" in response_text:
                vlm_score += 5
                
            score += vlm_score
            if vlm_score > 0:
                feedback_parts.append("Visual verification confirmed results visible.")
                
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: give points if file analysis was perfect
            if analysis_valid and vars_correct:
                score += 10

    # Final logic
    passed = score >= 80 and analysis_valid and vars_correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }