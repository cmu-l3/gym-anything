#!/usr/bin/env python3
"""
Verifier for attach_source_dose_lib task.

Criteria:
1. .classpath file must exist and be valid XML (20 pts)
2. .classpath must have been modified during the task (20 pts)
3. The dose-engine.jar entry must have a 'sourcepath' attribute (30 pts)
4. The 'sourcepath' must point to the correct zip file (30 pts)
"""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_attach_source(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_zip_name = metadata.get('src_zip_name', 'dose-engine-src.zip')

    score = 0
    feedback_parts = []
    
    # Read result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # Criterion 1: .classpath exists
    if not result.get('classpath_exists'):
        return {"passed": False, "score": 0, "feedback": "Project configuration (.classpath) not found"}
    
    score += 20
    feedback_parts.append(".classpath exists")

    # Criterion 2: Modified during task
    if result.get('classpath_modified'):
        score += 20
        feedback_parts.append("Configuration modified")
    else:
        feedback_parts.append("Configuration NOT modified (did you save?)")

    # Parse XML content
    classpath_content = result.get('classpath_content', '')
    if not classpath_content:
        return {"passed": False, "score": score, "feedback": "Empty classpath file"}

    try:
        root = ET.fromstring(classpath_content)
        jar_entry = None
        
        # Look for the library entry
        for entry in root.findall("classpathentry"):
            path_attr = entry.get("path", "")
            if entry.get("kind") == "lib" and "dose-engine.jar" in path_attr:
                jar_entry = entry
                break
        
        if jar_entry is None:
            feedback_parts.append("dose-engine.jar removed from build path!")
        else:
            # Criterion 3: Check for sourcepath attribute
            sourcepath = jar_entry.get("sourcepath")
            
            if sourcepath:
                score += 30
                feedback_parts.append("Source attachment detected")
                
                # Criterion 4: Verify it points to the correct zip
                # We accept absolute path or name match
                if expected_zip_name in sourcepath:
                    score += 30
                    feedback_parts.append(f"Correct source file attached ({expected_zip_name})")
                else:
                    feedback_parts.append(f"Wrong source file attached: {sourcepath}")
            else:
                feedback_parts.append("No sourcepath attribute found on jar entry")

    except ET.ParseError:
        feedback_parts.append("Invalid XML in .classpath")
        score = 0

    # VLM Verification for UI confirmation
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from eclipse_verification_utils import vlm_verify_eclipse_task

        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Attach source zip to library in Java Build Path",
            checklist_items=[
                "Eclipse IDE is open",
                "Properties dialog or Build Path Configure dialog is visible",
                "Source Attachment Configuration dialog is visible",
                "The source file 'dose-engine-src.zip' was selected",
                "Java source code is visible in the editor (not 'Source not found')"
            ]
        )
        
        if vlm_result and vlm_result.get('vlm_passed'):
            # Bonus or validation confirmation
            if score < 100:
                score = min(score + 10, 100)
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
            
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    passed = score >= 100
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }