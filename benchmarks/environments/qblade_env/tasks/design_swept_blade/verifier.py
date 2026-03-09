#!/usr/bin/env python3
"""
Verifier for design_swept_blade task.

Checks:
1. `swept_blade.wpa` exists and is a valid XML file.
2. The blade geometry in the WPA file has the correct tip offsets:
   - X-Offset (Sweep) ~= 2.0
   - Y-Offset (Pre-bend) ~= 1.5
3. `swept_blade.stl` exists (evidence of export).
"""

import json
import tempfile
import os
import logging
import xml.etree.ElementTree as ET
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_swept_blade(traj, env_info, task_info):
    """Verify blade geometry modification."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_x = metadata.get('target_x_offset', 2.0)
    target_y = metadata.get('target_y_offset', 1.5)
    tolerance = metadata.get('tolerance', 0.1)

    # 1. Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check basic file existence
    if not result.get('project_exists', False):
        return {"passed": False, "score": 0, "feedback": "Project file swept_blade.wpa not found."}
    
    score += 20
    feedback_parts.append("Project file saved.")

    if result.get('stl_exists', False):
        score += 20
        feedback_parts.append("STL file exported.")
    else:
        feedback_parts.append("STL file missing.")

    # 2. Analyze WPA file content for geometry
    project_path = result.get('project_path')
    temp_wpa = tempfile.NamedTemporaryFile(delete=False, suffix='.wpa')
    
    x_found = None
    y_found = None
    
    try:
        copy_from_env(project_path, temp_wpa.name)
        
        # QBlade .wpa files are XML. We parse to find Blade Sections.
        # Structure is typically: <Blade> ... <Section> ... <XOff>val</XOff> ... </Section> </Blade>
        # We need the LAST section (Tip).
        
        tree = ET.parse(temp_wpa.name)
        root = tree.getroot()
        
        # Find all Section elements. Depending on schema versions, they might be nested differently.
        # We'll search recursively for "Section" or similar tags that contain offset data.
        # A robust way is to find all elements named "Section" and look at the last one.
        
        sections = []
        # Try finding Section tags anywhere
        for elem in root.iter():
            if 'Section' in elem.tag:
                # Check if this section has offset data
                x_tag = elem.find('XOff')
                y_tag = elem.find('YOff')
                if x_tag is not None and y_tag is not None:
                    sections.append(elem)
        
        if not sections:
            # Fallback: QBlade might use different tag names in some versions or context
            # Let's try to regex search the file for the pattern if XML parsing fails to find semantic tags
            with open(temp_wpa.name, 'r') as f:
                content = f.read()
                # Look for patterns like <XOff>2.000</XOff>
                # We find all matches and take the last one
                x_matches = re.findall(r'<XOff>([\d\.\-]+)</XOff>', content)
                y_matches = re.findall(r'<YOff>([\d\.\-]+)</YOff>', content)
                
                if x_matches:
                    x_found = float(x_matches[-1])
                if y_matches:
                    y_found = float(y_matches[-1])
        else:
            # We found sections via XML, take the last one
            last_section = sections[-1]
            try:
                x_found = float(last_section.find('XOff').text)
                y_found = float(last_section.find('YOff').text)
            except (ValueError, AttributeError):
                feedback_parts.append("Could not parse offset values from XML section.")

    except ET.ParseError:
        feedback_parts.append("Project file is not valid XML.")
    except Exception as e:
        feedback_parts.append(f"Error analyzing project file: {str(e)}")
    finally:
        if os.path.exists(temp_wpa.name):
            os.unlink(temp_wpa.name)

    # 3. Score Geometry
    geo_score = 0
    
    # Check X-Offset (Sweep)
    if x_found is not None:
        if abs(x_found - target_x) <= tolerance:
            geo_score += 30
            feedback_parts.append(f"Tip Sweep (X-Offset) correct: {x_found}")
        else:
            feedback_parts.append(f"Tip Sweep incorrect: found {x_found}, expected {target_x}")
    else:
        feedback_parts.append("Could not identify Tip Sweep value")

    # Check Y-Offset (Pre-bend)
    if y_found is not None:
        if abs(y_found - target_y) <= tolerance:
            geo_score += 30
            feedback_parts.append(f"Tip Pre-bend (Y-Offset) correct: {y_found}")
        else:
            feedback_parts.append(f"Tip Pre-bend incorrect: found {y_found}, expected {target_y}")
    else:
        feedback_parts.append("Could not identify Tip Pre-bend value")

    score += geo_score
    
    # Anti-gaming: Ensure file was modified/created during task
    if not result.get('file_created_during_task', False):
        score = 0
        feedback_parts.append("FAILED: Output file timestamp indicates it was not created during this task.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }