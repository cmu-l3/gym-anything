#!/usr/bin/env python3
"""
Verifier for insert_math_equations task.
Verifies ODP structure and embedded Math objects.
"""

import json
import os
import sys
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insert_math_equations(traj, env_info, task_info):
    """
    Verify that 3 math formula objects were inserted on slides 2, 3, and 4.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define namespaces used in ODP XML
    NS = {
        'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
        'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
        'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0',
        'xlink': 'http://www.w3.org/1999/xlink'
    }

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Target presentation file not found."}

    if not result_data.get("file_modified"):
        feedback_parts.append("⚠️ File was not modified (timestamp unchanged)")
    else:
        score += 10
        feedback_parts.append("File modified successfully")

    # 2. Retrieve ODP File
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env("/tmp/verification_file.odp", temp_odp.name)
        
        if not zipfile.is_zipfile(temp_odp.name):
            return {"passed": False, "score": score, "feedback": "Result file is not a valid ODP/ZIP archive"}

        with zipfile.ZipFile(temp_odp.name, 'r') as zf:
            # Check content.xml
            if 'content.xml' not in zf.namelist():
                return {"passed": False, "score": score, "feedback": "Invalid ODP: content.xml missing"}
            
            content_xml = zf.read('content.xml')
            root = ET.fromstring(content_xml)

            # Find all slides
            # Note: Slides are usually draw:page elements inside office:presentation
            # But sometimes namespaced differently depending on version
            slides = root.findall('.//draw:page', NS)
            
            if len(slides) != 5:
                feedback_parts.append(f"⚠️ Slide count changed: Found {len(slides)}, expected 5")
            else:
                score += 10
                feedback_parts.append("Slide count preserved (5)")

            # Check for embedded objects on Slide 2, 3, 4 (Index 1, 2, 3)
            # ODP stores embedded formulas as draw:frame containing draw:object or draw:object-ole
            target_indices = [1, 2, 3] # Slides 2, 3, 4
            equations_found = 0
            
            for i in target_indices:
                if i >= len(slides):
                    break
                    
                slide = slides[i]
                slide_has_formula = False
                
                # Look for object frames
                frames = slide.findall('.//draw:frame', NS)
                for frame in frames:
                    # Check for direct object child
                    obj = frame.find('./draw:object', NS)
                    obj_ole = frame.find('./draw:object-ole', NS)
                    
                    if obj is not None or obj_ole is not None:
                        slide_has_formula = True
                        break
                        
                if slide_has_formula:
                    equations_found += 1
                    score += 20 # 20 points per correct slide
                    feedback_parts.append(f"✅ Equation found on Slide {i+1}")
                else:
                    feedback_parts.append(f"❌ No formula object found on Slide {i+1}")

            # Check if embedded objects actually exist in the zip (Formula objects are subdirs like 'Object 1')
            embedded_dirs = [n for n in zf.namelist() if 'Object' in n and n.endswith('content.xml')]
            if len(embedded_dirs) >= 3:
                score += 20
                feedback_parts.append(f"Found {len(embedded_dirs)} embedded object definitions")
            elif len(embedded_dirs) > 0:
                score += 10
                feedback_parts.append(f"Found {len(embedded_dirs)} embedded object definitions (expected 3+)")
            else:
                feedback_parts.append("No embedded object definitions found in archive")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error parsing ODP: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }