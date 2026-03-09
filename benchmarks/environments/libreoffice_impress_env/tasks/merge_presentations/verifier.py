#!/usr/bin/env python3
"""
Verifier for merge_presentations task.

Verifies:
1. 'Executive_Briefing.odp' exists and is a valid ODP file.
2. File was created during the task (anti-gaming).
3. Presentation contains exactly 7 slides.
4. Content from 'BIA_Findings.odp' is in the first 4 slides.
5. Content from 'Risk_Assessment.odp' is in the last 3 slides.
"""

import json
import tempfile
import os
import logging
import zipfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odp_content_robust(odp_path):
    """
    Parses an ODP file using standard zipfile and xml libraries.
    Returns a list of strings, where each string is the aggregated text of a slide.
    
    This is used to avoid dependency on odfpy on the verification host if not available,
    and provides a robust way to check content order.
    """
    slides_text = []
    
    try:
        with zipfile.ZipFile(odp_path, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()
                
                # Namespaces
                ns = {
                    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
                    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
                    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
                }
                
                # Find the presentation body
                body = root.find('.//office:body/office:presentation', ns)
                if body is None:
                    return None, "Invalid ODP structure: no presentation body"
                
                # Iterate through pages (slides)
                for page in body.findall('draw:page', ns):
                    page_text = []
                    # Find all text paragraphs in this page
                    for elem in page.iter():
                        if elem.tag == f"{{{ns['text']}}}p":
                            if elem.text:
                                page_text.append(elem.text)
                            # Also check for spans/text inside
                            for child in elem:
                                if child.tail:
                                    page_text.append(child.tail)
                                if child.text:
                                    page_text.append(child.text)
                    
                    slides_text.append(" ".join(page_text))
                    
        return slides_text, None
        
    except Exception as e:
        return None, f"Failed to parse ODP: {str(e)}"

def verify_merge_presentations(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve Task Metadata
    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_slide_count', 7)
    check_strings = metadata.get('check_strings', {})

    # Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic Checks
    if not result_data.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file 'Executive_Briefing.odp' not found."
        }
    
    if not result_data.get('created_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file exists but was not created during this task session."
        }

    # Retrieve and Parse the ODP File
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(result_data['output_path'], temp_odp.name)
        
        slides_content, error = parse_odp_content_robust(temp_odp.name)
        
        if error:
            return {"passed": False, "score": 10, "feedback": f"File exists but is invalid: {error}"}
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to copy/read ODP file: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    # Scoring Logic
    score = 0
    feedback_lines = []
    
    # Criterion 1: File Validity (already checked partially) -> Base points
    score += 15
    feedback_lines.append("✅ File 'Executive_Briefing.odp' is a valid presentation.")

    # Criterion 2: Slide Count
    actual_count = len(slides_content)
    if actual_count == expected_count:
        score += 20
        feedback_lines.append(f"✅ Correct slide count ({actual_count}).")
    else:
        feedback_lines.append(f"❌ Incorrect slide count: found {actual_count}, expected {expected_count}.")

    # Criterion 3: BIA Content (Slides 1-4)
    bia_matches = 0
    bia_expected = [
        check_strings.get("slide_1", "Business Impact Analysis"),
        check_strings.get("slide_2", "Critical Business Functions"),
        check_strings.get("slide_3", "Recovery Time Objectives"),
        check_strings.get("slide_4", "Resource Dependencies")
    ]
    
    for i, expected_text in enumerate(bia_expected):
        if i < actual_count:
            if expected_text.lower() in slides_content[i].lower():
                bia_matches += 1
                feedback_lines.append(f"  - Slide {i+1} verified: Contains '{expected_text}'")
            else:
                feedback_lines.append(f"  - Slide {i+1} mismatch: Expected '{expected_text}'")
    
    # 30 points for BIA content (7.5 pts per slide)
    score += int((bia_matches / 4) * 30)

    # Criterion 4: Risk Assessment Content (Slides 5-7)
    risk_matches = 0
    risk_expected = [
        check_strings.get("slide_5", "Enterprise Risk Assessment"),
        check_strings.get("slide_6", "Threat Landscape"),
        check_strings.get("slide_7", "Mitigation Strategies")
    ]
    
    # Check appended slides (indices 4, 5, 6 corresponding to slides 5, 6, 7)
    start_index = 4
    for i, expected_text in enumerate(risk_expected):
        current_idx = start_index + i
        if current_idx < actual_count:
            if expected_text.lower() in slides_content[current_idx].lower():
                risk_matches += 1
                feedback_lines.append(f"  - Slide {current_idx+1} verified: Contains '{expected_text}'")
            else:
                # Fallback search: maybe they are out of order?
                found_elsewhere = any(expected_text.lower() in s.lower() for s in slides_content)
                if found_elsewhere:
                    feedback_lines.append(f"  - Slide {current_idx+1} mismatch (text found on wrong slide)")
                else:
                    feedback_lines.append(f"  - Slide {current_idx+1} mismatch: Expected '{expected_text}'")
    
    # 35 points for Risk content (approx 11.6 pts per slide)
    score += int((risk_matches / 3) * 35)

    # Determine Success
    # Must have at least 70 points AND the correct slide count
    passed = (score >= 70) and (actual_count == expected_count)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }