#!/usr/bin/env python3
"""
Verifier for Restore Missing Assets task.

Verifies that:
1. The ODP file was modified/saved.
2. The image link in the ODP XML points to the 'New' assets directory.
3. The image is NOT embedded (href does not start with Pictures/).
"""

import json
import tempfile
import os
import zipfile
import xml.etree.ElementTree as ET
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_missing_assets(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Task Metadata
    metadata = task_info.get('metadata', {})
    pres_path = metadata.get('presentation_path', '/home/ga/Documents/Presentations/Q3_Performance.odp')
    
    # 1. Load basic result info
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            basic_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not basic_result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    if not basic_result.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "File was not saved/modified after task start"}

    # 2. Analyze the ODP file content
    score = 10 # Base score for saving
    feedback_parts = ["File saved"]
    
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(pres_path, temp_odp.name)
        
        # ODP is a zip file. We need to parse content.xml
        if not zipfile.is_zipfile(temp_odp.name):
            return {"passed": False, "score": 10, "feedback": "File saved but is not a valid ODP archive"}

        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            if 'content.xml' not in z.namelist():
                return {"passed": False, "score": 10, "feedback": "Invalid ODP: content.xml missing"}
            
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()

        # Namespaces in ODP
        namespaces = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'xlink': 'http://www.w3.org/1999/xlink'
        }

        # Find all images
        images = root.findall('.//draw:image', namespaces)
        
        link_found = False
        link_correct = False
        link_embedded = False
        found_href = ""

        # We are looking for the image on Slide 2 (or any image pointing to the chart)
        for img in images:
            href = img.get(f"{{{namespaces['xlink']}}}href")
            if not href:
                continue
            
            # Check if this is likely our chart
            if "revenue_chart" in href or "Assets" in href or "New" in href:
                link_found = True
                found_href = href
                
                # Check 1: Is it embedded?
                if href.startswith("Pictures/"):
                    link_embedded = True
                
                # Check 2: Does it point to 'New'?
                # Accepted variations: 
                # ../Assets/New/revenue_chart.png
                # ../../Assets/New/revenue_chart.png
                # /home/ga/Documents/Assets/New/revenue_chart.png
                if "Assets/New/revenue_chart.png" in href:
                    link_correct = True
                
                # If we found the specific target, stop searching
                break
        
        if not link_found:
            feedback_parts.append("❌ Could not find the chart image in the presentation structure")
        else:
            if link_embedded:
                # Partial credit if they deleted and re-inserted (embedded) it
                score += 20
                feedback_parts.append("⚠️ Image was embedded instead of linked (workflow violation)")
            elif link_correct:
                score += 70 # 10 (save) + 70 (link) + 20 (not embedded implicit)
                feedback_parts.append("✅ Link successfully updated to 'Assets/New'")
            else:
                feedback_parts.append(f"❌ Link incorrect. Found: '{found_href}'")

    except Exception as e:
        logger.error(f"Error parsing ODP: {e}")
        return {"passed": False, "score": 10, "feedback": f"Error verifying file content: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }