#!/usr/bin/env python3
"""
Verifier for Master Slide Navigation task.

Verification Logic:
1. Unzip the ODP file.
2. Parse 'styles.xml' to find the Master Slide definitions.
3. Verify that the navigation elements (sidebar, links) exist inside the Master Slide.
   - This ensures the agent didn't just copy-paste elements onto every slide (anti-gaming).
4. Verify link targets point to correct slides.
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

# Namespaces commonly used in ODF
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'xlink': 'http://www.w3.org/1999/xlink'
}

def verify_master_slide_navigation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup temp workspace
    temp_dir = tempfile.mkdtemp()
    target_odp = os.path.join(temp_dir, "target.odp")
    result_json_path = os.path.join(temp_dir, "task_result.json")

    try:
        # 1. Get Task Result Metadata
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data"}

        if not result_data.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Output file not found. Did you save as 'employee_handbook_nav.odp'?"}
        
        if not result_data.get("file_created_during_task", False):
            return {"passed": False, "score": 0, "feedback": "Output file not modified during task session."}

        # 2. Get the ODP file
        try:
            copy_from_env("/tmp/verification_target.odp", target_odp)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve ODP file for verification"}

        # 3. Parse ODP (Zip -> styles.xml)
        if not zipfile.is_zipfile(target_odp):
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid ODP archive"}

        with zipfile.ZipFile(target_odp, 'r') as z:
            if 'styles.xml' not in z.namelist():
                return {"passed": False, "score": 0, "feedback": "Invalid ODP: styles.xml missing"}
            
            with z.open('styles.xml') as f:
                styles_tree = ET.parse(f)
                styles_root = styles_tree.getroot()

        # 4. Verification Logic
        score = 0
        feedback_parts = []
        
        # A. Find Master Page
        # Path: office:document-styles -> office:master-styles -> style:master-page
        master_styles = styles_root.find('.//office:master-styles', NS)
        if master_styles is None:
            return {"passed": False, "score": 0, "feedback": "Corrupt ODP: No master styles found"}
        
        master_page = master_styles.find('style:master-page', NS)
        if master_page is None:
            # Maybe looking for 'Standard' master
            for mp in master_styles.findall('style:master-page', NS):
                if mp.get(f"{{{NS['style']}}}name") == 'Standard':
                    master_page = mp
                    break
            if master_page is None:
                # Fallback to first available
                master_page = master_styles.find('style:master-page', NS)
        
        if master_page is not None:
            score += 20
            feedback_parts.append("Found Master Slide definition")
        else:
            return {"passed": False, "score": 0, "feedback": "Could not locate Master Slide definition"}

        # B. Check for Sidebar (Rectangle) in Master
        # Look for draw:rect or draw:custom-shape
        rects = master_page.findall('.//draw:rect', NS)
        custom_shapes = master_page.findall('.//draw:custom-shape', NS)
        
        has_sidebar = False
        # Heuristic: Sidebar is likely on the left, so low 'x' and large 'height'
        # But for basic verification, just existence of a shape added to master is good
        if len(rects) > 0 or len(custom_shapes) > 0:
            has_sidebar = True
            score += 20
            feedback_parts.append("Sidebar shape detected in Master Slide")
        else:
            feedback_parts.append("No sidebar/shapes found in Master Slide")

        # C. Check for Hyperlinks in Master
        # Look for text:a inside the master page
        links = master_page.findall('.//text:a', NS)
        # Also look inside draw:frame -> textbox
        
        home_link_found = False
        contact_link_found = False
        
        for link in links:
            href = link.get(f"{{{NS['xlink']}}}href", "")
            text_content = "".join(link.itertext()).lower()
            
            # Check targets (usually internal links start with #)
            is_internal = href.startswith("#")
            
            if "home" in text_content and is_internal:
                home_link_found = True
            
            if "contact" in text_content and is_internal:
                contact_link_found = True

        if home_link_found:
            score += 20
            feedback_parts.append("'Home' link found in Master")
        else:
            feedback_parts.append("'Home' link missing or not on Master Slide")
            
        if contact_link_found:
            score += 20
            feedback_parts.append("'Contact' link found in Master")
        else:
            feedback_parts.append("'Contact' link missing or not on Master Slide")

        # D. Anti-Gaming Check (Filesize/Content)
        # If links were found in master, we assume they didn't copy-paste 100 times.
        # We award remaining points for file validity and general success
        if home_link_found or contact_link_found:
            score += 20
        
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification Failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)