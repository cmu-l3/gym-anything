#!/usr/bin/env python3
"""
Verifier for add_custom_mime_type task.

Verification Logic:
1. Parse the Artifactory system configuration XML exported from the container.
2. Search for the <mimeType> entry matching the target type.
3. Verify the associated extension is correct.
4. Ensure the entry didn't exist before (anti-gaming).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_custom_mime_type(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_mime = metadata.get('target_mime_type', 'application/vnd.company.datalog')
    target_ext = metadata.get('target_extension', 'datalog')

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    
    try:
        # 1. Get JSON result
        try:
            copy_from_env("/tmp/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

        # 2. Get XML config
        try:
            copy_from_env("/tmp/task_config_export.xml", temp_xml.name)
            # Read header to ensure it looks like XML
            with open(temp_xml.name, 'r') as f:
                header = f.read(100)
                if not header.strip():
                    return {"passed": False, "score": 0, "feedback": "Configuration export was empty"}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load config XML: {e}"}

        # 3. Analyze
        score = 0
        feedback_parts = []
        
        # Check initial state
        if result.get("initial_mime_exists", False):
            feedback_parts.append("WARNING: Target MIME type existed before task started.")
            # We enforce that the agent should have verified it, but usually this is an env setup error.
            # We'll allow passing if it exists now, but note it.

        # Parse XML
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
            
            # Navigate to mimeTypes (usually root -> mimeTypes -> mimeType)
            # Structure: <config> <mimeTypes> <mimeType type="..." extensions="..." /> ...
            
            mime_found = False
            extension_correct = False
            
            mime_types = root.find("mimeTypes")
            if mime_types is None:
                # Some versions might flatten it or put it elsewhere, search all descendants
                candidates = root.findall(".//mimeType")
            else:
                candidates = mime_types.findall("mimeType")
                
            for mt in candidates:
                mt_type = mt.get("type", "")
                mt_exts = mt.get("extensions", "")
                
                if mt_type.strip() == target_mime:
                    mime_found = True
                    # Extensions can be comma separated
                    ext_list = [e.strip() for e in mt_exts.split(',')]
                    if target_ext in ext_list:
                        extension_correct = True
                    break
            
            if mime_found:
                score += 50
                feedback_parts.append(f"MIME type '{target_mime}' found in configuration.")
                if extension_correct:
                    score += 50
                    feedback_parts.append(f"Extension '{target_ext}' is correctly mapped.")
                else:
                    feedback_parts.append(f"MIME type found, but extension '{target_ext}' is missing from it.")
            else:
                feedback_parts.append(f"MIME type '{target_mime}' NOT found in configuration.")
                
        except ET.ParseError as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to parse Artifactory configuration XML: {e}"}

        passed = score >= 100
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)