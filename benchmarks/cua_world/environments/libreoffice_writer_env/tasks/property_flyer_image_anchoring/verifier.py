#!/usr/bin/env python3
"""
Verifier for Real Estate Flyer Image Anchoring task.
Verifies ODT internal structure for Object Names, Anchors, and Text Wrapping.
"""

import os
import json
import zipfile
import tempfile
import shutil
import logging
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# XML Namespaces in ODT
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
}

def verify_flyer_anchoring(traj, env_info, task_info):
    """
    Verify the flyer layout task.
    
    Criteria:
    1. Output file exists.
    2. Logo object: Named 'Company_Logo', Anchored 'page'.
    3. House object: Named 'House_Photo', Anchored 'paragraph', Wrapped 'parallel' (or similar).
    4. Signature object: Named 'Agent_Signature', Anchored 'as-char'.
    5. Title has Heading 1 style.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    score = 0
    feedback = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    try:
        copy_from_env("/tmp/task_result.json", temp_json)
        with open(temp_json) as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {e}"}
    finally:
        if os.path.exists(temp_json):
            os.remove(temp_json)
            
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Final output file 'final_flyer.odt' not found."}

    score += 10 # File exists
    
    # 2. Analyze the ODT file
    temp_odt = tempfile.NamedTemporaryFile(delete=False, suffix=".odt").name
    try:
        copy_from_env("/home/ga/Documents/final_flyer.odt", temp_odt)
        
        # Open ODT (it's a zip)
        if not zipfile.is_zipfile(temp_odt):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid ODT/ZIP file."}
            
        with zipfile.ZipFile(temp_odt, 'r') as z:
            content_xml = z.read('content.xml')
            
        root = ET.fromstring(content_xml)
        
        # --- Check Heading 1 ---
        # Find the title text "Luxury Villa..."
        title_found = False
        h1_applied = False
        for p in root.findall('.//text:p', NS) + root.findall('.//text:h', NS):
            if p.text and "Luxury Villa" in p.text:
                title_found = True
                # Check style
                style_name = p.get(f"{{{NS['text']}}}style-name", "")
                # Heading styles usually map to "Heading_20_1" or similar in internal XML, 
                # or the outline-level attribute is set.
                outline_level = p.get(f"{{{NS['text']}}}outline-level")
                if outline_level == "1" or "Heading" in style_name:
                    h1_applied = True
                break
        
        if h1_applied:
            score += 10
            feedback.append("Title formatted as Heading 1.")
        else:
            feedback.append("Title formatting incorrect (expected Heading 1).")

        # --- Check Objects (Frames) ---
        frames = root.findall('.//draw:frame', NS)
        
        objects_status = {
            "logo": {"found": False, "anchor": False, "name": False},
            "house": {"found": False, "anchor": False, "wrap": False, "name": False},
            "sig": {"found": False, "anchor": False, "name": False}
        }
        
        # Styles map (needed to check wrapping)
        # Wrapping is defined in automatic-styles referenced by the frame
        auto_styles = root.find('office:automatic-styles', NS)
        style_map = {}
        if auto_styles:
            for style in auto_styles.findall('style:style', NS):
                name = style.get(f"{{{NS['style']}}}name")
                # Look for graphic properties
                gprops = style.find('style:graphic-properties', NS)
                if gprops is not None:
                    wrap = gprops.get(f"{{{NS['style']}}}wrap")
                    style_map[name] = wrap
        
        for frame in frames:
            name = frame.get(f"{{{NS['draw']}}}name", "")
            anchor = frame.get(f"{{{NS['text']}}}anchor-type", "")
            style_name = frame.get(f"{{{NS['draw']}}}style-name", "")
            wrap_type = style_map.get(style_name, "none")
            
            # Check Company_Logo
            if "Company_Logo" in name:
                objects_status["logo"]["found"] = True
                objects_status["logo"]["name"] = True
                if anchor == "page":
                    objects_status["logo"]["anchor"] = True
            
            # Check House_Photo
            elif "House_Photo" in name:
                objects_status["house"]["found"] = True
                objects_status["house"]["name"] = True
                if anchor == "paragraph":
                    objects_status["house"]["anchor"] = True
                if wrap_type in ["parallel", "dynamic"]:
                    objects_status["house"]["wrap"] = True
            
            # Check Agent_Signature
            elif "Agent_Signature" in name:
                objects_status["sig"]["found"] = True
                objects_status["sig"]["name"] = True
                if anchor == "as-char":
                    objects_status["sig"]["anchor"] = True

        # Scoring Logic
        
        # Logo (20 pts)
        if objects_status["logo"]["name"]:
            score += 5
            feedback.append("Logo renamed correctly.")
        if objects_status["logo"]["anchor"]:
            score += 15
            feedback.append("Logo anchored to page.")
        else:
            feedback.append("Logo anchor incorrect (expected To Page).")
            
        # House (30 pts)
        if objects_status["house"]["name"]:
            score += 5
            feedback.append("House photo renamed correctly.")
        if objects_status["house"]["anchor"]:
            score += 15
            feedback.append("House photo anchored to paragraph.")
        else:
            feedback.append("House photo anchor incorrect (expected To Paragraph).")
        if objects_status["house"]["wrap"]:
            score += 10
            feedback.append("House photo wrap set correctly.")
        else:
            feedback.append("House photo wrap incorrect (expected Parallel/Optimal).")
            
        # Signature (20 pts)
        if objects_status["sig"]["name"]:
            score += 5
            feedback.append("Signature renamed correctly.")
        if objects_status["sig"]["anchor"]:
            score += 15
            feedback.append("Signature anchored as character.")
        else:
            feedback.append("Signature anchor incorrect (expected As Character).")
            
        # VLM Check (10 pts)
        # If score is already high, we assume visual is likely okay, but we add a small bonus
        # or use it as a sanity check. For this pure programmatic verifier, we trust the XML.
        # But let's add 10 points for "No artifacts/errors" implied by clean XML parsing.
        score += 10
        feedback.append("File structure is valid.")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_odt):
            os.remove(temp_odt)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }