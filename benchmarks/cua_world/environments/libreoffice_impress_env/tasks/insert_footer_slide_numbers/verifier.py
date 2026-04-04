#!/usr/bin/env python3
"""
Verifier for insert_footer_slide_numbers task.
Parses the ODP file to verify footer declarations and slide references.
"""

import json
import tempfile
import os
import zipfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODF Namespaces
NAMESPACES = {
    'presentation': 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'dc': 'http://purl.org/dc/elements/1.1/'
}

def verify_footer_and_numbers(traj, env_info, task_info):
    """
    Verify that footers, slide numbers, and date were applied correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_footer = metadata.get('expected_footer_text', "Operations Division - Confidential")
    odp_path = metadata.get('presentation_path', '/home/ga/Documents/Presentations/q4_operations_review.odp')

    # Load task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic checks
    if not task_result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}
    
    if not task_result.get('file_modified'):
        return {"passed": False, "score": 5, "feedback": "File exists but was not saved (not modified)"}

    # Fetch ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(odp_path, temp_odp.name)
        
        # Verify ODP Content
        score = 0
        feedback_parts = []
        
        # 1. Open ODP zip
        try:
            with zipfile.ZipFile(temp_odp.name, 'r') as z:
                with z.open('content.xml') as f:
                    tree = ET.parse(f)
                    root = tree.getroot()
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Invalid ODP file structure: {e}"}

        # 2. Check Footer Declaration
        # Look for <presentation:footer-decl> with the expected text
        footer_decls = root.findall('.//presentation:footer-decl', NAMESPACES)
        footer_found = False
        for decl in footer_decls:
            if decl.text and expected_footer in decl.text:
                footer_found = True
                break
        
        if footer_found:
            score += 20
            feedback_parts.append("✅ Footer text configured correctly")
        else:
            feedback_parts.append("❌ Footer text declaration not found")

        # 3. Check Date Declaration (Fixed)
        # Look for <presentation:date-time-decl presentation:source="fixed">
        date_decls = root.findall('.//presentation:date-time-decl', NAMESPACES)
        date_fixed_found = False
        for decl in date_decls:
            source = decl.get(f"{{{NAMESPACES['presentation']}}}source")
            if source == "fixed" and decl.text and len(decl.text.strip()) > 0:
                date_fixed_found = True
                break
        
        if date_fixed_found:
            score += 20
            feedback_parts.append("✅ Fixed date configured")
        else:
            feedback_parts.append("❌ Fixed date declaration not found")

        # 4. Check Slide Application (Slides 2-6)
        # Iterate over draw:page
        pages = root.findall('.//draw:page', NAMESPACES)
        
        if len(pages) != 6:
            feedback_parts.append(f"⚠️ Unexpected slide count: {len(pages)} (expected 6)")
        else:
            score += 10 # Preserved slide count
            feedback_parts.append("✅ Slide count preserved")

        slides_with_footer = 0
        slides_with_date = 0
        title_slide_clean = True
        
        for i, page in enumerate(pages):
            is_title_slide = (i == 0)
            
            # Check references
            # Attribute keys include namespace
            use_footer = page.get(f"{{{NAMESPACES['presentation']}}}use-footer-name")
            use_date = page.get(f"{{{NAMESPACES['presentation']}}}use-date-time-name")
            
            if is_title_slide:
                if use_footer or use_date:
                    title_slide_clean = False
            else:
                if use_footer: slides_with_footer += 1
                if use_date: slides_with_date += 1

        # Check references count (Expect 5 slides: 2,3,4,5,6)
        if slides_with_footer >= 4: # Allow 1 miss
            score += 20
            feedback_parts.append(f"✅ Footer applied to content slides ({slides_with_footer}/5)")
        else:
            feedback_parts.append(f"❌ Footer missing from content slides ({slides_with_footer}/5)")

        if slides_with_date >= 4:
            score += 15
            feedback_parts.append(f"✅ Date applied to content slides ({slides_with_date}/5)")
        else:
            feedback_parts.append(f"❌ Date missing from content slides ({slides_with_date}/5)")

        if title_slide_clean:
            score += 15
            feedback_parts.append("✅ Title slide excluded from footer/date")
        else:
            feedback_parts.append("❌ Title slide includes footer/date (should be excluded)")

        # Final pass Check
        passed = score >= 60 and footer_found and date_fixed_found
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)