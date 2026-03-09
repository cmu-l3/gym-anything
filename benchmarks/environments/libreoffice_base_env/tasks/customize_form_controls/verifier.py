#!/usr/bin/env python3
"""
Verifier for customize_form_controls task.

Checks:
1. ODB file was modified.
2. Form named 'TrackEditor' exists in the ODB.
3. XML parsing of the form definition verifies:
   - TrackId control is Read-Only.
   - UnitPrice control has Currency formatting ($).
   - Composer control has Max Length 100.
"""

import json
import os
import zipfile
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODF XML Namespaces
NAMESPACES = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'xlink': 'http://www.w3.org/1999/xlink',
    'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
    'form': 'urn:oasis:names:tc:opendocument:xmlns:form:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
}

def verify_customize_form_controls(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load basic result metadata
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

    if not result.get('odb_exists', False):
        return {"passed": False, "score": 0, "feedback": "Database file not found."}
    
    if not result.get('odb_modified', False):
        return {"passed": False, "score": 0, "feedback": "Database file was not modified (did you save?)."}

    # 2. Extract and Inspect ODB
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    try:
        copy_from_env("/home/ga/chinook.odb", temp_odb.name)
        
        score = 10  # Base points for modifying DB
        feedback = []
        
        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            # Step A: Find the Form URL from root content.xml
            try:
                root_content = z.read('content.xml')
                root_tree = ET.fromstring(root_content)
                
                # Find the forms container
                # Path: office:body/office:database/db:schema-definition/db:component-collection
                # We look for a db:component with db:name="TrackEditor"
                
                form_component = None
                # Search recursively for db:component
                for comp in root_tree.findall('.//db:component', NAMESPACES):
                    name = comp.get(f"{{{NAMESPACES['db']}}}name")
                    if name == "TrackEditor":
                        form_component = comp
                        break
                
                if form_component is None:
                    return {
                        "passed": False, 
                        "score": score, 
                        "feedback": "Form 'TrackEditor' not found in database."
                    }
                
                score += 20
                feedback.append("Form 'TrackEditor' exists.")
                
                # Get the internal path (xlink:href)
                # It usually looks like "forms/Obj12"
                href = form_component.get(f"{{{NAMESPACES['xlink']}}}href")
                if not href:
                    return {"passed": False, "score": score, "feedback": "Form definition path not found."}
                
                # The actual form content is in [href]/content.xml
                form_content_path = f"{href}/content.xml"
                
            except Exception as e:
                return {"passed": False, "score": score, "feedback": f"Error parsing database structure: {e}"}

            # Step B: Parse the Form's specific content.xml
            try:
                form_xml = z.read(form_content_path)
                form_tree = ET.fromstring(form_xml)
                
                # We need to find controls bound to specific fields.
                # Controls are usually under office:body/office:text/form:form/form:control
                # But they can be nested. We look for elements with form:data-field="..."
                
                controls_map = {} # Map data-field -> element
                
                for elem in form_tree.findall('.//*[@form:data-field]', NAMESPACES):
                    field_name = elem.get(f"{{{NAMESPACES['form']}}}data-field")
                    controls_map[field_name] = elem

                # Check 1: TrackId Read-Only (30 pts)
                # Attribute: form:readonly="true"
                track_id_ctrl = controls_map.get('TrackId')
                if track_id_ctrl is not None:
                    is_readonly = track_id_ctrl.get(f"{{{NAMESPACES['form']}}}readonly")
                    if is_readonly == 'true':
                        score += 30
                        feedback.append("TrackId is Read-Only.")
                    else:
                        feedback.append(f"TrackId is NOT Read-Only (found: {is_readonly}).")
                else:
                    feedback.append("TrackId control not found on form.")

                # Check 2: UnitPrice Currency (20 pts)
                # This can be represented in a few ways depending on the wizard/control type.
                # Common: form:formatted-text with office:currency="USD" OR form:currency-symbol="$"
                price_ctrl = controls_map.get('UnitPrice')
                if price_ctrl is not None:
                    # Check for currency attributes
                    curr_symbol = price_ctrl.get(f"{{{NAMESPACES['form']}}}currency-symbol")
                    office_curr = price_ctrl.get(f"{{{NAMESPACES['office']}}}currency")
                    
                    # Also check class/control-implementation. usually "com.sun.star.form.component.CurrencyField"
                    impl = price_ctrl.get(f"{{{NAMESPACES['form']}}}control-implementation")
                    
                    is_currency = (
                        (curr_symbol == '$') or 
                        (office_curr == 'USD') or 
                        (impl and 'CurrencyField' in impl)
                    )
                    
                    if is_currency:
                        score += 20
                        feedback.append("UnitPrice is Currency formatted.")
                    else:
                        feedback.append("UnitPrice is NOT correctly formatted as Currency.")
                else:
                    feedback.append("UnitPrice control not found on form.")

                # Check 3: Composer Max Length 100 (20 pts)
                # Attribute: form:max-length="100"
                composer_ctrl = controls_map.get('Composer')
                if composer_ctrl is not None:
                    max_len = composer_ctrl.get(f"{{{NAMESPACES['form']}}}max-text-len")
                    # Note: XML attribute name might vary slightly between LO versions, 
                    # standard is form:max-text-len
                    
                    if str(max_len) == "100":
                        score += 20
                        feedback.append("Composer Max Length is 100.")
                    else:
                        feedback.append(f"Composer Max Length incorrect (found: {max_len}).")
                else:
                    feedback.append("Composer control not found on form.")

            except KeyError:
                return {"passed": False, "score": score, "feedback": f"Form content file {form_content_path} not found in ZIP."}
            except Exception as e:
                return {"passed": False, "score": score, "feedback": f"Error parsing form definition: {e}"}

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    # Final Pass/Fail Check
    # Pass if score >= 70 (Requires Form + at least 2 properties correct)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }