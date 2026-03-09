#!/usr/bin/env python3
"""
Verifier for Add Review Comments task.
Parses ODP (ZIP/XML) to verify annotations on specific slides.
"""

import json
import tempfile
import os
import zipfile
import logging
import xml.etree.ElementTree as ET
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_review_comments(traj, env_info, task_info):
    """
    Verify that specific comments were added to the ODP file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    expected_comments = metadata.get('expected_comments', [])
    target_file = metadata.get('target_file', '/home/ga/Documents/Presentations/marketing_strategy.odp')

    # Load Result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic checks
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}
    
    if not result.get('file_modified'):
        # Anti-gaming: File must be saved
        return {"passed": False, "score": 0, "feedback": "Presentation file was not modified (did you save?)"}

    # Fetch ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(target_file, temp_odp.name)
        
        if not zipfile.is_zipfile(temp_odp.name):
            return {"passed": False, "score": 0, "feedback": "Target file is not a valid ODP archive"}

        # Parse XML
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            if 'content.xml' not in z.namelist():
                return {"passed": False, "score": 0, "feedback": "Corrupt ODP: missing content.xml"}
            content_xml = z.read('content.xml')

        # ODF Namespaces
        ns = {
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
            'dc': 'http://purl.org/dc/elements/1.1/'
        }

        root = ET.fromstring(content_xml)
        
        # Locate slides (draw:page)
        # Structure: office:body > office:presentation > draw:page
        body = root.find('office:body', ns)
        presentation = body.find('office:presentation', ns)
        if presentation is None:
             return {"passed": False, "score": 0, "feedback": "Corrupt ODP structure: no presentation element"}
             
        pages = presentation.findall('draw:page', ns)
        
        score = 10 # Base score for valid file
        feedback_parts = ["File valid"]
        
        # Check each expected comment
        for req in expected_comments:
            slide_idx = req['slide_index']
            expected_text = req['text_content']
            desc = req.get('description', f"Slide {slide_idx+1}")

            if slide_idx >= len(pages):
                feedback_parts.append(f"❌ {desc}: Slide missing")
                continue

            page = pages[slide_idx]
            
            # Find annotations on this page
            # Annotations are <office:annotation> elements
            annotations = page.findall('.//office:annotation', ns)
            
            # Extract text from annotations
            found_texts = []
            for ann in annotations:
                # Text is in <text:p> or <text:list>
                paragraphs = ann.findall('.//text:p', ns)
                text_content = " ".join([p.text for p in paragraphs if p.text])
                found_texts.append(text_content)
            
            # Check match (keywords/fuzzy)
            keywords = [w.lower() for w in expected_text.split() if len(w) > 3]
            match_found = False
            
            for found_text in found_texts:
                found_lower = found_text.lower()
                # Require 60% of keywords to be present
                hits = sum(1 for k in keywords if k in found_lower)
                if hits / len(keywords) >= 0.6:
                    match_found = True
                    break
            
            if match_found:
                score += 30
                feedback_parts.append(f"✅ {desc}: Comment found")
            else:
                feedback_parts.append(f"❌ {desc}: Comment missing")

        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
        
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)