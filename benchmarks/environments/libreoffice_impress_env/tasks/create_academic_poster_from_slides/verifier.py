#!/usr/bin/env python3
"""
Verifier for create_academic_poster_from_slides task.
Checks dimensions, slide count, and content retention.
"""

import json
import os
import tempfile
import logging
import zipfile
from xml.dom import minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_academic_poster(traj, env_info, task_info):
    """
    Verify the academic poster task.
    
    Criteria:
    1. File exists and was saved during task.
    2. Dimensions are approx 30" x 20".
    3. Slide count is exactly 1.
    4. Text content from original slides is present.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'research_poster.odp')
    required_keywords = metadata.get('required_keywords', [])

    # Load export result
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic File Checks
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": f"Output file {expected_filename} not found."}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task."}

    # Fetch the ODP file for analysis
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(f"/home/ga/Documents/Presentations/{expected_filename}", temp_odp.name)
        
        # Parse ODP structure
        # ODP is a zip file. 'content.xml' contains slides/text, 'styles.xml' usually contains page layout.
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            content_xml = z.read('content.xml')
            styles_xml = z.read('styles.xml')
            
        dom_content = minidom.parseString(content_xml)
        dom_styles = minidom.parseString(styles_xml)

        # 1. Check Slide Count
        # Slides are <draw:page> elements in content.xml
        slides = dom_content.getElementsByTagName('draw:page')
        slide_count = len(slides)
        
        # 2. Check Dimensions
        # Page layout is defined in styles.xml under <style:page-layout-properties>
        # We need to find the used layout, but checking all layouts is usually sufficient for a single-slide doc
        page_width_in = 0
        page_height_in = 0
        
        layout_props = dom_styles.getElementsByTagName('style:page-layout-properties')
        # Also check content.xml automatic styles just in case
        layout_props.extend(dom_content.getElementsByTagName('style:page-layout-properties'))
        
        for prop in layout_props:
            w = prop.getAttribute('fo:page-width')
            h = prop.getAttribute('fo:page-height')
            if w and h:
                # Convert to inches
                page_width_in = convert_to_inches(w)
                page_height_in = convert_to_inches(h)
                # If we find a large format, assume it's the one (since default is small)
                if page_width_in > 20: 
                    break

        # 3. Check Content Retention
        # Extract all text from content.xml
        text_elements = dom_content.getElementsByTagName('text:p')
        all_text = " ".join([node.firstChild.nodeValue for node in text_elements if node.firstChild])
        
        # Scoring
        score = 0
        feedback_parts = []
        
        # Score: File saved (already checked) -> 10 pts
        score += 10
        feedback_parts.append("File saved")

        # Score: Dimensions (30 pts)
        # Allow small tolerance
        if abs(page_width_in - 30) < 1.0 and abs(page_height_in - 20) < 1.0:
            score += 30
            feedback_parts.append(f"Dimensions correct ({page_width_in:.1f}\"x{page_height_in:.1f}\")")
        else:
            feedback_parts.append(f"Dimensions incorrect ({page_width_in:.1f}\"x{page_height_in:.1f}\", expected 30x20)")

        # Score: Slide Count (20 pts)
        if slide_count == 1:
            score += 20
            feedback_parts.append("Slide count correct (1)")
        else:
            feedback_parts.append(f"Slide count incorrect ({slide_count}, expected 1)")

        # Score: Content (40 pts)
        found_keywords = [kw for kw in required_keywords if kw.lower() in all_text.lower()]
        keyword_score = int((len(found_keywords) / len(required_keywords)) * 40)
        score += keyword_score
        
        if len(found_keywords) == len(required_keywords):
            feedback_parts.append("All content retained")
        else:
            feedback_parts.append(f"Content missing ({len(found_keywords)}/{len(required_keywords)} keywords found)")

        return {
            "passed": score >= 70 and slide_count == 1 and abs(page_width_in - 30) < 1.0,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

def convert_to_inches(length_str):
    """Convert ODF length string (e.g., '30in', '25cm') to inches."""
    length_str = length_str.lower().strip()
    try:
        if length_str.endswith('in'):
            return float(length_str[:-2])
        elif length_str.endswith('cm'):
            return float(length_str[:-2]) / 2.54
        elif length_str.endswith('mm'):
            return float(length_str[:-2]) / 25.4
        elif length_str.endswith('pt'):
            return float(length_str[:-2]) / 72.0
        return 0.0
    except ValueError:
        return 0.0