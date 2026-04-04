#!/usr/bin/env python3
"""
Verifier for Sanitize Metadata Task.
Unzips the ODP file and inspects meta.xml and content.xml for forbidden data.
"""

import json
import tempfile
import os
import zipfile
import shutil
import logging
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespaces in ODF files
NAMESPACES = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'meta': 'urn:oasis:names:tc:opendocument:xmlns:meta:1.0',
    'dc': 'http://purl.org/dc/elements/1.1/',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
}

def verify_sanitize_metadata(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_file', 'incident_report_public.odp')
    
    # 1. Retrieve the result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check basics
    if not result_data.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target file 'incident_report_public.odp' not found."
        }

    if not result_data.get('file_created_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "File exists but was not saved during the task session (anti-gaming check failed)."
        }

    # 3. Retrieve and Unzip the ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    temp_extract_dir = tempfile.mkdtemp()
    
    score = 0
    feedback_parts = []
    
    try:
        copy_from_env(expected_output, temp_odp.name)
        
        try:
            with zipfile.ZipFile(temp_odp.name, 'r') as zip_ref:
                zip_ref.extractall(temp_extract_dir)
        except zipfile.BadZipFile:
            return {"passed": False, "score": 10, "feedback": "Saved file is not a valid ODP/ZIP archive."}
            
        # 4. Verify Metadata (meta.xml)
        meta_xml_path = os.path.join(temp_extract_dir, 'meta.xml')
        meta_clean = False
        prop_clean = False
        
        if os.path.exists(meta_xml_path):
            tree = ET.parse(meta_xml_path)
            root = tree.getroot()
            
            # Check Creator/Author
            creators = root.findall('.//dc:creator', NAMESPACES)
            initial_creators = root.findall('.//meta:initial-creator', NAMESPACES)
            
            forbidden_author = "Internal Audit Team"
            found_author = False
            
            for node in creators + initial_creators:
                if node.text and forbidden_author in node.text:
                    found_author = True
                    break
            
            if not found_author:
                score += 25
                meta_clean = True
                feedback_parts.append("✅ Author metadata removed.")
            else:
                feedback_parts.append(f"❌ Author '{forbidden_author}' still found in metadata.")

            # Check Custom Properties
            user_defined = root.findall('.//meta:user-defined', NAMESPACES)
            found_prop = False
            for node in user_defined:
                name = node.get(f"{{{NAMESPACES['meta']}}}name")
                if name == "Classification":
                    found_prop = True
                    break
            
            if not found_prop:
                score += 25
                prop_clean = True
                feedback_parts.append("✅ Custom property 'Classification' removed.")
            else:
                feedback_parts.append("❌ Custom property 'Classification' still exists.")
        else:
            feedback_parts.append("⚠️ meta.xml missing (technically clean, but unusual).")

        # 5. Verify Comments (content.xml)
        content_xml_path = os.path.join(temp_extract_dir, 'content.xml')
        comments_clean = False
        
        if os.path.exists(content_xml_path):
            tree = ET.parse(content_xml_path)
            root = tree.getroot()
            
            # Look for annotations
            annotations = root.findall('.//office:annotation', NAMESPACES)
            annotation_count = len(annotations)
            
            if annotation_count == 0:
                score += 40
                comments_clean = True
                feedback_parts.append("✅ All comments removed.")
            else:
                feedback_parts.append(f"❌ {annotation_count} comments still remaining.")
        else:
            feedback_parts.append("❌ content.xml missing (file corrupted).")

        # 6. Basic file valid score
        score += 10 # Points for valid file structure

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Error analyzing file: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)
        shutil.rmtree(temp_extract_dir, ignore_errors=True)

    passed = (score >= 90) # Requires almost perfect execution
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }