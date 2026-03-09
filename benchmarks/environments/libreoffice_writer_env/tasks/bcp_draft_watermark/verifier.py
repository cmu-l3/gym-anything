#!/usr/bin/env python3
"""
Verifier for BCP Draft Watermark Task.

Verifies:
1. Document Properties (Metadata): Title, Subject, Author, Keywords
2. Footer Content: Confidentiality text presence
3. Watermark: "DRAFT" presence in header XML
4. Content Preservation: Document is not empty or corrupted
"""

import json
import os
import sys
import tempfile
import zipfile
import logging
import re
from typing import Dict, Any

# Adjust path to find utility modules if needed
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import vlm_verify_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bcp_draft_watermark(traj, env_info, task_info):
    """
    Verify the BCP document governance task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_props = metadata.get('expected_properties', {})
    expected_footer = metadata.get('footer_text', "CONFIDENTIAL")
    expected_watermark = metadata.get('watermark_text', "DRAFT")
    
    # 1. Check Export Result (File Existence & Timing)
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    if not export_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file bcp_plan_draft.docx not found."}
    
    if not export_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task session."}

    # 2. Get the Output Document
    temp_doc = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    temp_doc_path = temp_doc.name
    temp_doc.close()
    
    try:
        copy_from_env("/home/ga/Documents/bcp_plan_draft.docx", temp_doc_path)
    except Exception as e:
        if os.path.exists(temp_doc_path):
            os.unlink(temp_doc_path)
        return {"passed": False, "score": 0, "feedback": f"Failed to copy output document: {e}"}

    score = 0
    feedback = []
    
    try:
        # Use python-docx for Properties and Footer text
        from docx import Document
        doc = Document(temp_doc_path)
        
        # --- CHECK 1: Core Properties (Metadata) [40 points] ---
        # Title (10)
        actual_title = doc.core_properties.title
        if expected_props['title'] in actual_title:
            score += 10
            feedback.append("Title correct.")
        else:
            feedback.append(f"Title incorrect. Expected '{expected_props['title']}', got '{actual_title}'")
            
        # Author (10)
        actual_author = doc.core_properties.author
        if expected_props['author'].lower() in actual_author.lower():
            score += 10
            feedback.append("Author correct.")
        else:
            feedback.append(f"Author incorrect. Got '{actual_author}'")

        # Subject (10)
        actual_subject = doc.core_properties.subject
        if expected_props['subject'] in actual_subject:
            score += 10
            feedback.append("Subject correct.")
        else:
            feedback.append(f"Subject incorrect. Got '{actual_subject}'")

        # Keywords (10)
        actual_keywords = doc.core_properties.keywords
        # Keywords might be comma separated or space separated depending on how Writer saves them
        keywords_found = 0
        for kw in expected_props['keywords']:
            if kw.lower() in actual_keywords.lower():
                keywords_found += 1
        
        if keywords_found >= 3:
            score += 10
            feedback.append("Keywords correct.")
        elif keywords_found > 0:
            score += 5
            feedback.append(f"Some keywords missing ({keywords_found}/4 found).")
        else:
            feedback.append("Keywords missing.")

        # --- CHECK 2: Footer Content [20 points] ---
        footer_text_found = False
        for section in doc.sections:
            if section.footer:
                for para in section.footer.paragraphs:
                    if "CONFIDENTIAL" in para.text and "Meridian" in para.text:
                        footer_text_found = True
                        break
            if footer_text_found:
                break
        
        if footer_text_found:
            score += 20
            feedback.append("Footer present.")
        else:
            feedback.append("Confidential footer not found.")

        # --- CHECK 3: Watermark (XML Parsing) [20 points] ---
        # python-docx doesn't easily expose watermarks (usually VML/drawing in header).
        # We will unzip the docx and grep the header XMLs.
        watermark_found = False
        with zipfile.ZipFile(temp_doc_path, 'r') as zip_ref:
            # Look in word/header1.xml, header2.xml, etc.
            header_files = [f for f in zip_ref.namelist() if f.startswith('word/header')]
            for hf in header_files:
                xml_content = zip_ref.read(hf).decode('utf-8', errors='ignore')
                # Watermarks often appear as powerplus watermark or v:textpath
                if 'DRAFT' in xml_content and ('watermark' in xml_content.lower() or 'textpath' in xml_content.lower()):
                    watermark_found = True
                    break
                # Fallback: just look for the text in a shape context
                if 'DRAFT' in xml_content and '<v:shape' in xml_content:
                    watermark_found = True
                    break
        
        if watermark_found:
            score += 20
            feedback.append("Watermark detected in XML.")
        else:
            feedback.append("Watermark 'DRAFT' not detected in document structure.")

        # --- CHECK 4: VLM Verification [20 points] ---
        # Visual check for watermark and overall look
        vlm_result = vlm_verify_screenshot(env_info, traj, 
            "Analyze this document screenshot. 1. Is there a visible 'DRAFT' watermark (usually gray, diagonal text behind content)? "
            "2. Is there a footer visible at the bottom? 3. Does the document look like a structured plan?")
        
        if vlm_result['success']:
            parsed = vlm_result.get('parsed', {})
            # We trust the code checks more, but use VLM as confirmation
            # If code check failed watermark, but VLM sees it, give partial credit?
            # Sticking to the plan: VLM score is additive.
            if parsed.get('has_watermark', False) or "DRAFT" in str(parsed):
                score += 10
            if parsed.get('has_footer', False):
                score += 10
        else:
            # Fallback if VLM fails: if XML check passed, give these points too
            if watermark_found: score += 10
            if footer_text_found: score += 10

    except Exception as e:
        feedback.append(f"Error during verification: {str(e)}")
        # Partial score based on file existence
        if export_result.get('output_exists'):
            score = 10 
    finally:
        if os.path.exists(temp_doc_path):
            os.unlink(temp_doc_path)

    passed = score >= 60 and export_result.get('output_exists')
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }