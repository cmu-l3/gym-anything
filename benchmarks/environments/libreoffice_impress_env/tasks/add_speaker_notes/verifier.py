#!/usr/bin/env python3
"""
Verifier for Add Speaker Notes task.
Parses the ODP file to check for specific speaker notes on each slide.
"""

import json
import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespace map for ODF parsing
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
}

def extract_text_from_element(element):
    """Recursively extract text from an XML element."""
    text_content = []
    if element.text:
        text_content.append(element.text)
    for child in element:
        text_content.append(extract_text_from_element(child))
        if child.tail:
            text_content.append(child.tail)
    return "".join(text_content)

def parse_odp_notes(odp_path):
    """
    Extracts speaker notes from an ODP file.
    Returns a list of strings, where index i corresponds to notes for slide i.
    """
    notes_list = []
    
    try:
        with zipfile.ZipFile(odp_path, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()
                
                # Find the presentation body
                body = root.find('.//office:body/office:presentation', NS)
                if body is None:
                    return []
                
                # Iterate through slides (draw:page)
                for page in body.findall('draw:page', NS):
                    # Find notes within the page (presentation:notes)
                    notes_elem = page.find('presentation:notes', NS)
                    
                    slide_note_text = ""
                    if notes_elem is not None:
                        # Notes are contained in text paragraphs inside the notes element
                        # Usually inside a draw:page-thumbnail or direct text boxes
                        # We just grab all text paragraphs inside the notes element
                        paragraphs = notes_elem.findall('.//text:p', NS)
                        p_texts = [extract_text_from_element(p) for p in paragraphs]
                        slide_note_text = " ".join(p_texts).strip()
                    
                    notes_list.append(slide_note_text)
                    
    except Exception as e:
        logger.error(f"Error parsing ODP: {e}")
        return None
        
    return notes_list

def verify_add_speaker_notes(traj, env_info, task_info):
    """
    Verify that speaker notes were added correctly to the presentation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_content = metadata.get('required_content', [])
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve ODP File
    if not result_data.get("output_exists", False):
         return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    temp_odp.close() # Close so we can write to it via copy
    
    try:
        copy_from_env("/tmp/task_result.odp", temp_odp.name)
        
        # 3. Parse Notes
        extracted_notes = parse_odp_notes(temp_odp.name)
        
        if extracted_notes is None:
            return {"passed": False, "score": 0, "feedback": "Failed to parse ODP file (corrupted?)"}
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ODP file: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    # 4. Verify Content
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Anti-gaming: File modified check (5 pts)
    if result_data.get("file_modified", False):
        score += 5
        feedback_parts.append("File saved")
    else:
        feedback_parts.append("File NOT saved/modified")

    # Structure check (5 pts)
    if len(extracted_notes) == 6:
        score += 5
        feedback_parts.append("Slide count correct")
    else:
        feedback_parts.append(f"Slide count mismatch ({len(extracted_notes)}/6)")

    # Content Checks (15 pts per slide = 90 pts total available here, scaled down)
    # Total points distribution:
    # - File saved: 5
    # - Structure: 5
    # - 6 slides * 15 pts = 90
    # Total = 100
    
    slides_passed = 0
    
    for req in required_content:
        slide_idx = req['slide'] - 1 # 0-based
        if slide_idx >= len(extracted_notes):
            feedback_parts.append(f"Slide {req['slide']} missing")
            continue
            
        note_text = extracted_notes[slide_idx].lower()
        slide_score = 0
        
        # Length Check
        if len(note_text) >= req.get('min_length', 0):
            # Keyword Check
            keywords_any = [k.lower() for k in req.get('keywords_any', [])]
            keywords_all = [k.lower() for k in req.get('keywords_all', [])]
            
            any_match = not keywords_any or any(k in note_text for k in keywords_any)
            all_match = not keywords_all or all(k in note_text for k in keywords_all)
            
            if any_match and all_match:
                slide_score = 15
                slides_passed += 1
            else:
                feedback_parts.append(f"Slide {req['slide']} content mismatch")
        else:
            feedback_parts.append(f"Slide {req['slide']} notes too short/empty")
            
        score += slide_score

    passed = (score >= 60) and (slides_passed >= 4)
    
    feedback_summary = f"Slides with correct notes: {slides_passed}/6. " + " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_summary,
        "details": {
            "slides_passed": slides_passed,
            "total_slides": len(extracted_notes),
            "file_modified": result_data.get("file_modified", False)
        }
    }