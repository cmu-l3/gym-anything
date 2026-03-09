#!/usr/bin/env python3
"""
Verifier for Population Pyramid task.

Verifies:
1. PBIX file exists and was created during the task.
2. Contains a Stacked Bar Chart.
3. Uses 2 measures (Male/Female) and Age Group category.
4. Uses VLM to confirm the visual pyramid shape and positive formatting on axis.
"""

import json
import os
import tempfile
import logging
import zipfile
import shutil

# Import VLM utilities from the environment
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback/Mock for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "ImportError"}
    def get_final_screenshot(traj): return None

logger = logging.getLogger(__name__)

def verify_population_pyramid_census(traj, env_info, task_info):
    """
    Verify the population pyramid task using file analysis and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON and PBIX file
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    pbix_path = os.path.join(temp_dir, "Census_Pyramid.pbix")
    
    try:
        # Get metadata
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
            
        # Get PBIX file (if it exists)
        if result_data.get("output_exists"):
            try:
                copy_from_env("/tmp/Census_Pyramid.pbix", pbix_path)
            except Exception as e:
                logger.warning(f"Could not copy PBIX file: {e}")
    except Exception as e:
        shutil.rmtree(temp_dir)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

    # === Criterion 1: File Existence & Anti-Gaming (15 pts) ===
    if result_data.get("output_exists"):
        if result_data.get("file_created_during_task"):
            score += 15
            feedback.append("File created successfully.")
        else:
            score += 5
            feedback.append("File exists but timestamp is old (pre-existing?).")
    else:
        shutil.rmtree(temp_dir)
        return {"passed": False, "score": 0, "feedback": "Census_Pyramid.pbix not found on Desktop."}

    # === Criterion 2: Internal PBIX Structure (40 pts) ===
    # Unzip PBIX and check Layout
    layout_valid = False
    has_stacked_bar = False
    has_correct_roles = False
    measure_names = []

    if os.path.exists(pbix_path):
        try:
            with zipfile.ZipFile(pbix_path, 'r') as zip_ref:
                # 'Report/Layout' contains the visual configuration
                if 'Report/Layout' in zip_ref.namelist():
                    with zip_ref.open('Report/Layout') as layout_file:
                        layout_json = json.loads(layout_file.read().decode('utf-16-le', errors='ignore'))
                        
                        # Search through sections (pages) and visuals
                        for section in layout_json.get('sections', []):
                            for visual in section.get('visualContainers', []):
                                config_str = visual.get('config')
                                if not config_str: continue
                                config = json.loads(config_str)
                                
                                single_visual = config.get('singleVisual', {})
                                v_type = single_visual.get('visualType', '')
                                
                                if v_type == 'stackedBarChart':
                                    has_stacked_bar = True
                                    
                                    # Check Projections (Data Roles)
                                    # Category (Y) should be Age_Group
                                    # Values (X) should be measures
                                    projections = single_visual.get('projections', {})
                                    category = projections.get('Category', [])
                                    values = projections.get('Y', []) # In bar chart, Y is usually Category, X is Value? 
                                    # Note: Power BI internal names can be tricky. 'Y' in config often maps to the Value axis for horizontal bars.
                                    # Let's check generally for multiple fields in the value role.
                                    
                                    # Usually 'Y' or 'Series' contains the values in a bar chart
                                    p_roles = list(projections.values())
                                    flat_roles = [item for sublist in p_roles for item in sublist]
                                    
                                    # Check for at least 2 measures/fields
                                    if len(flat_roles) >= 3: # 1 Category + 2 Values
                                        has_correct_roles = True
                                    
                                    # Extract query references to find measure names
                                    for item in flat_roles:
                                        if 'queryRef' in item:
                                            measure_names.append(item['queryRef'])
                                    break
        except Exception as e:
            feedback.append(f"Error parsing PBIX: {e}")

    if has_stacked_bar:
        score += 20
        feedback.append("Stacked Bar Chart found.")
    else:
        feedback.append("No Stacked Bar Chart found.")

    if has_correct_roles:
        score += 20
        feedback.append("Visual has multiple data fields (likely Age + 2 Genders).")
    else:
        feedback.append("Visual configuration incomplete (missing fields?).")

    # === Criterion 3: Visual Verification via VLM (45 pts) ===
    # We check:
    # 1. Pyramid Shape (diverging bars)
    # 2. Positive Labels on Negative Side (Formatting)
    
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        prompt = """
        You are verifying a Power BI report task. 
        The user was asked to create a 'Population Pyramid' (Tornado Chart).
        
        Look at the screenshot and answer:
        1. Is there a chart that looks like a Population Pyramid? (Bars extending left and right from a center axis).
        2. Are there TWO series/colors (representing Male and Female)?
        3. Look at the X-axis at the bottom. Do the numbers on the LEFT side appear positive (e.g. "10K" or "10000") or negative (e.g. "-10K")? 
           - The task REQUIRED them to be formatted as POSITIVE numbers.
        4. Are the Age Groups (Y-axis) sorted correctly (0-4 at one end, 85+ at the other) rather than randomly?
        
        Respond in JSON:
        {
            "is_pyramid": true/false,
            "has_two_series": true/false,
            "negative_axis_hidden": true/false,
            "sorted_correctly": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_resp = query_vlm(image=final_screenshot, prompt=prompt)
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            
            if parsed.get("is_pyramid"):
                vlm_score += 15
                feedback.append("VLM confirms Pyramid shape.")
            
            if parsed.get("has_two_series"):
                vlm_score += 10
                feedback.append("VLM confirms two gender series.")
                
            if parsed.get("negative_axis_hidden"):
                vlm_score += 10
                feedback.append("VLM confirms negative signs are hidden (formatting success).")
            else:
                feedback.append("VLM sees negative signs on the axis (formatting failed).")
                
            if parsed.get("sorted_correctly"):
                vlm_score += 10
                feedback.append("VLM confirms correct sort order.")
        else:
            feedback.append("VLM verification failed to run.")
    else:
        feedback.append("No screenshot available for visual verification.")

    score += vlm_score

    # Cleanup
    shutil.rmtree(temp_dir)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }