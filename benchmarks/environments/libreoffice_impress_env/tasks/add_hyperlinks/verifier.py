#!/usr/bin/env python3
"""
Verifier for add_hyperlinks@1 task.
Verifies that the user added specific internal and external hyperlinks to a LibreOffice Impress presentation.
"""

import json
import os
import zipfile
import xml.etree.ElementTree as ET
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_hyperlinks(traj, env_info, task_info):
    """
    Verify the presentation contains the required hyperlinks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Basic Checks
    if not result_data.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found."}

    if not result_data.get("file_modified"):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task (do-nothing detected)."}

    # 2. Retrieve the presentation file
    file_format = result_data.get("file_format", "odp")
    temp_pres = tempfile.NamedTemporaryFile(delete=False, suffix=f'.{file_format}')
    try:
        copy_from_env(f"/tmp/final_presentation.{file_format}", temp_pres.name)
        
        # Verify Content
        score = 0
        feedback = []
        
        if file_format == 'odp':
            verification_result = verify_odp_content(temp_pres.name)
        else:
            feedback.append("⚠️ Format is not ODP (PPTX detected), attempting partial verification.")
            # Fallback for PPTX if agent saved as PPTX (less strict, but allowed)
            # Since python-pptx might not be available on host, we treat this as a lower-confidence pass
            # or fail if we demand ODP. Task description says "Save the file" implying keep ODP.
            # However, for robustness, we fail high scores if format changed unless specified.
            return {"passed": False, "score": 20, "feedback": "File saved in wrong format (PPTX). Please save as ODP."}

        score = verification_result['score']
        feedback.extend(verification_result['feedback'])
        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_pres.name):
            os.unlink(temp_pres.name)

def verify_odp_content(filepath):
    """
    Parses ODP (zip) and content.xml to check for hyperlinks.
    """
    score = 0
    feedback = []
    
    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()

        # Namespaces
        ns = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
            'xlink': 'http://www.w3.org/1999/xlink'
        }

        # Find all slides (draw:page)
        slides = root.findall('.//draw:page', ns)
        slide_count = len(slides)
        
        # Criterion: Slide count
        if slide_count == 5:
            score += 10
            feedback.append("✅ Slide count correct (5)")
        else:
            feedback.append(f"❌ Slide count incorrect: {slide_count} (expected 5)")

        # Analyze Slide 1 for internal links
        internal_links_count = 0
        if slide_count >= 1:
            slide1 = slides[0]
            # Find text:a elements
            links = slide1.findall('.//text:a', ns)
            
            for link in links:
                href = link.get(f"{{{ns['xlink']}}}href", "")
                # Internal links usually start with # or are relative
                if href and (href.startswith("#") or "Slide" in href or "page" in href):
                    internal_links_count += 1
        
        # Scoring Internal Links (Max 40 pts)
        if internal_links_count >= 4:
            score += 40
            feedback.append(f"✅ All internal links found on Slide 1 ({internal_links_count}/4)")
        elif internal_links_count > 0:
            pts = internal_links_count * 10
            score += pts
            feedback.append(f"⚠️ Partial internal links on Slide 1 ({internal_links_count}/4)")
        else:
            feedback.append("❌ No internal links found on Slide 1")

        # Analyze Slide 5 for external link
        external_link_found = False
        usa_gov_found = False
        
        if slide_count >= 5:
            slide5 = slides[4]
            links = slide5.findall('.//text:a', ns)
            for link in links:
                href = link.get(f"{{{ns['xlink']}}}href", "")
                if "usa.gov" in href.lower():
                    external_link_found = True
                    usa_gov_found = True
                    break
                if "http" in href: # Any external link
                    external_link_found = True

            # Also check if text exists even if link is missing (partial credit)
            # Extract all text from slide 5
            all_text = "".join(slide5.itertext())
            if "usa.gov" in all_text.lower():
                usa_gov_found = True # Text present

        # Scoring External Link (Max 40 pts)
        if external_link_found and usa_gov_found:
            score += 40
            feedback.append("✅ External link to USA.gov found on Slide 5")
        elif usa_gov_found:
            score += 10
            feedback.append("⚠️ 'USA.gov' text found but not hyperlinked correctly")
        elif external_link_found:
            score += 10
            feedback.append("⚠️ External link found but not to USA.gov")
        else:
            feedback.append("❌ No external link found on Slide 5")
            
        # File modification check (10 pts)
        score += 10 
        feedback.append("✅ File modification confirmed")

    except Exception as e:
        logger.error(f"ODP parsing failed: {e}")
        return {'score': 0, 'feedback': [f"Failed to parse ODP structure: {str(e)}"]}

    return {'score': score, 'feedback': feedback}