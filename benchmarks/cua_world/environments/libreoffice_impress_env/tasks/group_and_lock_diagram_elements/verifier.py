#!/usr/bin/env python3
"""
Verifier for Group and Lock Diagram Elements task.

Verification Logic:
1. Checks if the output ODP file exists and was modified during the task.
2. Parses the ODP content (content.xml) to identify grouped elements (<draw:g>).
3. Verifies the group contains exactly the 4 shape elements.
4. Verifies the text labels are NOT in the group.
5. Verifies the group has 'position' and 'size' protection enabled.
"""

import json
import tempfile
import os
import zipfile
import logging
import shutil
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_group_and_lock(traj, env_info, task_info):
    """
    Verify that the agent grouped the shapes and locked the group.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/Presentations/cell_biology_locked.odp')

    # 1. Get result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Check file existence and anti-gaming
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file 'cell_biology_locked.odp' not found."}
    
    if not result_data.get('file_modified_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task session."}

    # 2. Get the ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    temp_odp.close()
    
    try:
        copy_from_env(expected_output_path, temp_odp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to copy output ODP file: {e}"}

    # 3. Analyze ODP Content
    score = 10  # Base score for file existence
    feedback_parts = ["File saved successfully"]
    
    try:
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            with z.open('content.xml') as f:
                content_xml = f.read()
        
        # Parse XML
        # Namespaces in ODF are heavy, usually need to handle them
        # draw namespace is usually urn:oasis:names:tc:opendocument:xmlns:drawing:1.0
        ns = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
        }
        
        root = ET.fromstring(content_xml)
        
        # Find the slide (draw:page)
        # We assume the work is on the first slide
        body = root.find('.//office:body/office:presentation', ns)
        if body is None:
             raise ValueError("Invalid ODP structure: no presentation body")
             
        pages = body.findall('draw:page', ns)
        if not pages:
            raise ValueError("No slides found in presentation")
            
        slide1 = pages[0]
        
        # FIND GROUPS
        groups = slide1.findall('draw:g', ns)
        
        # Logic: We expect one main group containing the shapes.
        target_group = None
        
        # Identify the correct group by checking its children
        for g in groups:
            # Check children types
            children = list(g)
            
            # Count shapes (ellipse/circle/custom-shape) vs text boxes (frame with text-box)
            shapes_count = 0
            text_boxes_count = 0
            
            for child in children:
                tag = child.tag
                if 'ellipse' in tag or 'circle' in tag or 'custom-shape' in tag or 'rect' in tag:
                    shapes_count += 1
                elif 'frame' in tag:
                    # Check if it contains a text box or text
                    if child.find('.//draw:text-box', ns) is not None or child.find('.//text:p', ns) is not None:
                        text_boxes_count += 1
            
            # We expect 4 shapes (2 circles, 2 ovals) and 0 text boxes
            if shapes_count >= 3 and text_boxes_count == 0:
                target_group = g
                break
        
        # SCORING CRITERIA
        
        # Criterion 1: Group Created (30 pts)
        if target_group is not None:
            score += 30
            feedback_parts.append("Correctly grouped the diagram shapes")
        else:
            feedback_parts.append("FAIL: No group found containing the diagram shapes")
            # If no group, we can't give points for locking
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
            
        # Criterion 2: Text Labels Excluded (20 pts)
        # Verified during group selection above (text_boxes_count == 0)
        # Let's double check that text boxes exist OUTSIDE the group on the slide
        ungrouped_frames = slide1.findall('draw:frame', ns)
        ungrouped_text_count = 0
        for frame in ungrouped_frames:
             if frame.find('.//text:p', ns) is not None:
                 ungrouped_text_count += 1
                 
        if ungrouped_text_count >= 3: # Allow some tolerance, but we expect 4
            score += 20
            feedback_parts.append("Text labels correctly left ungrouped")
        else:
            feedback_parts.append(f"FAIL: Found only {ungrouped_text_count} text labels outside group (expected 4). Did you group them?")
            score -= 10 # Penalty if they grouped everything
            
        # Criterion 3: Position Locked (20 pts)
        # Check draw:protect attribute
        # Attribute value can be "position" or "position size" or "size position"
        protect_attr = target_group.get(f"{{{ns['draw']}}}protect", "")
        
        if "position" in protect_attr:
            score += 20
            feedback_parts.append("Position protection verified")
        else:
            feedback_parts.append("FAIL: Position is not locked")
            
        # Criterion 4: Size Locked (20 pts)
        if "size" in protect_attr:
            score += 20
            feedback_parts.append("Size protection verified")
        else:
            feedback_parts.append("FAIL: Size is not locked")

    except Exception as e:
        logger.error(f"Error parsing ODP: {e}")
        return {"passed": False, "score": score, "feedback": f"File verification failed: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }