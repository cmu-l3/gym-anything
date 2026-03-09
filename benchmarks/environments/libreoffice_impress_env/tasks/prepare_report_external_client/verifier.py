#!/usr/bin/env python3
"""
Verifier for Prepare Report for External Client task.
Verifies that:
1. The external link to the spreadsheet is broken (data embedded).
2. The "Confidential" watermark is removed from the Master Slide.
"""

import json
import zipfile
import xml.etree.ElementTree as ET
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prepare_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    try:
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    if not result.get("file_modified"):
        return {"passed": False, "score": 0, "feedback": "File was not modified/saved"}

    # Copy the ODP file for analysis
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    odp_path = result.get("file_path", "/home/ga/Documents/Presentations/monthly_review.odp")
    
    try:
        copy_from_env(odp_path, temp_odp.name)
    except Exception as e:
        os.unlink(temp_odp.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve presentation file: {e}"}

    # Analyze ODP content
    score = 0
    feedback_parts = []
    
    try:
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            # 1. Verify Link is Broken
            # We check content.xml for draw:object or draw:object-ole
            # A linked object has xlink:href pointing to the file
            # An embedded object has xlink:href pointing to internal structure (e.g. "./Object 1")
            
            content_xml = z.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Namespaces usually used in ODF
            ns = {
                'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
                'xlink': 'http://www.w3.org/1999/xlink',
                'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0'
            }
            
            # Find all objects
            objects = root.findall('.//draw:object', ns) + root.findall('.//draw:object-ole', ns)
            
            external_link_found = False
            object_exists = False
            
            for obj in objects:
                object_exists = True
                href = obj.get(f"{{{ns['xlink']}}}href", "")
                
                # Check if it looks like an external file link
                if "financial_data.ods" in href and ".." not in href and "./" not in href:
                     # Strict check: if the filename is there without a clear internal indicator
                     # In ODF, internal links often look like "./Object 1"
                     # External look like "../financial_data.ods" or "file://..." or just "financial_data.ods"
                     # If the link was broken/embedded, it should NOT reference the external filename anymore
                     # OR it might reference it but the mode changes. 
                     # However, typically breaking a link changes the href to an internal representation.
                     pass

                # A simpler check: Does any attribute specifically point to the external file structure?
                # When embedded, the href usually becomes something like "./Object 1"
                if "financial_data.ods" in href:
                    external_link_found = True
                    feedback_parts.append(f"Found external link: {href}")
            
            if not object_exists:
                feedback_parts.append("❌ Spreadsheet object missing (deleted?)")
            elif not external_link_found:
                score += 50
                feedback_parts.append("✅ External link broken (data embedded)")
            else:
                feedback_parts.append("❌ Link to 'financial_data.ods' still active")

            # 2. Verify Watermark Removed
            # The watermark is in the Master Page, which is defined in styles.xml (usually)
            # But sometimes in content.xml for automatic styles. We check both.
            
            styles_xml = z.read('styles.xml')
            styles_root = ET.fromstring(styles_xml)
            
            forbidden_text = "Confidential - Internal Use Only"
            watermark_found = False
            
            # Helper to search text in XML tree
            def find_text_in_tree(tree_root, text_to_find):
                for elem in tree_root.iter():
                    if elem.text and text_to_find in elem.text:
                        return True
                return False
            
            if find_text_in_tree(styles_root, forbidden_text) or find_text_in_tree(root, forbidden_text):
                watermark_found = True
            
            if not watermark_found:
                score += 50
                feedback_parts.append("✅ Confidential watermark removed")
            else:
                feedback_parts.append("❌ Confidential watermark still present")

    except Exception as e:
        feedback_parts.append(f"Error parsing ODP file: {e}")
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }