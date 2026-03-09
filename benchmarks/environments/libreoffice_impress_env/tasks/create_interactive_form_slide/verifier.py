#!/usr/bin/env python3
"""
Verifier for create_interactive_form_slide task.
Verifies ODP file structure for specific form controls.
"""

import json
import os
import zipfile
import tempfile
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_interactive_form(traj, env_info, task_info):
    """
    Verify that specific form controls exist in the ODP file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_controls = metadata.get('expected_controls', [])
    target_file = metadata.get('target_file', "/home/ga/Documents/Presentations/warehouse_safety.odp")

    # 1. Retrieve Result JSON to check basics
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task status"}

    if not task_result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    if not task_result.get("file_modified"):
        return {"passed": False, "score": 0, "feedback": "File was not modified/saved during task"}

    # 2. Retrieve ODP File
    temp_odp = tempfile.NamedTemporaryFile(suffix=".odp", delete=False)
    temp_odp.close()
    
    try:
        copy_from_env(target_file, temp_odp.name)
    except Exception as e:
        os.unlink(temp_odp.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ODP file: {e}"}

    # 3. Parse ODP Content
    # ODP is a zip, we need content.xml
    score = 10 # Base score for saving file
    feedback = ["File saved successfully"]
    
    try:
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            with z.open('content.xml') as c:
                tree = ET.parse(c)
                root = tree.getroot()

        # Define Namespaces
        namespaces = {
            'form': 'urn:oasis:names:tc:opendocument:xmlns:form:1.0',
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
        }

        # Find all controls
        # Structure is typically office:body -> office:presentation -> draw:page -> office:forms -> form:form -> [controls]
        # We search recursively for form elements
        
        found_controls = []
        
        # Helper to safely get attrib
        def get_attr(elem, attr_name):
            return elem.attrib.get(f"{{{namespaces['form']}}}{attr_name}")

        # Scan for Text Boxes
        for elem in root.findall(".//form:text", namespaces):
            name = get_attr(elem, "name")
            found_controls.append({"type": "text", "name": name, "elem": elem})

        # Scan for Checkboxes
        for elem in root.findall(".//form:checkbox", namespaces):
            name = get_attr(elem, "name")
            label = get_attr(elem, "label")
            found_controls.append({"type": "checkbox", "name": name, "label": label, "elem": elem})

        # Scan for Buttons
        for elem in root.findall(".//form:button", namespaces):
            name = get_attr(elem, "name")
            label = get_attr(elem, "label")
            found_controls.append({"type": "button", "name": name, "label": label, "elem": elem})

        logger.info(f"Found controls: {found_controls}")

        # 4. Verify Against Requirements
        
        # Verify Text Box
        txt_req = next((c for c in expected_controls if c["type"] == "text"), None)
        txt_found = next((c for c in found_controls if c["type"] == "text" and c["name"] == txt_req["name"]), None)
        
        if txt_found:
            score += 30
            feedback.append(f"✅ Text Box '{txt_req['name']}' found")
        else:
            feedback.append(f"❌ Text Box '{txt_req['name']}' missing")

        # Verify Checkbox
        chk_req = next((c for c in expected_controls if c["type"] == "checkbox"), None)
        chk_found = next((c for c in found_controls if c["type"] == "checkbox" and c["name"] == chk_req["name"]), None)
        
        if chk_found:
            score += 20
            feedback.append(f"✅ Checkbox '{chk_req['name']}' found")
            
            # Check Label
            if chk_found.get("label") == chk_req["label"]:
                score += 10
                feedback.append(f"✅ Checkbox label '{chk_req['label']}' correct")
            else:
                feedback.append(f"❌ Checkbox label mismatch (Found: '{chk_found.get('label')}', Expected: '{chk_req['label']}')")
        else:
            feedback.append(f"❌ Checkbox '{chk_req['name']}' missing")

        # Verify Button
        btn_req = next((c for c in expected_controls if c["type"] == "button"), None)
        btn_found = next((c for c in found_controls if c["type"] == "button" and c["name"] == btn_req["name"]), None)
        
        if btn_found:
            score += 20
            feedback.append(f"✅ Button '{btn_req['name']}' found")
            
            # Check Label
            if btn_found.get("label") == btn_req["label"]:
                score += 10
                feedback.append(f"✅ Button label '{btn_req['label']}' correct")
            else:
                feedback.append(f"❌ Button label mismatch")
        else:
            feedback.append(f"❌ Button '{btn_req['name']}' missing")

    except Exception as e:
        logger.error(f"XML Parsing Error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Failed to parse presentation structure: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }