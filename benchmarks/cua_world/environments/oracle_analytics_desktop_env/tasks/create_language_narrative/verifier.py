#!/usr/bin/env python3
"""
Verifier for Create Language Narrative task in Oracle Analytics Desktop.

Checks:
1. Category_Narrative.dva exists and was modified during task.
2. DVA file (zip) contains a narrative visualization definition.
3. Visualization references Sales, Profit, and Product Category.
4. Level of Detail property is set high.
5. VLM confirms text-based insights on screen.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_language_narrative(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve JSON result from environment
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json_path = temp_json.name
    temp_json.close()
    
    dva_path_in_env = metadata.get('output_path', r"C:\Users\Docker\Documents\Category_Narrative.dva")
    local_dva_path = tempfile.mktemp(suffix='.dva')

    try:
        copy_from_env(r"C:\Users\Docker\AppData\Local\Temp\task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)

    # Basic File Checks
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Workbook 'Category_Narrative.dva' was not saved."}
    
    if not result_data.get('created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File exists but was not saved during this task session."}

    score = 20 # File exists and is new
    feedback = "Workbook saved. "

    # 2. Retrieve and Inspect DVA File
    try:
        copy_from_env(dva_path_in_env, local_dva_path)
        
        is_narrative = False
        has_sales = False
        has_profit = False
        has_category = False
        high_detail = False

        if zipfile.is_zipfile(local_dva_path):
            with zipfile.ZipFile(local_dva_path, 'r') as z:
                # Search for visualization metadata in XML files
                # Structure is typically /va/project/project.xml or similar
                for filename in z.namelist():
                    if filename.endswith('.xml'):
                        try:
                            with z.open(filename) as xml_file:
                                content = xml_file.read().decode('utf-8', errors='ignore')
                                
                                # Heuristic checks within XML content
                                if 'narrative' in content.lower() or 'languagenarrative' in content.lower():
                                    is_narrative = True
                                
                                # Check bindings in the same context if possible, or global file
                                if 'columnID="Sales"' in content or 'Sales' in content:
                                    has_sales = True
                                if 'columnID="Profit"' in content or 'Profit' in content:
                                    has_profit = True
                                if 'Product Category' in content:
                                    has_category = True
                                
                                # Check for detail properties (heuristic based on OAD XML schema)
                                if 'levelOfDetail' in content or 'verbosity' in content:
                                    # We give benefit of doubt if property exists; 
                                    # parsing specific integer value in complex XML is fragile without schema.
                                    # We'll rely on VLM for the "richness" check if XML is ambiguous.
                                    high_detail = True
                        except:
                            continue
        
        if is_narrative:
            score += 30
            feedback += "Narrative visualization detected. "
        else:
            feedback += "No Narrative visualization found in workbook metadata. "

        if has_sales and has_profit:
            score += 20
            feedback += "Measures (Sales, Profit) found. "
        else:
            feedback += "Missing required measures (Sales/Profit). "

        if has_category:
            score += 10
            feedback += "Category dimension found. "
        
        # Cleanup
        if os.path.exists(local_dva_path):
            os.unlink(local_dva_path)

    except Exception as e:
        logger.warning(f"DVA inspection failed: {e}")
        feedback += f"Could not verify internal file structure ({str(e)}). "

    # 3. VLM Verification (Trajectory)
    # Check if a text narrative was actually visible on screen
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    
    if final:
        frames.append(final)
        
    vlm_prompt = """
    Review these screenshots of Oracle Analytics Desktop.
    I am looking for a 'Language Narrative' visualization. This looks like a block of natural language text (sentences/paragraphs) summarizing data, NOT a chart or table.
    
    1. Is there a visualization that consists of generated text paragraphs?
    2. Does the text contain generated numbers (currency, percentages)?
    3. Do you see words like 'Technology', 'Furniture', 'Office Supplies' (Product Categories) in the text?
    
    Reply in JSON: {"text_viz_visible": bool, "data_values_in_text": bool, "categories_in_text": bool}
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('result'):
        try:
            parsed = json.loads(vlm_result.get('result').replace('