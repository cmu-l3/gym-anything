#!/usr/bin/env python3
"""
Verifier for create_form_with_lookup task.

Verifies that:
1. The ODB file was modified.
2. A form named 'CustomerEntry' exists in the ODB package.
3. The form contains a List Box control.
4. The List Box is bound to 'SupportRepId'.
5. The List Box uses a SQL source referencing the 'Employee' table.
"""

import json
import os
import zipfile
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_form_with_lookup(traj, env_info, task_info):
    """
    Verify the LibreOffice Base form creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Scoring weights
    SCORE_FORM_EXISTS = 20
    SCORE_LISTBOX_USED = 30
    SCORE_BOUND_FIELD = 20
    SCORE_SQL_SOURCE = 30
    
    score = 0
    feedback_parts = []
    
    # 1. Get result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('odb_modified', False):
        return {"passed": False, "score": 0, "feedback": "Database file was not saved/modified."}

    # 2. Get ODB file
    temp_odb = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    try:
        copy_from_env("/tmp/submission.odb", temp_odb.name)
        
        if not zipfile.is_zipfile(temp_odb.name):
             return {"passed": False, "score": 0, "feedback": "Submission is not a valid ODB (ZIP) file."}

        with zipfile.ZipFile(temp_odb.name, 'r') as z:
            file_list = z.namelist()
            
            # A. Check for Form Name in content.xml (The global content registry)
            # Forms are listed in <db:forms> inside content.xml
            form_found = False
            form_path = None
            
            if 'content.xml' in file_list:
                content_xml = z.read('content.xml')
                root = ET.fromstring(content_xml)
                
                # Namespaces usually used in ODB
                ns = {
                    'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
                    'xlink': 'http://www.w3.org/1999/xlink'
                }
                
                # Find component with name "CustomerEntry"
                # Path structure: office:body -> office:database -> db:forms -> db:component
                # Note: This finds the LINK to the form (which is a sub-document)
                for component in root.findall(".//db:component", ns):
                    name = component.get("{urn:oasis:names:tc:opendocument:xmlns:database:1.0}name")
                    if name == "CustomerEntry":
                        form_found = True
                        href = component.get("{http://www.w3.org/1999/xlink}href")
                        if href:
                            # href is usually like "forms/Obj11"
                            # The actual content is in "forms/Obj11/content.xml"
                            form_path = f"{href}/content.xml"
                        break
            
            if form_found:
                score += SCORE_FORM_EXISTS
                feedback_parts.append("Form 'CustomerEntry' created.")
            else:
                return {"passed": False, "score": 0, "feedback": "Form 'CustomerEntry' not found in database."}

            # B. Analyze the Form Definition (Sub-document)
            if form_path and form_path in file_list:
                form_content = z.read(form_path)
                form_root = ET.fromstring(form_content)
                
                # Namespaces for Form definitions
                form_ns = {
                    'form': 'urn:oasis:names:tc:opendocument:xmlns:form:1.0',
                    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
                }
                
                # Find the List Box control
                # Look for <form:listbox> with data-field="SupportRepId"
                listbox_found = False
                bound_correctly = False
                sql_source_found = False
                
                # Search all listboxes
                for lb in form_root.findall(".//form:listbox", form_ns):
                    listbox_found = True
                    
                    data_field = lb.get("{urn:oasis:names:tc:opendocument:xmlns:form:1.0}data-field")
                    if data_field and data_field.lower() == "supportrepid":
                        bound_correctly = True
                        
                        # Check source
                        list_source = lb.get("{urn:oasis:names:tc:opendocument:xmlns:form:1.0}list-source")
                        source_type = lb.get("{urn:oasis:names:tc:opendocument:xmlns:form:1.0}list-source-type")
                        
                        # We accept SQL type (sql) or Table type (table) or Query type (query)
                        # But specific requirement was displaying Names (joined or from query)
                        # So we check if "Employee" is mentioned in source
                        if list_source and "employee" in list_source.lower():
                            sql_source_found = True
                        
                        # If simple "table" source type, they might not be joining names, which is half-credit
                        # But task asked for specific SELECT ... || ...
                        break
                
                if bound_correctly:
                    score += SCORE_LISTBOX_USED  # If we found a listbox on the right field, these points imply listbox usage
                    score += SCORE_BOUND_FIELD
                    feedback_parts.append("List Box control correctly bound to SupportRepId.")
                    
                    if sql_source_found:
                        score += SCORE_SQL_SOURCE
                        feedback_parts.append("List source correctly references Employee table.")
                    else:
                        feedback_parts.append("List source does not appear to query Employee table correctly.")
                elif listbox_found:
                    # Found a listbox but not bound to SupportRepId
                    score += SCORE_LISTBOX_USED
                    feedback_parts.append("List Box control found, but NOT bound to SupportRepId.")
                else:
                    feedback_parts.append("No List Box control found in the form.")
            else:
                feedback_parts.append(f"Could not locate form definition file at {form_path}")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error verifying ODB structure: {e}"}
    finally:
        if os.path.exists(temp_odb.name):
            os.unlink(temp_odb.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }