#!/usr/bin/env python3
"""
Verifier for configure_kiosk_slideshow task.
Parses the ODP file's XML to check auto-advance timing and loop settings.
"""

import os
import sys
import zipfile
import re
import json
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODP XML namespaces
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
}

def parse_duration_to_seconds(duration_str):
    """
    Parse ISO 8601 duration string to seconds.
    Examples: 'PT10S', 'PT00H00M10S', 'PT0H0M10S', 'PT10.0S'
    """
    if not duration_str:
        return None
    
    # Match various ISO 8601 duration patterns
    pattern = r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?'
    match = re.match(pattern, duration_str)
    if not match:
        return None
    
    hours = int(match.group(1) or 0)
    minutes = int(match.group(2) or 0)
    seconds = float(match.group(3) or 0)
    
    return hours * 3600 + minutes * 60 + seconds

def verify_kiosk_settings(traj, env_info, task_info):
    """
    Verify that the ODP file has correct kiosk settings.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_slides = metadata.get('expected_slide_count', 6)
    expected_duration = metadata.get('expected_auto_advance_seconds', 10)
    duration_tolerance = metadata.get('expected_auto_advance_tolerance_seconds', 3)
    target_file = metadata.get('target_file', "/home/ga/Documents/Presentations/community_kiosk.odp")

    # Retrieve export result for metadata checks
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Check basic file existence and modification
    if not export_result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Target file not found"}
    
    if not export_result.get('file_modified_hash', False):
        return {"passed": False, "score": 0, "feedback": "File was not modified (hash identical to initial state)"}

    # Retrieve the actual ODP file for XML parsing
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(target_file, temp_odp.name)
        
        # Verify valid zip/odp
        if not zipfile.is_zipfile(temp_odp.name):
            return {"passed": False, "score": 0, "feedback": "Target file is not a valid ODP/ZIP archive"}
        
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            content_xml = z.read('content.xml')
        
        root = ET.fromstring(content_xml)
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse ODP file: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    score = 0
    feedback_parts = []
    
    # === CRITERION 1: Slide Count (10 pts) ===
    pages = root.findall('.//draw:page', NS)
    slide_count = len(pages)
    if slide_count == expected_slides:
        score += 10
        feedback_parts.append(f"Slide count correct ({slide_count})")
    else:
        feedback_parts.append(f"Slide count mismatch: expected {expected_slides}, got {slide_count}")

    # === CRITERION 2: Auto-advance settings (40 pts) ===
    # Map page style names to check durations
    page_style_names = [page.get(f"{{{NS['draw']}}}style-name") for page in pages]
    
    # Find automatic styles that are for drawing-pages
    auto_styles = root.findall('.//office:automatic-styles/style:style', NS)
    
    durations_found = []
    
    for style in auto_styles:
        if style.get(f"{{{NS['style']}}}family") == 'drawing-page':
            style_name = style.get(f"{{{NS['style']}}}name")
            if style_name in page_style_names:
                props = style.find('style:drawing-page-properties', NS)
                if props is not None:
                    duration_attr = props.get(f"{{{NS['presentation']}}}duration")
                    if duration_attr:
                        secs = parse_duration_to_seconds(duration_attr)
                        if secs is not None:
                            durations_found.append(secs)

    slides_with_timing = len(durations_found)
    
    if slides_with_timing >= metadata.get('min_slides_with_transition', 5):
        score += 20
        feedback_parts.append(f"Auto-advance enabled on {slides_with_timing}/{slide_count} slides")
        
        # Check timing accuracy
        correct_timing_count = sum(1 for d in durations_found 
                                   if abs(d - expected_duration) <= duration_tolerance)
        
        if correct_timing_count >= metadata.get('min_slides_with_transition', 5):
            score += 20
            feedback_parts.append(f"Timing correct (~{expected_duration}s)")
        else:
            feedback_parts.append(f"Timing incorrect on some slides (found {durations_found})")
    elif slides_with_timing > 0:
        score += 10
        feedback_parts.append(f"Auto-advance only on {slides_with_timing}/{slide_count} slides (too few)")
    else:
        feedback_parts.append("No auto-advance settings found")

    # === CRITERION 3: Endless Loop (40 pts) ===
    is_endless = False
    settings = root.find('.//presentation:settings', NS)
    if settings is not None:
        endless_attr = settings.get(f"{{{NS['presentation']}}}endless")
        if endless_attr == 'true':
            is_endless = True
    
    if is_endless:
        score += 40
        feedback_parts.append("Endless loop enabled")
    else:
        feedback_parts.append("Endless loop NOT enabled")

    # === CRITERION 4: Anti-gaming (10 pts) ===
    # We already checked file_modified_hash at start
    score += 10
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }