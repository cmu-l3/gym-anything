#!/usr/bin/env python3
"""
Verifier for mirror_bracket_assembly task.

Verifies:
1. Output FCStd file exists and was created during the task.
2. File size indicates added geometry (mirror).
3. Internal Document.xml contains 'Part::Mirroring' and 'Part::Compound' objects.
4. VLM verifies the trajectory shows usage of Mirror/Compound tools.
"""

import json
import os
import sys
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mirror_bracket_assembly(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Timestamp (Anti-gaming)
    output_exists = result.get("output_exists", False)
    created_during_task = result.get("file_created_during_task", False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not created_during_task:
        return {"passed": False, "score": 0, "feedback": "Output file timestamp predates task start (anti-gaming failure)."}
    
    score += 10
    feedback_parts.append("File created successfully")

    # 3. Check File Size (Should be larger than original)
    out_size = result.get("output_size_bytes", 0)
    orig_size = result.get("original_size_bytes", 0)
    
    if out_size > orig_size * 1.05: # At least 5% larger
        score += 5
        feedback_parts.append("File size increased (geometry added)")
    else:
        feedback_parts.append("Warning: File size similar to original (geometry might be missing)")

    # 4. Analyze FCStd Content (XML Parsing)
    # We need to pull the actual FCStd file from the container to inspect it
    temp_fcstd = tempfile.NamedTemporaryFile(delete=False, suffix='.FCStd')
    has_mirror = False
    has_compound = False
    
    try:
        copy_from_env("/home/ga/Documents/FreeCAD/symmetric_bracket_assembly.FCStd", temp_fcstd.name)
        
        # FCStd is a zip file containing Document.xml
        if zipfile.is_zipfile(temp_fcstd.name):
            with zipfile.ZipFile(temp_fcstd.name, 'r') as zf:
                if 'Document.xml' in zf.namelist():
                    doc_xml = zf.read('Document.xml')
                    root = ET.fromstring(doc_xml)
                    
                    # Namespace handling might be tricky, usually FreeCAD XML is straightforward
                    # Search for Objects
                    objects = root.findall(".//Object")
                    
                    for obj in objects:
                        obj_type = obj.get("type", "")
                        obj_name = obj.get("name", "")
                        
                        # Check for Mirror
                        if "Part::Mirroring" in obj_type or "Mirror" in obj_name:
                            has_mirror = True
                        
                        # Check for Compound
                        if "Part::Compound" in obj_type or "Compound" in obj_name:
                            has_compound = True

        else:
            feedback_parts.append("Output file is not a valid zip/FCStd archive")

    except Exception as e:
        feedback_parts.append(f"Failed to analyze file content: {str(e)}")
    finally:
        if os.path.exists(temp_fcstd.name):
            os.unlink(temp_fcstd.name)

    if has_mirror:
        score += 25
        feedback_parts.append("Mirror object detected")
    else:
        feedback_parts.append("Missing Mirror object")

    if has_compound:
        score += 25
        feedback_parts.append("Compound object detected")
    else:
        feedback_parts.append("Missing Compound object")

    # 5. VLM Verification (Trajectory Analysis)
    # We look for evidence of the "Mirror" dialog or result in the viewport
    frames = sample_trajectory_frames(traj, n=4)
    
    vlm_prompt = """
    Review this sequence of screenshots from FreeCAD.
    The user is supposed to:
    1. Select a bracket part.
    2. Mirror it (create a symmetric copy).
    3. Create a Compound of the original and the mirror.
    
    Do you see:
    - Two symmetric bracket shapes (left/right) visible at the same time?
    - The "Mirror" tool or dialog being used?
    - The "Compound" tool being used or a Compound object in the tree?
    
    Answer JSON: {"symmetric_view_visible": bool, "mirror_tool_used": bool, "compound_tool_used": bool}
    """
    
    vlm_result = query_vlm(frames, vlm_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    vlm_score = 0
    if vlm_data.get("symmetric_view_visible"):
        vlm_score += 15
        feedback_parts.append("VLM: Symmetric assembly visible")
    if vlm_data.get("mirror_tool_used"):
        vlm_score += 10
        feedback_parts.append("VLM: Mirror tool usage detected")
    if vlm_data.get("compound_tool_used"):
        vlm_score += 10
        feedback_parts.append("VLM: Compound tool usage detected")
        
    score += vlm_score

    # Final scoring
    passed = (score >= 60 and has_mirror and has_compound)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }