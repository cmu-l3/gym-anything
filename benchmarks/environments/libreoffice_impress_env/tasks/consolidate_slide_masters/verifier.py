#!/usr/bin/env python3
"""
Verifier for Consolidate Slide Masters task.

Verification Logic:
1. Parse the ODP file (it's a ZIP containing content.xml).
2. Extract the 'master-page-name' attribute for all slides.
3. Confirm that Slide 1's master page name is used by ALL other slides.
4. Verify text content to ensure slides weren't simply deleted.
"""

import json
import zipfile
import xml.etree.ElementTree as ET
import tempfile
import os
import shutil
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_masters(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_slide_count = metadata.get('expected_slide_count', 5)
    
    # 1. Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    if not result_data.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "Presentation was not saved (timestamp unchanged)"}

    # 2. Get the ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    temp_odp.close()
    
    try:
        copy_from_env(result_data['file_path'], temp_odp.name)
        
        # 3. Parse content.xml from ODP (ZIP archive)
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()

        # ODF Namespaces
        namespaces = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
        }

        # Extract slides (draw:page)
        slides = root.findall('.//draw:page', namespaces)
        
        slide_data = []
        for i, slide in enumerate(slides):
            master_name = slide.get(f"{{{namespaces['draw']}}}master-page-name")
            
            # Extract text to ensure content preservation
            text_elements = slide.findall('.//text:p', namespaces)
            text_content = " ".join([t.text for t in text_elements if t.text])
            
            slide_data.append({
                'index': i,
                'master': master_name,
                'text': text_content
            })

        # Verification Logic
        score = 0
        feedback_parts = []
        
        # Check 1: Slide Count
        if len(slide_data) == expected_slide_count:
            score += 20
            feedback_parts.append(f"Slide count correct ({len(slide_data)})")
        else:
            feedback_parts.append(f"Incorrect slide count: {len(slide_data)} (expected {expected_slide_count})")

        # Check 2: Content Preservation
        # We check if specific key phrases exist in specific slides
        expected_texts = [
            "Q3 Sales Overview",
            "North Region Data",
            "East Region Data",
            "South Region Data",
            "Global Summary"
        ]
        
        content_preserved = True
        for i, expected in enumerate(expected_texts):
            if i < len(slide_data):
                if expected not in slide_data[i]['text']:
                    content_preserved = False
                    break
        
        if content_preserved:
            score += 20
            feedback_parts.append("Content preserved")
        else:
            feedback_parts.append("Content altered or slides reordered")

        # Check 3: Master Slide Consistency (The Core Task)
        if len(slide_data) > 0:
            target_master = slide_data[0]['master']
            
            # We expect a master name. If it's None, it uses default, which is valid if ALL use default.
            # But in our setup, we assigned explicit masters.
            
            consistent_count = 0
            for s in slide_data:
                if s['master'] == target_master:
                    consistent_count += 1
            
            if consistent_count == len(slide_data):
                score += 60
                feedback_parts.append("All slides use the correct Master Slide")
            else:
                feedback_parts.append(f"Inconsistent formatting: Only {consistent_count}/{len(slide_data)} slides match Slide 1")
        else:
            feedback_parts.append("No slides found to verify")

        passed = (score == 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except zipfile.BadZipFile:
        return {"passed": False, "score": 0, "feedback": "Result file is not a valid ODP archive"}
    except Exception as e:
        logger.error(f"Verification Logic Error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)