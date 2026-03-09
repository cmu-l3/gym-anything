#!/usr/bin/env python3
"""
Verifier for medical_intake_form_controls task.
Verifies that ODT form controls are correctly inserted and configured.
"""

import json
import os
import sys
import zipfile
import tempfile
import logging
import shutil
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_medical_intake_form(traj, env_info, task_info):
    """
    Verify the ODT document has the correct form controls.
    
    Strategy:
    1. Unzip the .odt file.
    2. Parse content.xml.
    3. Look for <form:form> and <form:control> elements.
    4. Validate control types and names.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_controls = metadata.get('controls', [])
    output_path = metadata.get('output_path', '/home/ga/Documents/intake_form_interactive.odt')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Temporary directory for verification
    temp_dir = tempfile.mkdtemp()
    local_odt = os.path.join(temp_dir, "result.odt")
    
    try:
        # 1. Check File Existence and Modification
        # Read task result json for metadata
        task_result_file = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", task_result_file)
            with open(task_result_file, 'r') as f:
                task_result = json.load(f)
        except Exception:
            task_result = {}

        if not task_result.get("output_exists", False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file not found. Ensure you saved as 'intake_form_interactive.odt'."
            }
        
        score += 10 # File exists
        
        if task_result.get("file_created_during_task", False):
            score += 10
            feedback_parts.append("File saved correctly.")
        else:
            feedback_parts.append("Warning: File timestamp indicates it wasn't modified during task.")

        # 2. XML Parsing of Controls
        try:
            copy_from_env(output_path, local_odt)
            
            if not zipfile.is_zipfile(local_odt):
                return {"passed": False, "score": score, "feedback": "Output is not a valid ODT/ZIP file."}
                
            with zipfile.ZipFile(local_odt, 'r') as z:
                with z.open('content.xml') as f:
                    xml_content = f.read()
            
            # Parse XML
            root = ET.fromstring(xml_content)
            
            # ODF Namespaces
            namespaces = {
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'form': 'urn:oasis:names:tc:opendocument:xmlns:form:1.0',
                'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0'
            }
            
            # Find all controls in the form definitions
            # Structure usually: office:body -> office:text -> office:forms -> form:form -> form:control...
            # We search recursively for form:control
            controls_found = {}
            
            # Find all form elements anywhere
            for elem in root.findall('.//form:radio', namespaces):
                name = elem.get(f"{{{namespaces['form']}}}name")
                value = elem.get(f"{{{namespaces['form']}}}value")
                label = elem.get(f"{{{namespaces['form']}}}label")
                if name:
                    if name not in controls_found: controls_found[name] = []
                    controls_found[name].append({'type': 'radio', 'value': value, 'label': label})
                    
            for elem in root.findall('.//form:checkbox', namespaces):
                name = elem.get(f"{{{namespaces['form']}}}name")
                if name:
                    if name not in controls_found: controls_found[name] = []
                    controls_found[name].append({'type': 'checkbox'})
                    
            for elem in root.findall('.//form:text', namespaces):
                name = elem.get(f"{{{namespaces['form']}}}name")
                if name:
                    if name not in controls_found: controls_found[name] = []
                    controls_found[name].append({'type': 'text'})
            
            # Note: Dates are sometimes stored as form:formatted-text with specific properties, 
            # or form:date. We check for generic text or date.
            for elem in root.findall('.//form:date', namespaces):
                name = elem.get(f"{{{namespaces['form']}}}name")
                if name:
                    if name not in controls_found: controls_found[name] = []
                    controls_found[name].append({'type': 'date'})

            # Verify against expected
            for expected in expected_controls:
                name = expected['name']
                exp_type = expected['type']
                
                if name in controls_found:
                    instances = controls_found[name]
                    # Check types
                    # Map date to text loosely if strict date control not found but text box used
                    match = False
                    for inst in instances:
                        if inst['type'] == exp_type:
                            match = True
                        elif exp_type == 'date' and inst['type'] in ['text', 'formatted-text']:
                            match = True # lenient on date implementation
                    
                    if match:
                        # Scoring logic
                        if exp_type == 'radio':
                            # Require count match for radios
                            count = expected.get('count', 1)
                            if len(instances) >= count:
                                score += 15
                                feedback_parts.append(f"Radio group '{name}': OK ({len(instances)} buttons).")
                            else:
                                score += 5
                                feedback_parts.append(f"Radio group '{name}': Found but only {len(instances)}/{count} buttons.")
                        else:
                            score += 10
                            feedback_parts.append(f"Control '{name}': OK.")
                    else:
                        feedback_parts.append(f"Control '{name}': Found but wrong type.")
                else:
                    feedback_parts.append(f"Control '{name}': MISSING.")

        except Exception as e:
            logger.error(f"XML Parsing failed: {e}")
            feedback_parts.append(f"Verification error: Failed to parse ODT structure ({str(e)}).")

        # 3. VLM Verification (Fallback/Sanity Check)
        frames = sample_trajectory_frames(traj, n=3)
        final_screenshot = get_final_screenshot(traj)
        
        vlm_prompt = """
        Analyze these screenshots of LibreOffice Writer.
        1. Is the 'Form Controls' toolbar visible?
        2. Do you see form elements like Text Boxes, Checkboxes, or Radio Buttons added to the document?
        3. Is the document 'Amani Family Health - New Patient Registration'?
        """
        
        vlm_result = query_vlm(images=frames + [final_screenshot], prompt=vlm_prompt)
        
        if vlm_result.get('success'):
            # Basic sanity bonus if VLM confirms visual elements
            # We don't rely fully on VLM for detail, but it helps verify intent
            score += 10 
        
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }