#!/usr/bin/env python3
"""
Verifier for newsletter_linked_frames_flow task.
Checks for the existence of linked text frames in an ODT file using XML parsing.
"""

import os
import sys
import json
import zipfile
import tempfile
import shutil
import logging
from xml.dom import minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_linked_frames(traj, env_info, task_info):
    """
    Verifies that the agent created linked text frames and flowed text into them.
    
    Criteria:
    1. Output file exists and was modified during task.
    2. Document contains at least 2 text frames.
    3. Frames are logically linked (draw:chain-next-name attribute present).
    4. Target content ("Letter from the President") is INSIDE a frame.
    5. Target content is NOT in the main body.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    target_text = metadata.get('target_story_content_fragment', "As we welcome the first green shoots")
    target_title = metadata.get('target_story_title', "Letter from the President")
    
    # Load export result
    result_json_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)

    if not export_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file 'newsletter_final.odt' not found."}

    # 2. Retrieve ODT File
    temp_odt_path = tempfile.mktemp(suffix=".odt")
    try:
        copy_from_env("/home/ga/Documents/newsletter_final.odt", temp_odt_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ODT file: {e}"}

    # 3. Parse ODT Content (XML in Zip)
    score = 0
    feedback = []
    
    try:
        with zipfile.ZipFile(temp_odt_path, 'r') as z:
            content_xml = z.read('content.xml')
        
        dom = minidom.parseString(content_xml)
        
        # Namespaces commonly used in ODT
        # We'll search tags by local name to avoid namespace hell in simple verification
        
        # Find all frames
        frames = dom.getElementsByTagName('draw:frame')
        text_boxes = dom.getElementsByTagName('draw:text-box')
        
        # --- Check 1: Frames Existence (20 pts) ---
        if len(frames) >= 2:
            score += 20
            feedback.append(f"Found {len(frames)} frames (Pass)")
        else:
            feedback.append(f"Found {len(frames)} frames (Fail: Need at least 2)")
        
        # --- Check 2: Linked Frames (30 pts) ---
        # Look for 'draw:chain-next-name' attribute
        linked_frames_count = 0
        for frame in frames:
            if frame.hasAttribute('draw:chain-next-name'):
                linked_frames_count += 1
                
        if linked_frames_count > 0:
            score += 30
            feedback.append(f"Found {linked_frames_count} linked frames (Pass)")
        else:
            feedback.append("No linked frames found (Fail: Missing 'chain-next-name' attribute)")

        # --- Check 3: Content Location (50 pts) ---
        # Extract text from main body vs text boxes
        
        # Function to get text from a node
        def get_text(node):
            rc = []
            for child in node.childNodes:
                if child.nodeType == child.TEXT_NODE:
                    rc.append(child.data)
                else:
                    rc.append(get_text(child))
            return ''.join(rc)

        # Get body text (excluding frames)
        office_text = dom.getElementsByTagName('office:text')[0]
        # We need to be careful: office:text contains frames as children. 
        # We want to check if the text is direct child of body OR inside a frame.
        
        # Let's verify if target text is inside a text-box
        content_in_frame = False
        for tb in text_boxes:
            tb_text = get_text(tb)
            if target_text[:20] in tb_text: # Check a fragment
                content_in_frame = True
                break
        
        # Check if content is still in the main flow (orphaned from frames)
        # We iterate over paragraphs that are NOT children of a frame
        content_in_body = False
        all_paras = dom.getElementsByTagName('text:p')
        for p in all_paras:
            # Check if this paragraph's parent is a text-box
            parent = p.parentNode
            is_frame_child = False
            while parent:
                if parent.nodeName == 'draw:text-box':
                    is_frame_child = True
                    break
                parent = parent.parentNode
            
            if not is_frame_child:
                p_text = get_text(p)
                if target_text[:20] in p_text:
                    content_in_body = True
                    break

        if content_in_frame:
            score += 30
            feedback.append("Target text found inside a frame (Pass)")
        else:
            feedback.append("Target text NOT found inside any frame (Fail)")

        if not content_in_body:
            score += 20
            feedback.append("Target text correctly removed from main body (Pass)")
        else:
            # If it's in both (copy-paste error), they lose points
            feedback.append("Target text still found in main body (Fail: Move, don't just copy)")

    except Exception as e:
        logger.error(f"Verification Error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification failed with error: {str(e)}"}
    finally:
        if os.path.exists(temp_odt_path):
            os.remove(temp_odt_path)

    # Final Pass/Fail Logic
    # Must have linked frames AND content in frames
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }