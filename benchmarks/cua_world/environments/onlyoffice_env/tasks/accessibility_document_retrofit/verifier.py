#!/usr/bin/env python3
"""
Verifier for Accessibility Document Retrofit task

Checks:
1. Proper Heading 1 styles applied (3 sections)
2. Proper Heading 2 styles applied (2 subsections)
3. All images have alt text
4. Alt text is descriptive (contains relevant keywords)
5. Table of contents exists
6. Document saved with correct filename
"""

import sys
import os
import logging
import tempfile
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_image_alt_texts(doc_path):
    """
    Extract alt text from images by parsing the DOCX XML directly.
    
    Returns:
        List of alt text strings
    """
    alt_texts = []
    
    try:
        with zipfile.ZipFile(doc_path, 'r') as docx_zip:
            # Parse document.xml
            xml_content = docx_zip.read('word/document.xml')
            root = ET.fromstring(xml_content)
            
            # Define namespaces
            namespaces = {
                'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
                'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
                'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
                'pic': 'http://schemas.openxmlformats.org/drawingml/2006/picture'
            }
            
            # Find all drawing elements with docPr (which contains alt text)
            for docPr in root.findall('.//wp:docPr', namespaces):
                # Get descr attribute (alt text)
                alt_text = docPr.get('descr', '') or docPr.get('title', '')
                if alt_text and alt_text.strip():
                    alt_texts.append(alt_text.strip())
                else:
                    # Image exists but no alt text
                    alt_texts.append('')
            
            logger.info(f"Found {len(alt_texts)} images with alt text info")
    
    except Exception as e:
        logger.warning(f"Could not extract alt text from XML: {e}")
    
    return alt_texts


def check_for_toc(doc):
    """
    Check if document contains a table of contents.
    
    Looks for:
    - TOC field codes
    - Hyperlinked TOC paragraphs
    - Paragraphs styled as TOC
    """
    try:
        # Method 1: Check for TOC-related styles
        for para in doc.paragraphs:
            style_name = para.style.name if para.style else ""
            if 'TOC' in style_name or 'Contents' in style_name:
                return True
            
            # Method 2: Check for field codes (more reliable)
            if hasattr(para, '_element'):
                # Look for field characters that indicate TOC
                for fldChar in para._element.findall('.//{http://schemas.openxmlformats.org/wordprocessingml/2006/main}fldChar'):
                    return True
                
                # Look for instrText containing TOC
                for instrText in para._element.findall('.//{http://schemas.openxmlformats.org/wordprocessingml/2006/main}instrText'):
                    if instrText.text and 'TOC' in instrText.text:
                        return True
        
        # Method 3: Check for hyperlinks to bookmarks (characteristic of TOC)
        toc_hyperlink_count = 0
        for para in doc.paragraphs:
            if hasattr(para, '_element'):
                hyperlinks = para._element.findall('.//{http://schemas.openxmlformats.org/wordprocessingml/2006/main}hyperlink')
                if hyperlinks:
                    toc_hyperlink_count += len(hyperlinks)
        
        # If we have multiple hyperlinks early in the document, likely a TOC
        if toc_hyperlink_count >= 2:
            return True
        
        return False
    
    except Exception as e:
        logger.error(f"Error checking for TOC: {e}")
        return False


def verify_accessibility_retrofit(traj, env_info, task_info):
    """
    Verify that accessibility fixes were properly applied to the document.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    # Try both possible file paths
    accessible_path = "/home/ga/Documents/TextDocuments/community_resources_accessible.docx"
    draft_path = "/home/ga/Documents/TextDocuments/community_resources_draft.docx"
    
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_accessibility_')
    temp_file = None

    try:
        # Try accessible path first, fall back to draft path
        success = False
        doc = None
        used_path = None
        
        for container_path in [accessible_path, draft_path]:
            result = copy_and_parse_document(container_path, copy_from_env, 'docx')
            if result[0]:  # success
                success, doc, error = result
                used_path = container_path
                temp_file = os.path.join(temp_dir, 'document.docx')
                # Copy file for XML parsing
                temp_file_handle = open(temp_file, 'wb')
                try:
                    # Copy the file content
                    copy_from_env(container_path, temp_file)
                except:
                    pass
                finally:
                    if os.path.exists(temp_file_handle.name):
                        temp_file_handle.close()
                break
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "❌ Could not open document. Make sure to save your work!"
            }
        
        feedback_parts = []
        score = 0.0
        max_score = 10.0
        
        # Check if correct filename was used
        if 'accessible' in used_path:
            score += 1.0
            feedback_parts.append("✅ Saved with correct filename (community_resources_accessible.docx)")
        else:
            feedback_parts.append("⚠️ Saved as draft.docx instead of community_resources_accessible.docx")
        
        # Criterion 1: Verify Heading 1 styles (3 expected)
        h1_count = 0
        h1_texts = []
        expected_h1 = ['transportation services', 'communication resources', 'service animal resources']
        
        for para in doc.paragraphs:
            if para.style and 'Heading 1' in para.style.name:
                h1_count += 1
                h1_texts.append(para.text.lower())
        
        h1_matches = sum(1 for expected in expected_h1 if any(expected in text for text in h1_texts))
        
        if h1_count >= 3 and h1_matches >= 2:
            score += 2.0
            feedback_parts.append(f"✅ Found {h1_count} Heading 1 styles with correct content")
        elif h1_count >= 3:
            score += 1.0
            feedback_parts.append(f"⚠️ Found {h1_count} Heading 1 styles, but content may not match")
        else:
            feedback_parts.append(f"❌ Expected 3 Heading 1 styles, found {h1_count}")
        
        # Criterion 2: Verify Heading 2 styles (2 expected)
        h2_count = 0
        h2_texts = []
        expected_h2 = ['tty services', 'video relay service']
        
        for para in doc.paragraphs:
            if para.style and 'Heading 2' in para.style.name:
                h2_count += 1
                h2_texts.append(para.text.lower())
        
        h2_matches = sum(1 for expected in expected_h2 if any(expected in text for text in h2_texts))
        
        if h2_count >= 2 and h2_matches >= 1:
            score += 2.0
            feedback_parts.append(f"✅ Found {h2_count} Heading 2 styles with correct content")
        elif h2_count >= 2:
            score += 1.0
            feedback_parts.append(f"⚠️ Found {h2_count} Heading 2 styles, but content may not match")
        else:
            feedback_parts.append(f"❌ Expected 2 Heading 2 styles, found {h2_count}")
        
        # Criterion 3: Verify images have alt text
        images_with_alt = 0
        alt_texts = []
        
        # Method 1: Try XML parsing if we have the temp file
        if temp_file and os.path.exists(temp_file):
            alt_texts = extract_image_alt_texts(temp_file)
        
        # Method 2: Try using python-docx inline shapes
        if not alt_texts:
            for para in doc.paragraphs:
                for run in para.runs:
                    if hasattr(run, '_element'):
                        # Look for drawing elements
                        for drawing in run._element.findall('.//{http://schemas.openxmlformats.org/wordprocessingml/2006/main}drawing'):
                            for docPr in drawing.findall('.//{http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing}docPr'):
                                alt_text = docPr.get('descr', '') or docPr.get('title', '')
                                alt_texts.append(alt_text if alt_text else '')
        
        # Count non-empty alt texts
        images_with_alt = sum(1 for alt in alt_texts if alt and len(alt.strip()) > 0)
        
        if images_with_alt >= 3:
            score += 2.0
            feedback_parts.append(f"✅ All {images_with_alt} images have alt text")
        elif images_with_alt >= 2:
            score += 1.0
            feedback_parts.append(f"⚠️ Only {images_with_alt}/3 images have alt text")
        else:
            feedback_parts.append(f"❌ Only {images_with_alt}/3 images have alt text")
        
        # Criterion 4: Verify alt text quality (contains relevant keywords)
        alt_text_quality = 0
        keyword_sets = [
            ['ramp', 'wheelchair', 'accessible', 'entrance'],
            ['tty', 'phone', 'telecommunication', 'device', 'deaf'],
            ['service dog', 'service animal', 'dog', 'vest', 'animal']
        ]
        
        for i, keyword_list in enumerate(keyword_sets):
            if i < len(alt_texts):
                alt = alt_texts[i].lower() if alt_texts[i] else ''
                if any(kw in alt for kw in keyword_list):
                    alt_text_quality += 1
        
        if alt_text_quality >= 2:
            score += 2.0
            feedback_parts.append(f"✅ Alt text is descriptive ({alt_text_quality}/3 contain relevant keywords)")
        elif alt_text_quality >= 1:
            score += 1.0
            feedback_parts.append(f"⚠️ Some alt text is descriptive ({alt_text_quality}/3 contain relevant keywords)")
        else:
            feedback_parts.append(f"❌ Alt text may not be descriptive enough ({alt_text_quality}/3 matched)")
        
        # Criterion 5: Verify table of contents exists
        toc_found = check_for_toc(doc)
        
        if toc_found:
            score += 3.0
            feedback_parts.append("✅ Table of contents found")
        else:
            feedback_parts.append("❌ No table of contents found (References → Table of Contents)")
        
        # Calculate final result
        passed = score >= 7.0  # Need at least 7/10 points to pass
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score / max_score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)