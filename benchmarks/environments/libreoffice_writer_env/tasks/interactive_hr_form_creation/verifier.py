#!/usr/bin/env python3
"""
Verifier for Interactive HR Form Creation task.
Parses ODT XML to verify presence and configuration of Form Controls.
"""

import json
import os
import sys
import zipfile
import tempfile
import logging
import shutil
from xml.dom import minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_interactive_form(traj, env_info, task_info):
    """
    Verify the ODT file contains the required form controls.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Documents/onboarding_form_interactive.odt')
    
    # Create temp dir for verification
    temp_dir = tempfile.mkdtemp()
    local_odt = os.path.join(temp_dir, "output.odt")
    
    try:
        # 1. Copy file from env
        try:
            copy_from_env(output_path, local_odt)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Output file not found or could not be copied: {e}"
            }
            
        if not os.path.exists(local_odt) or os.path.getsize(local_odt) == 0:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output file exists but is empty."
            }

        # 2. Parse ODT (unzip and read content.xml)
        try:
            with zipfile.ZipFile(local_odt, 'r') as z:
                content_xml = z.read('content.xml')
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to parse ODT file structure: {e}"
            }

        # 3. Analyze XML for form controls
        dom = minidom.parseString(content_xml)
        
        # Helper to find elements by tag name (ignoring namespace prefixes usually)
        # ODF forms are typically in <form:form> inside <office:forms>
        
        text_boxes = dom.getElementsByTagName('form:text')
        date_fields = dom.getElementsByTagName('form:date')
        # Sometimes dates are formatted-text with specific properties, but standard control is form:date
        formatted_fields = dom.getElementsByTagName('form:formatted-text')
        radio_buttons = dom.getElementsByTagName('form:radio')
        check_boxes = dom.getElementsByTagName('form:checkbox')
        
        # Analyze counts
        score = 10
        feedback = ["File created and parsed successfully."]
        
        # Check Text Boxes (Expect 2: Name, Title)
        # Note: ODF XML might use different tags depending on exact control, but form:text is standard for text box
        count_text = len(text_boxes)
        if count_text >= 2:
            score += 20
            feedback.append(f"✓ Found {count_text} Text Boxes (Goal: 2)")
        elif count_text > 0:
            score += 10
            feedback.append(f"⚠ Found only {count_text} Text Boxes (Goal: 2)")
        else:
            feedback.append("✗ No Text Boxes found")

        # Check Date Field (Expect 1)
        # If form:date is 0, check formatted_fields for date-like properties if needed, 
        # but the task specifically asked for a Date Field control.
        count_date = len(date_fields)
        if count_date >= 1:
            score += 20
            feedback.append(f"✓ Found {count_date} Date Field")
        else:
            # Fallback check: sometimes generic formatted fields are used
            if len(formatted_fields) > 0:
                 feedback.append("⚠ No explicit Date Field found, but formatted text fields exist (partial credit potentially missed if strict).")
            feedback.append("✗ No Date Field found")

        # Check Check Box (Expect 1)
        count_check = len(check_boxes)
        if count_check >= 1:
            score += 20
            feedback.append(f"✓ Found {count_check} Check Box")
        else:
            feedback.append("✗ No Check Box found")

        # Check Radio Buttons (Expect 2)
        count_radio = len(radio_buttons)
        radios_passed = False
        grouping_passed = False
        
        if count_radio >= 2:
            score += 15
            radios_passed = True
            feedback.append(f"✓ Found {count_radio} Radio Buttons (Goal: 2)")
            
            # Check Grouping (Same 'form:name' attribute)
            # Collect names
            names = set()
            for radio in radio_buttons:
                # ODF uses 'form:name' for grouping
                name = radio.getAttribute('form:name')
                # Also check 'form:group-name' if present (newer standards)
                if not name:
                    name = radio.getAttribute('form:group-name')
                if name:
                    names.add(name)
            
            # If we have at least 2 radios and they share 1 name, or fewer names than radios implies grouping
            # Ideally for 2 radios: 1 unique name shared by both
            if len(names) == 1 and count_radio >= 2:
                score += 15
                grouping_passed = True
                feedback.append(f"✓ Radio Buttons are correctly grouped (Group Name: '{list(names)[0]}')")
            else:
                feedback.append(f"✗ Radio Buttons are NOT grouped correctly. Found names: {list(names)}")
        else:
            feedback.append("✗ Insufficient Radio Buttons found")

        # Final Evaluation
        passed = (score >= 85)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        logger.exception("Verification error")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}
        
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)