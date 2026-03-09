#!/usr/bin/env python3
"""
Verifier for Create Custom Icons (Boolean Operations) task.
Verifies that primitives have been converted into single vector paths.
"""

import json
import tempfile
import os
import zipfile
import logging
from xml.dom import minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_icons(traj, env_info, task_info):
    """
    Verify that shapes were combined using Boolean operations.
    
    Strategy:
    1. Unzip the ODP file.
    2. Parse content.xml.
    3. Iterate through slides.
    4. Slide 1 (Subtract): Should NOT have 'draw:rect' or 'draw:ellipse'. Should have 'draw:path' or 'draw:custom-shape'. Count should be 1 (excluding text frames).
    5. Slide 2 (Union): Should NOT have 'draw:ellipse'. Should have 'draw:path' or 'draw:custom-shape'. Count should be 1.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    target_file = task_info.get('metadata', {}).get('target_file', '/home/ga/Documents/Presentations/icons_draft.odp')

    # 1. Check basic file status from export result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found."}
    
    if not result_data.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "File was not modified (did you save?)."}

    # 2. Retrieve and parse the ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(target_file, temp_odp.name)
        
        if not zipfile.is_zipfile(temp_odp.name):
             return {"passed": False, "score": 0, "feedback": "Saved file is not a valid ODP archive."}

        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            with z.open('content.xml') as f:
                content_xml = f.read()
                
        dom = minidom.parseString(content_xml)
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse ODP file: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    # 3. Analyze Slides
    score = 0
    feedback = []
    
    # Namespaces usually found in ODF
    # Note: minidom tag names include namespace prefix if present in the raw XML, 
    # e.g., 'draw:page', 'draw:rect'.
    
    pages = dom.getElementsByTagName('draw:page')
    if len(pages) < 2:
        return {"passed": False, "score": 0, "feedback": "Presentation has fewer than 2 slides."}

    # --- Verify Slide 1 (Server Asset - Subtract) ---
    slide1 = pages[0]
    s1_shapes = get_draw_objects(slide1)
    
    # We expect the text frame (instruction) to remain, so we ignore frames containing textboxes with instructions
    s1_shapes = [s for s in s1_shapes if not is_instruction_frame(s)]
    
    s1_passed = False
    if len(s1_shapes) == 1:
        shape_type = s1_shapes[0].tagName
        if shape_type in ['draw:path', 'draw:custom-shape', 'draw:poly-polygon']:
            score += 50
            feedback.append("Slide 1: Success (Subtract operation confirmed).")
            s1_passed = True
        elif shape_type == 'draw:g':
            feedback.append("Slide 1: Shape is a Group, not a Boolean result. Use 'Subtract', not 'Group'.")
        else:
            feedback.append(f"Slide 1: Unexpected shape type '{shape_type}'.")
    else:
        feedback.append(f"Slide 1: Expected 1 merged object, found {len(s1_shapes)} objects. (Did you select all and Subtract?)")
        
    # --- Verify Slide 2 (Cloud Asset - Union) ---
    slide2 = pages[1]
    s2_shapes = get_draw_objects(slide2)
    s2_shapes = [s for s in s2_shapes if not is_instruction_frame(s)]
    
    s2_passed = False
    if len(s2_shapes) == 1:
        shape_type = s2_shapes[0].tagName
        if shape_type in ['draw:path', 'draw:custom-shape', 'draw:poly-polygon']:
            score += 50
            feedback.append("Slide 2: Success (Union operation confirmed).")
            s2_passed = True
        elif shape_type == 'draw:g':
            feedback.append("Slide 2: Shape is a Group, not a Boolean result. Use 'Union', not 'Group'.")
        else:
            feedback.append(f"Slide 2: Unexpected shape type '{shape_type}'.")
    else:
        feedback.append(f"Slide 2: Expected 1 merged object, found {len(s2_shapes)} objects. (Did you select all and Union?)")

    passed = s1_passed and s2_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }

def get_draw_objects(page_element):
    """
    Recursively find all draw objects that are NOT inside a group (top-level on page).
    Relevant tags: rect, ellipse, path, custom-shape, g, poly-polygon, circle
    """
    relevant_tags = [
        'draw:rect', 'draw:ellipse', 'draw:circle', 
        'draw:path', 'draw:custom-shape', 'draw:poly-polygon',
        'draw:g', 'draw:frame' # Include frame to check for text
    ]
    
    objects = []
    for child in page_element.childNodes:
        if child.nodeType == child.ELEMENT_NODE:
            if child.tagName in relevant_tags:
                objects.append(child)
    return objects

def is_instruction_frame(element):
    """
    Check if an element is likely the instruction text frame.
    """
    if element.tagName != 'draw:frame':
        return False
    
    # Check if it contains a textbox
    textboxes = element.getElementsByTagName('draw:text-box')
    if textboxes:
        return True
    return False