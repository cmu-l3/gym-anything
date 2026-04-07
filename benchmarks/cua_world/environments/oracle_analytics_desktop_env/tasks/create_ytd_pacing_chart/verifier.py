#!/usr/bin/env python3
"""
Verifier for create_ytd_pacing_chart task.
"""

import json
import os
import zipfile
import logging
import tempfile
import shutil
from typing import Dict, Any

# Import VLM utils provided by the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, image=None, images=None): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ytd_pacing_chart(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the creation of a YTD Pacing Chart.
    
    Strategy:
    1. VLM: Check trajectory/final frame for visual correctness (cumulative lines, year colors).
    2. Programmatic: Check if DVA file exists, was created during task, and contains key aggregation terms.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Fetch Basic Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy result json: {e}")
        result_data = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Score Basic Criteria (30 pts)
    output_exists = result_data.get('output_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    
    if output_exists:
        score += 15
        feedback_parts.append("Workbook file saved")
        if created_during:
            score += 15
            feedback_parts.append("Workbook created during task session")
        else:
            feedback_parts.append("Workbook file timestamp predates task (stale data)")
    else:
        feedback_parts.append("Workbook file NOT found")

    # 3. Analyze DVA Content (Programmatic) (30 pts)
    # The .dva file is a zip. We look for keywords like "RSUM" (Running Sum) or "MSUM" inside the XML/JSON definitions.
    dva_content_score = 0
    if output_exists:
        temp_dva = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
        try:
            copy_from_env(result_data.get('output_path', ''), temp_dva.name)
            
            # Search for keywords in the archive
            has_running_sum = False
            has_year_month = False
            
            if zipfile.is_zipfile(temp_dva.name):
                with zipfile.ZipFile(temp_dva.name, 'r') as z:
                    for filename in z.namelist():
                        # DVA usually contains xml or json definitions of validat (datamodel)
                        if filename.endswith('.xml') or filename.endswith('.json'):
                            try:
                                content = z.read(filename).decode('utf-8', errors='ignore')
                                if 'RSUM' in content or 'MSUM' in content or 'running' in content.lower():
                                    has_running_sum = True
                                if 'Month' in content and 'Year' in content:
                                    has_year_month = True
                            except:
                                continue
            
            if has_running_sum:
                dva_content_score += 20
                feedback_parts.append("Running Total aggregation detected in file")
            else:
                feedback_parts.append("Running Total logic NOT detected in file")
                
            if has_year_month:
                dva_content_score += 10
                feedback_parts.append("Year/Month dimensions detected")
                
        except Exception as e:
            logger.error(f"Failed to inspect DVA: {e}")
            feedback_parts.append("Failed to inspect workbook content")
        finally:
            if os.path.exists(temp_dva.name):
                os.unlink(temp_dva.name)
    
    score += dva_content_score

    # 4. VLM Verification (40 pts)
    # We use VLM to verify the visual chart structure which is hard to parse from XML
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=4)
    all_images = frames + ([final_screenshot] if final_screenshot else [])
    
    vlm_score = 0
    if all_images:
        prompt = """
        Analyze these screenshots of Oracle Analytics Desktop.
        The user is trying to create a 'Pacing Chart' (Cumulative Sales by Month, colored by Year).
        
        Look for:
        1. A Line Chart (not bar, not pie).
        2. Multiple colored lines on the same chart (representing different years).
        3. The lines should be strictly INCREASING (going up from left to right) - this indicates a Running Total/Cumulative Sum.
           If the lines go up and down jaggedly, it is NOT a cumulative chart.
        4. The X-axis should show generic Months (Jan, Feb...) not Year-Month.
        
        Respond in JSON:
        {
            "is_line_chart": boolean,
            "has_multiple_lines": boolean,
            "is_cumulative_increasing": boolean,
            "axis_looks_correct": boolean
        }
        """
        
        vlm_res = query_vlm(prompt=prompt, images=all_images)
        if vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {})
            
            if analysis.get('is_line_chart'):
                vlm_score += 10
            
            if analysis.get('has_multiple_lines'):
                vlm_score += 10
                
            if analysis.get('is_cumulative_increasing'):
                vlm_score += 10
                feedback_parts.append("Visuals confirm cumulative trajectory")
            else:
                feedback_parts.append("Visuals do NOT show smooth cumulative increase")
                
            if analysis.get('axis_looks_correct'):
                vlm_score += 10
        else:
            feedback_parts.append("VLM analysis failed")
    
    score += vlm_score
    
    # Calculate Final Pass/Fail
    # Must have file, must look cumulative, must have multiple lines
    pass_threshold = 70
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }