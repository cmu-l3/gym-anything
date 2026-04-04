#!/usr/bin/env python3
"""
Verifier for sop_metadata_automation task.
Checks if LibreOffice Writer document has correct metadata properties
and if the header uses dynamic fields instead of static text.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from xml.dom import minidom
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sop_metadata(traj, env_info, task_info):
    """
    Verify the SOP metadata task.
    1. Check file existence.
    2. Unzip ODT and parse meta.xml for Title and Custom Properties.
    3. Parse styles.xml (or content.xml) to verify header uses <text:title> and <text:user-field-get>.
    4. VLM check to ensure the header renders the correct text visually.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Steam Sterilization Protocol")
    expected_props = metadata.get('expected_custom_props', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            res_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not res_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file SOP_805_Automated.odt not found"}
    
    score += 10 # File saved
    feedback_parts.append("File saved")

    # 2. Get the ODT file
    temp_odt = tempfile.NamedTemporaryFile(delete=False, suffix='.odt')
    try:
        copy_from_env(res_data['output_path'], temp_odt.name)
        
        if not zipfile.is_zipfile(temp_odt.name):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid ODT/Zip archive"}

        with zipfile.ZipFile(temp_odt.name, 'r') as z:
            # --- Check Metadata (meta.xml) ---
            try:
                meta_xml = z.read('meta.xml')
                dom = minidom.parseString(meta_xml)
                
                # Check Title
                titles = dom.getElementsByTagName('dc:title')
                actual_title = titles[0].firstChild.nodeValue if titles and titles[0].firstChild else ""
                
                if actual_title == expected_title:
                    score += 10
                    feedback_parts.append("Metadata Title Correct")
                else:
                    feedback_parts.append(f"Metadata Title Mismatch: Found '{actual_title}'")

                # Check Custom Properties
                user_def = dom.getElementsByTagName('meta:user-defined')
                found_props = {}
                for node in user_def:
                    name = node.getAttribute('meta:name')
                    val = node.firstChild.nodeValue if node.firstChild else ""
                    found_props[name] = val
                
                props_correct = True
                for k, v in expected_props.items():
                    if found_props.get(k) != v:
                        props_correct = False
                        feedback_parts.append(f"Custom Prop '{k}' mismatch or missing")
                
                if props_correct and len(expected_props) > 0:
                    score += 20
                    feedback_parts.append("Custom Properties Correct")
            
            except Exception as e:
                feedback_parts.append(f"Error parsing meta.xml: {e}")

            # --- Check Fields Usage (styles.xml usually holds header definitions) ---
            # Headers are typically in <style:master-page> -> <style:header> in styles.xml
            # But sometimes in content.xml depending on save usage. We check both.
            try:
                combined_xml = ""
                if 'styles.xml' in z.namelist():
                    combined_xml += str(z.read('styles.xml'))
                if 'content.xml' in z.namelist():
                    combined_xml += str(z.read('content.xml'))
                
                # Check for Title Field (<text:title> or <text:title-field>)
                # LibreOffice ODT usually uses <text:title> or <text:placeholder text:placeholder-type="title">
                if "text:title" in combined_xml:
                    score += 20
                    feedback_parts.append("Dynamic Title Field Used")
                else:
                    feedback_parts.append("Static text found instead of Title Field")

                # Check for User Fields (<text:user-field-get text:name="DocNumber">)
                # We need to ensure the specific field names are referenced
                if 'text:name="DocNumber"' in combined_xml and 'text:user-field-get' in combined_xml:
                    score += 10
                    feedback_parts.append("DocNumber Field Used")
                else:
                    feedback_parts.append("DocNumber Field Missing")
                    
                if 'text:name="Revision"' in combined_xml and 'text:user-field-get' in combined_xml:
                    score += 10
                    feedback_parts.append("Revision Field Used")
                else:
                    feedback_parts.append("Revision Field Missing")

            except Exception as e:
                feedback_parts.append(f"Error parsing content/styles xml: {e}")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_odt.name):
            os.unlink(temp_odt.name)

    # 4. VLM Visual Verification
    # Ensure the fields actually render the correct text
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot:
        prompt = """
        Analyze this LibreOffice Writer screenshot.
        Look at the document header (top of the page).
        Does it contain exactly the text: "Doc #: SOP-805-V2" and "Rev: 2.0"?
        Also "Title: Steam Sterilization Protocol"?
        Ignore minor spacing differences.
        """
        vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
        if vlm_res.get("success"):
            # Simple heuristic or VLM parser
            # We assume VLM returns a structured bool or text we can parse.
            # For this template, let's assume human-readable positive feedback implies success.
            # In a real system, we'd request JSON.
            # Let's refine the prompt for JSON.
            pass
        
        # Re-query with JSON enforcement
        json_prompt = """
        Look at the header in the screenshot.
        Return JSON:
        {
          "has_title_text": boolean,
          "has_doc_num_v2": boolean, 
          "has_rev_2_0": boolean
        }
        "has_doc_num_v2" is true if you see "SOP-805-V2".
        "has_rev_2_0" is true if you see "2.0".
        """
        vlm_res = query_vlm(prompt=json_prompt, image=final_screenshot)
        
        vlm_score = 0
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("has_doc_num_v2") and parsed.get("has_rev_2_0"):
                vlm_score = 20
                feedback_parts.append("VLM confirmed visual correctness")
            else:
                feedback_parts.append("VLM did not see updated values in header")
        
        score += vlm_score

    # Final check
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }