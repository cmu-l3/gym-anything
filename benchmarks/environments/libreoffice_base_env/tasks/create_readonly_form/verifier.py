#!/usr/bin/env python3
"""
Verifier for create_readonly_form task.

Verifies:
1. 'Customer_ReadOnly' form exists in ODB.
2. Form is bound to 'Customer' table.
3. XML attributes for allow-inserts, allow-updates, and allow-deletes are set to 'false'.
"""

import json
import os
import sys
import zipfile
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_readonly_form(traj, env_info, task_info):
    """
    Verify the ODB file contains the correctly configured Read-Only form.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_form = metadata.get('expected_form_name', 'Customer_ReadOnly')
    target_table = metadata.get('target_table', 'Customer')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve the ODB file
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Get result JSON for basic checks
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        if not result_data.get('file_modified', False):
            feedback_parts.append("Database file was not saved (timestamp unchanged).")
            # We continue verification in case they did work but didn't save *after* the initial timestamp check, 
            # though usually this is a fail. We'll penalize via scoring logic if needed, 
            # but usually modification is a prerequisite for the ODB to contain new forms.
        
        # Get the actual database file
        copy_from_env("/home/ga/chinook.odb", temp_odb.name)
        
        if not zipfile.is_zipfile(temp_odb.name):
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve valid ODB file."}
            
        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            # 2. Find the form internal path in root content.xml
            try:
                root_content = z.read('content.xml')
            except KeyError:
                return {"passed": False, "score": 0, "feedback": "Corrupt ODB: missing root content.xml"}
                
            root_tree = ET.fromstring(root_content)
            
            # Namespaces
            ns = {
                'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                'xlink': 'http://www.w3.org/1999/xlink',
                'form': 'urn:oasis:names:tc:opendocument:xmlns:form:1.0',
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
            }
            
            # Find component with the specific name
            form_comp = None
            # Search path: office:body -> office:database -> db:forms -> db:component
            # But db:forms can be nested (folders). We search recursively for db:component
            for comp in root_tree.findall(".//db:component", ns):
                # Check for "db:name" attribute. ET requires full qualified name for get()
                name_attr = comp.get(f"{{{ns['db']}}}name")
                if name_attr == expected_form:
                    form_comp = comp
                    break
            
            if form_comp is None:
                return {
                    "passed": False, 
                    "score": 0, 
                    "feedback": f"Form '{expected_form}' not found in database."
                }
            
            score += 20
            feedback_parts.append(f"Form '{expected_form}' created.")
            
            # Get internal path
            href = form_comp.get(f"{{{ns['xlink']}}}href")
            # href is typically "forms/Obj12". The content is inside that folder as "content.xml"
            form_xml_path = f"{href}/content.xml"
            
            try:
                form_xml_content = z.read(form_xml_path)
            except KeyError:
                return {
                    "passed": False, 
                    "score": score, 
                    "feedback": f"Form content missing at {form_xml_path}."
                }
                
            # 3. Parse form definition
            form_tree = ET.fromstring(form_xml_content)
            
            # Find the logical form element <form:form>
            # There might be multiple (subforms), we look for the one bound to 'Customer'
            target_form_elem = None
            
            for f in form_tree.findall(".//form:form", ns):
                command = f.get(f"{{{ns['form']}}}command")
                # Command could be "Customer" or "Public.Customer" or similar
                if command and target_table.lower() in command.lower():
                    target_form_elem = f
                    break
            
            # Fallback: if only one form exists, assume it's the right one if name matches expectation logic
            if target_form_elem is None:
                forms = form_tree.findall(".//form:form", ns)
                if len(forms) > 0:
                    # Heuristic: check if this form controls fields that look like customer fields
                    # (Simplified: just take the first one and warn)
                    target_form_elem = forms[0]
                    feedback_parts.append("Warning: Could not verify exact table binding by name, checking first form found.")
            
            if target_form_elem is None:
                 return {
                    "passed": False, 
                    "score": score, 
                    "feedback": "Form definition found but no data form element detected."
                }
                
            score += 20
            feedback_parts.append(f"Form bound to table.")
            
            # 4. Check Security Properties
            # Attributes: form:allow-inserts, form:allow-updates, form:allow-deletes
            # ODF boolean is "true" or "false"
            
            props = {
                "allow-inserts": "Allow Additions",
                "allow-updates": "Allow Modifications",
                "allow-deletes": "Allow Deletions"
            }
            
            security_passed = True
            
            for attr, label in props.items():
                val = target_form_elem.get(f"{{{ns['form']}}}{attr}")
                # If attribute is missing, default is usually 'true' (allowed)
                # We want it explicitly set to 'false'
                if val == 'false':
                    score += 20
                    feedback_parts.append(f"{label}: NO (Correct)")
                else:
                    security_passed = False
                    val_display = val if val else "true (default)"
                    feedback_parts.append(f"{label}: {val_display} (Expected: No/false)")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
        
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Final evaluation
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }