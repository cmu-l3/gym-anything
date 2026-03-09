#!/usr/bin/env python3
"""
Verifier for Create Custom Slide Shows task.
Verifies ODP file structure by parsing XML content directly.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from lxml import etree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_slide_shows(traj, env_info, task_info):
    """
    Verify that custom slide shows were created correctly in the ODP file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get task metadata
    metadata = task_info.get('metadata', {})
    pres_path = metadata.get('presentation_path', '/home/ga/Documents/Presentations/renewable_energy_strategy.odp')
    expected_shows = metadata.get('expected_shows', {
        "Board Summary": [0, 2, 4, 7],
        "Technical Review": [0, 1, 3, 5, 6, 7]
    })

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Namespaces in ODP
    NS = {
        'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0',
        'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    }

    # Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check basic file status (20 points)
    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}
    
    if not result_data.get('file_modified_during_task'):
        feedback_parts.append("⚠️ File was not modified/saved (anti-gaming warning)")
        # We continue to check content, but penalty might apply or score limited
    else:
        score += 20
        feedback_parts.append("File saved successfully")

    # Retrieve the ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    temp_odp.close()
    
    try:
        copy_from_env(pres_path, temp_odp.name)
        
        if not zipfile.is_zipfile(temp_odp.name):
            return {"passed": False, "score": score, "feedback": "File is not a valid ODP archive"}

        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            if 'content.xml' not in z.namelist():
                return {"passed": False, "score": score, "feedback": "ODP corrupted (no content.xml)"}
            
            content_xml = z.read('content.xml')
            root = etree.fromstring(content_xml)

        # Map slide internal names (e.g., "page1") to indices
        pages = root.findall('.//draw:page', NS)
        page_name_map = {} # name -> index
        page_names_ordered = []
        
        for idx, page in enumerate(pages):
            name = page.get('{%s}name' % NS['draw']) or page.get('name')
            if name:
                page_name_map[name] = idx
                page_names_ordered.append(name)
        
        # Verify slide count (prevent deletion)
        if len(pages) == 8:
            score += 10
            feedback_parts.append("Slide count correct (8)")
        else:
            feedback_parts.append(f"Slide count incorrect: {len(pages)} (expected 8)")

        # Verify Custom Shows
        shows_found = root.findall('.//presentation:show', NS)
        
        if not shows_found:
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | No custom slide shows found"}

        feedback_parts.append(f"Found {len(shows_found)} custom shows")
        
        found_show_data = {}
        for show in shows_found:
            name = show.get('{%s}name' % NS['presentation']) or show.get('name')
            pages_attr = show.get('{%s}pages' % NS['presentation']) or show.get('pages', '')
            
            # Pages are comma separated names like "page1,page2"
            page_list = [p.strip() for p in pages_attr.split(',') if p.strip()]
            page_indices = []
            for p_name in page_list:
                if p_name in page_name_map:
                    page_indices.append(page_name_map[p_name])
            
            found_show_data[name.strip()] = page_indices

        # Score specific shows
        # Expected: "Board Summary": [0, 2, 4, 7]  (Slides 1,3,5,8)
        # Expected: "Technical Review": [0, 1, 3, 5, 6, 7] (Slides 1,2,4,6,7,8)
        
        for exp_name, exp_indices in expected_shows.items():
            # Flexible name matching (case insensitive)
            match = None
            for found_name in found_show_data:
                if found_name.lower() == exp_name.lower():
                    match = found_name
                    break
            
            if match:
                score += 10 # Show exists
                actual_indices = found_show_data[match]
                
                if actual_indices == exp_indices:
                    score += 25 # Perfect slide selection
                    feedback_parts.append(f"✅ '{exp_name}' correct")
                else:
                    # Partial credit for mostly correct
                    # Calculate Jaccard similarity or intersection
                    set_exp = set(exp_indices)
                    set_act = set(actual_indices)
                    if set_exp == set_act: 
                        # Order different but set same? Task implies order matters, but let's give partial
                        score += 20
                        feedback_parts.append(f"⚠️ '{exp_name}' slides correct but order wrong")
                    elif set_exp.issubset(set_act):
                        score += 15
                        feedback_parts.append(f"⚠️ '{exp_name}' contains extra slides")
                    elif len(set_exp.intersection(set_act)) / len(set_exp) > 0.5:
                        score += 10
                        feedback_parts.append(f"⚠️ '{exp_name}' has some correct slides")
                    else:
                        feedback_parts.append(f"❌ '{exp_name}' slides incorrect")
            else:
                feedback_parts.append(f"❌ Show '{exp_name}' missing")

    except Exception as e:
        logger.error(f"Verification logic error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification failed: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }