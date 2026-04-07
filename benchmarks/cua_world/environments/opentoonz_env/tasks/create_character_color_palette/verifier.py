#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def parse_opentoonz_palette(file_path):
    """
    Parses an OpenToonz .tpl file (XML) and extracts styles.
    Returns a dictionary: { "StyleName": (r, g, b), ... }
    """
    styles_found = {}
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        # Traverse the XML structure.
        # Structure varies, but usually <style> tags contain <name> and <color>
        # We search recursively for all <style> tags
        for style in root.findall(".//style"):
            name_tag = style.find("name")
            color_tag = style.find("color")
            
            if name_tag is not None and color_tag is not None:
                name = name_tag.text
                
                # Color val is usually "R G B M" (M=Alpha) e.g., "255 0 0 255"
                val_str = color_tag.get("val")
                if val_str:
                    try:
                        parts = list(map(int, val_str.split()))
                        if len(parts) >= 3:
                            rgb = tuple(parts[:3]) # Take first 3 (R, G, B)
                            styles_found[name] = rgb
                    except ValueError:
                        continue
                        
    except ET.ParseError:
        logger.error("Failed to parse TPL file: Invalid XML")
        return None
    except Exception as e:
        logger.error(f"Error reading palette file: {e}")
        return None
        
    return styles_found

def verify_create_character_color_palette(traj, env_info, task_info):
    """
    Verifies that the agent created a .tpl file with the correct styles.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    required_styles = metadata.get('required_styles', [])
    output_path = metadata.get('output_path', '/home/ga/OpenToonz/outputs/cyber_detective.tpl')

    # Retrieve the result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_result_json = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json)
        with open(temp_result_json, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result_json):
            os.remove(temp_result_json)

    # 2. Check File Existence and Timestamp (Anti-gaming)
    if not task_result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Palette file 'cyber_detective.tpl' was not found in the output directory."}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "A palette file exists, but it was not created during this task session."}

    # 3. Retrieve and Parse the Palette File
    with tempfile.NamedTemporaryFile(delete=False, suffix='.tpl') as f:
        temp_tpl_path = f.name

    try:
        copy_from_env(output_path, temp_tpl_path)
        parsed_styles = parse_opentoonz_palette(temp_tpl_path)
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"File exists but could not be copied or read: {e}"}
    finally:
        if os.path.exists(temp_tpl_path):
            os.remove(temp_tpl_path)

    if parsed_styles is None:
        return {"passed": False, "score": 10, "feedback": "File exists but is not a valid OpenToonz Palette (XML) file."}

    # 4. Score the Styles
    score = 15 # Base score for valid file created during task
    feedback = ["File created successfully."]
    
    matches = 0
    total_required = len(required_styles)
    
    for req in required_styles:
        req_name = req['name']
        req_rgb = tuple(req['rgb'])
        tolerance = req.get('tolerance', 2)
        
        # Check if style name exists (case-insensitive search)
        found_rgb = None
        found_real_name = None
        
        for s_name, s_rgb in parsed_styles.items():
            if s_name and s_name.lower() == req_name.lower():
                found_rgb = s_rgb
                found_real_name = s_name
                break
        
        if found_rgb:
            # Check RGB values
            r_diff = abs(found_rgb[0] - req_rgb[0])
            g_diff = abs(found_rgb[1] - req_rgb[1])
            b_diff = abs(found_rgb[2] - req_rgb[2])
            
            if r_diff <= tolerance and g_diff <= tolerance and b_diff <= tolerance:
                score += 25
                matches += 1
                feedback.append(f"✓ Style '{req_name}' matches ({found_rgb}).")
            else:
                score += 5 # Partial credit for correct name but wrong color
                feedback.append(f"⚠ Style '{req_name}' found, but color {found_rgb} mismatch expected {req_rgb}.")
        else:
            feedback.append(f"✗ Style '{req_name}' missing.")

    # 5. Final Calculation
    # Max score calculation: 15 (base) + 3 * 25 (styles) = 90. 
    # Let's adjust slightly: make Base 25 if valid XML. 25 + 75 = 100.
    if parsed_styles is not None:
        score += 10 # Bonus for valid XML structure
    
    score = min(100, score)
    passed = (matches >= 2) and (score >= 60) # Pass if at least 2/3 colors are correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }