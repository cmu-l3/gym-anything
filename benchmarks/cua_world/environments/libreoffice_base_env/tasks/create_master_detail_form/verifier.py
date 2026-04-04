#!/usr/bin/env python3
"""
Verifier for create_master_detail_form task.

Verifies that:
1. The ODB file was modified.
2. A form named 'ArtistDiscography' exists within the ODB container.
3. The form structure contains a Master-Detail relationship:
   - Outer form bound to 'Artist'
   - Inner/Sub form bound to 'Album'
"""

import json
import os
import zipfile
import tempfile
import xml.etree.ElementTree as ET
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODF Namespaces
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'xlink': 'http://www.w3.org/1999/xlink',
    'db': 'urn:oasis:names:tc:opendocument:xmlns:database:1.0',
    'form': 'urn:oasis:names:tc:opendocument:xmlns:form:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0'
}

def verify_master_detail_form(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_form_name = metadata.get('form_name', 'ArtistDiscography')
    expected_master = metadata.get('master_table', 'Artist')
    expected_detail = metadata.get('detail_table', 'Album')
    
    scoring = metadata.get('scoring', {
        "form_exists": 20,
        "master_correct": 20,
        "detail_correct": 20,
        "hierarchy_exists": 30,
        "file_saved": 10
    })

    score = 0
    feedback_parts = []
    
    # 1. Get task result JSON
    task_result_path = "/tmp/task_result.json"
    local_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env(task_result_path, local_result_json)
        with open(local_result_json, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(local_result_json):
            os.unlink(local_result_json)

    if not result_data.get('odb_exists'):
        return {"passed": False, "score": 0, "feedback": "Database file deleted or missing."}

    if result_data.get('odb_modified'):
        score += scoring['file_saved']
        feedback_parts.append("Database file saved.")
    else:
        feedback_parts.append("Database file not saved (timestamp unchanged).")

    # 2. Get ODB file
    odb_remote_path = result_data.get('odb_path', '/home/ga/chinook.odb')
    local_odb_path = tempfile.NamedTemporaryFile(delete=False, suffix='.odb').name
    try:
        copy_from_env(odb_remote_path, local_odb_path)
    except Exception as e:
        if os.path.exists(local_odb_path):
            os.unlink(local_odb_path)
        return {"passed": False, "score": score, "feedback": f"Failed to copy ODB file: {e}"}

    # 3. Analyze ODB Structure
    form_content_path = None
    
    try:
        with zipfile.ZipFile(local_odb_path, 'r') as zf:
            # 3a. Parse root content.xml to find the form registration
            if 'content.xml' not in zf.namelist():
                raise ValueError("Invalid ODB: content.xml missing")
            
            with zf.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()
                
                # Find the form component in the database registry
                # Path: office:body -> office:database -> db:table-representations... 
                # OR db:forms -> db:component-collection -> db:component (name=ArtistDiscography)
                
                # We look for a component with the specific name
                # db:component-collection usually holds forms and reports
                found_form = False
                for component in root.findall(".//db:component", NS):
                    name = component.get(f"{{{NS['db']}}}name")
                    if name == target_form_name:
                        href = component.get(f"{{{NS['xlink']}}}href")
                        if href:
                            form_content_path = href
                            found_form = True
                            break
                
                if found_form:
                    score += scoring['form_exists']
                    feedback_parts.append(f"Form '{target_form_name}' found in database registry.")
                else:
                    feedback_parts.append(f"Form '{target_form_name}' NOT found in database.")
                    return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

            # 3b. Parse the specific form XML
            # The href might be relative, e.g., "forms/Obj12". In the zip, it usually needs "content.xml" appended if it's a folder,
            # BUT in ODB, the href usually points to the folder, and the content is in href + "/content.xml"
            target_xml_path = f"{form_content_path}/content.xml"
            
            if target_xml_path not in zf.namelist():
                # Try without /content.xml just in case
                if form_content_path in zf.namelist():
                     target_xml_path = form_content_path
                else:
                     feedback_parts.append(f"Form storage path '{target_xml_path}' not found in ZIP.")
                     return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

            with zf.open(target_xml_path) as f:
                form_tree = ET.parse(f)
                form_root = form_tree.getroot()
                
                # 4. Analyze Form DOM for Master-Detail structure
                # We expect: <form:form ... command="Artist"> ... <form:form ... command="Album"> ... </form:form> </form:form>
                
                # Find all form definitions
                # Note: There is usually a top-level "Standard" form container
                
                master_found = False
                detail_found = False
                hierarchy_correct = False
                
                all_forms = form_root.findall(".//form:form", NS)
                
                for f_elem in all_forms:
                    command = f_elem.get(f"{{{NS['form']}}}command")
                    # Command can be table name directly or SQL
                    if command and expected_master.lower() in command.lower():
                        master_found = True
                        
                        # Check children for detail form
                        children = f_elem.findall("form:form", NS)
                        for child in children:
                            child_cmd = child.get(f"{{{NS['form']}}}command")
                            if child_cmd and expected_detail.lower() in child_cmd.lower():
                                detail_found = True
                                hierarchy_correct = True
                                break
                        
                        if hierarchy_correct:
                            break
                
                # Fallback search if direct nesting logic missed it (e.g. intermediate elements)
                if not master_found:
                    # Just look for existence of both data sources
                    cmds = [f.get(f"{{{NS['form']}}}command", "") for f in all_forms]
                    if any(expected_master.lower() in c.lower() for c in cmds):
                        master_found = True
                    if any(expected_detail.lower() in c.lower() for c in cmds):
                        detail_found = True

                if master_found:
                    score += scoring['master_correct']
                    feedback_parts.append(f"Main form bound to '{expected_master}'.")
                else:
                    feedback_parts.append(f"Main form NOT bound to '{expected_master}'.")

                if detail_found:
                    score += scoring['detail_correct']
                    feedback_parts.append(f"Subform bound to '{expected_detail}'.")
                else:
                    feedback_parts.append(f"Subform NOT bound to '{expected_detail}'.")

                if hierarchy_correct:
                    score += scoring['hierarchy_exists']
                    feedback_parts.append("Master-Detail hierarchy verified.")
                elif master_found and detail_found:
                     feedback_parts.append("Both tables present, but correct nesting not detected.")
                
    except Exception as e:
        feedback_parts.append(f"Error parsing ODB structure: {str(e)}")
        # If we crashed during parsing but validated form existence, return what we have
        
    finally:
        if os.path.exists(local_odb_path):
            os.unlink(local_odb_path)

    # Final check
    passed = score >= 80  # Require essentially everything to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }