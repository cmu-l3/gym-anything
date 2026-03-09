#!/usr/bin/env python3
"""
Verifier for embed_linked_images task.
Checks if the ODP file contains embedded images instead of external links.
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

def verify_images_embedded(traj, env_info, task_info):
    """
    Verify that images in the ODP file are embedded.
    
    Criteria:
    1. File exists and was modified.
    2. ODP (zip) parsing: No <draw:image> tags have xlink:href starting with 'file://', '/', or '..'.
    3. <draw:image> tags MUST exist (images weren't deleted).
    4. Images should point to internal paths (e.g., 'Pictures/...') or have binary data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    result_json_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)

    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}
    
    if not result_data.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "File was not modified (did you save?)"}

    # Copy the ODP file
    odp_path = tempfile.mktemp(suffix='.odp')
    try:
        copy_from_env("/tmp/result_presentation.odp", odp_path)
        
        # Verify ODP structure
        if not zipfile.is_zipfile(odp_path):
            return {"passed": False, "score": 0, "feedback": "Result is not a valid ODP file"}
            
        with zipfile.ZipFile(odp_path, 'r') as z:
            # Check content.xml
            if 'content.xml' not in z.namelist():
                return {"passed": False, "score": 0, "feedback": "Corrupt ODP: missing content.xml"}
            
            content_xml = z.read('content.xml')
            
            # Check for Pictures folder (embedded images usually live here)
            pictures_folder_exists = any(name.startswith('Pictures/') for name in z.namelist())

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to analyze ODP file: {e}"}

    # Parse XML
    try:
        # Register namespaces to parse correctly
        namespaces = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'xlink': 'http://www.w3.org/1999/xlink'
        }
        
        root = ET.fromstring(content_xml)
        
        # Find all images
        images = root.findall('.//draw:image', namespaces)
        
        image_count = len(images)
        if image_count < 2:
            return {
                "passed": False, 
                "score": 20, 
                "feedback": f"Found only {image_count} images. Expected at least 2. Did you delete them?"
            }
            
        linked_images = 0
        embedded_images = 0
        
        for img in images:
            href = img.get('{http://www.w3.org/1999/xlink}href')
            if not href:
                # Sometimes images are embedded as binary data directly (rare in ODP, but possible)
                continue
                
            # Check if linked
            if href.startswith('file://') or href.startswith('/') or href.startswith('..'):
                linked_images += 1
            elif not href.startswith('#'): # Ignore internal links if any, assume others are embedded
                embedded_images += 1
        
        # Cleanup
        if os.path.exists(odp_path):
            os.remove(odp_path)
            
        # Scoring
        if linked_images > 0:
            return {
                "passed": False,
                "score": 40,
                "feedback": f"Found {linked_images} images still linked to external files. All images must be embedded."
            }
        
        if embedded_images >= 2:
            return {
                "passed": True,
                "score": 100,
                "feedback": f"✅ Success! All {embedded_images} images are correctly embedded."
            }
        else:
            return {
                "passed": False,
                "score": 30,
                "feedback": "Images seem to be missing or format is unexpected."
            }

    except Exception as e:
        logger.error(f"XML Parsing Error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error parsing presentation content: {e}"}