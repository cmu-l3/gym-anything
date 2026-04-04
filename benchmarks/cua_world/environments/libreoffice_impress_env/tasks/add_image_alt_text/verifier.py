#!/usr/bin/env python3
"""
Verifier for add_image_alt_text task.
Parses ODP file to verify alt text on images.
"""

import json
import tempfile
import os
import logging
from odf import opendocument, draw
from odf.namespaces import SVGNS

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_image_alt_text(traj, env_info, task_info):
    """
    Verify that alt text was added to images in the presentation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output_file', 'community_impact_accessible.odp')
    pass_threshold = metadata.get('pass_threshold', 60)
    slide_keywords = metadata.get('slide_keywords', {})

    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # 2. Check File Existence and Modification
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found (community_impact_accessible.odp). Did you save as ODP?"}

    if not result_data.get('file_modified_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified/created during the task session."}
    
    score += 10 # Points for valid file existing
    feedback_parts.append("File exists and modified")

    # 3. Retrieve and Parse ODP File
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(expected_output, temp_odp.name)
        
        try:
            doc = opendocument.load(temp_odp.name)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse ODP file: {e}"}

        # 4. Inspect Slides
        slides = doc.getElementsByType(draw.Page)
        
        if len(slides) != 4:
            feedback_parts.append(f"Warning: Expected 4 slides, found {len(slides)}")
        else:
            score += 10 # Points for preserving slide structure
            feedback_parts.append("Slide structure preserved")

        # Check each slide's image alt text
        images_found = 0
        alt_text_points = 0
        
        for i, slide in enumerate(slides):
            # Find frames containing images
            frames = slide.getElementsByType(draw.Frame)
            slide_img_found = False
            
            for frame in frames:
                # Check if it has an image
                if frame.getElementsByType(draw.Image):
                    slide_img_found = True
                    images_found += 1
                    
                    # Look for svg:desc (Alt Text)
                    # Note: odfpy handles namespaced attributes/children
                    # svg:desc is usually a child element of draw:frame in ODP
                    desc_elements = []
                    for child in frame.childNodes:
                        if hasattr(child, 'qname') and child.qname == (SVGNS, 'desc'):
                            desc_elements.append(child)
                    
                    alt_text = ""
                    if desc_elements:
                        # Extract text from the <svg:desc> node
                        for node in desc_elements[0].childNodes:
                            if node.nodeType == node.TEXT_NODE:
                                alt_text += node.data
                    
                    # If empty, check svg:title just in case agent used Title field
                    if not alt_text:
                        for child in frame.childNodes:
                            if hasattr(child, 'qname') and child.qname == (SVGNS, 'title'):
                                for node in child.childNodes:
                                    if node.nodeType == node.TEXT_NODE:
                                        alt_text += node.data

                    # Verify Content
                    if alt_text:
                        # Check keywords
                        keywords = slide_keywords.get(str(i), [])
                        # Convert both to lower for case-insensitive match
                        alt_lower = alt_text.lower()
                        
                        hits = [k for k in keywords if k.lower() in alt_lower]
                        
                        if len(hits) >= 1:
                            # 20 points per slide for correct alt text
                            pts = 20
                            alt_text_points += pts
                            feedback_parts.append(f"Slide {i+1}: Alt text valid ('{alt_text[:20]}...')")
                        else:
                            # Partial credit for having text but wrong content
                            alt_text_points += 5
                            feedback_parts.append(f"Slide {i+1}: Alt text present but missing keywords ({alt_text[:20]}...)")
                    else:
                        feedback_parts.append(f"Slide {i+1}: No alt text found")
                    
                    # Only check the first image per slide
                    break 
            
            if not slide_img_found:
                feedback_parts.append(f"Slide {i+1}: No image found")

        score += alt_text_points

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    # Final scoring
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }