#!/usr/bin/env python3
"""
Verifier for Apply Distinct Master Slides task.
Verifies ODP file structure using standard Python libraries (zipfile, xml.etree).
"""

import json
import os
import zipfile
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_master_slides(traj, env_info, task_info):
    """
    Verify that specific slides have different master pages applied.
    Target slides (0, 2, 5) should share a master.
    Content slides (1, 3, 4, 6) should share a different master.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check basic file existence
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    if not result_data.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not saved during the task (timestamp check failed)"}

    # Retrieve the ODP file
    output_path = result_data.get('output_path')
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(output_path, temp_odp.name)
        
        # Parse ODP content
        try:
            with zipfile.ZipFile(temp_odp.name, 'r') as z:
                content_xml = z.read('content.xml')
        except zipfile.BadZipFile:
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid ODP archive"}

        # Parse XML
        root = ET.fromstring(content_xml)
        
        # Namespaces in ODP usually look like this
        ns = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
            'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0'
        }

        # Find all slides (draw:page)
        # Note: Depending on parsing, we might need to be flexible with namespaces
        # or use local names.
        slides = []
        # Try finding with namespace
        slides = root.findall('.//draw:page', ns)
        
        # Fallback if specific namespace setup fails, iterate all
        if not slides:
            slides = [elem for elem in root.iter() if elem.tag.endswith('}page')]

        slide_count = len(slides)
        if slide_count != 7:
            return {
                "passed": False, 
                "score": 10, 
                "feedback": f"Incorrect slide count. Expected 7, found {slide_count}"
            }

        # Extract master page names
        # Attribute is usually {urn:oasis:names:tc:opendocument:xmlns:drawing:1.0}master-page-name
        master_names = []
        for s in slides:
            # Try to get master-page-name attribute (handling NS)
            master = "default"
            for k, v in s.attrib.items():
                if k.endswith("master-page-name"):
                    master = v
                    break
            master_names.append(master)

        logger.info(f"Detected master pages: {master_names}")

        target_indices = [0, 2, 5]  # Slides 1, 3, 6
        content_indices = [1, 3, 4, 6] # Slides 2, 4, 5, 7

        score = 20 # Base score for valid file and count
        feedback_parts = ["File valid", f"Count: {slide_count}"]

        # Check Target Slides (Should match each other)
        target_masters = [master_names[i] for i in target_indices]
        if len(set(target_masters)) == 1:
            score += 20
            feedback_parts.append("Target slides share consistent master")
        else:
            feedback_parts.append("Target slides have inconsistent masters")

        # Check Content Slides (Should match each other)
        content_masters = [master_names[i] for i in content_indices]
        if len(set(content_masters)) == 1:
            score += 20
            feedback_parts.append("Content slides share consistent master")
        else:
            feedback_parts.append("Content slides have inconsistent masters")

        # Check that Target != Content
        # We take the most common master from each group to compare
        target_master_repr = max(set(target_masters), key=target_masters.count)
        content_master_repr = max(set(content_masters), key=content_masters.count)

        if target_master_repr != content_master_repr:
            score += 40
            feedback_parts.append("Target master is distinct from Content master")
        else:
            feedback_parts.append("Target and Content slides use the SAME master (Failed)")

        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {
                "masters": master_names,
                "target_indices": target_indices,
                "content_indices": content_indices
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification exception: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)