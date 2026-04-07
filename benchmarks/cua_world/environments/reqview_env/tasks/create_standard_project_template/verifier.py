#!/usr/bin/env python3
"""
Verifier for create_standard_project_template task.

Verifies:
1. Project folder creation and valid project.json structure.
2. Correct project metadata (ID, Title).
3. Existence of required documents (NEEDS, SRS, TESTS).
4. Custom attribute configuration in SRS.
"""

import json
import os
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_standard_project_template(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get metadata from task info
    metadata = task_info.get('metadata', {})
    expected_proj_id = metadata.get('project_id', 'STD')
    expected_proj_title = metadata.get('project_title', 'Company Standard Template')
    expected_attr_id = metadata.get('attribute_id', 'complexity')
    expected_attr_vals = metadata.get('attribute_values', ["Low", "Medium", "High"])

    # Setup temp directory for analysis
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Retrieve result metadata
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        score = 0
        feedback_parts = []
        
        # Check if project exists (10 points)
        if not result_data.get('project_exists', False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Project folder not found at expected location."
            }
        
        score += 10
        feedback_parts.append("Project folder created")

        # Check timestamp (anti-gaming)
        if not result_data.get('project_created_during_task', False):
            feedback_parts.append("WARNING: Project file timestamp outside task window")
            # We don't fail immediately but penalty might apply or manual review needed
        
        # 2. Analyze project.json
        project_json_path = os.path.join(temp_dir, "project.json")
        try:
            copy_from_env("/tmp/task_export/project.json", project_json_path)
            with open(project_json_path, 'r') as f:
                project_data = json.load(f)
                
            # Check ID and Title (10 points)
            p_id = project_data.get('id', '')
            p_title = project_data.get('name', '') # ReqView uses 'name' for title in root
            
            if p_id == expected_proj_id:
                score += 5
            else:
                feedback_parts.append(f"Project ID mismatch: got '{p_id}'")
                
            if expected_proj_title.lower() in p_title.lower():
                score += 5
            else:
                feedback_parts.append(f"Project Title mismatch: got '{p_title}'")

            # Check Documents (30 points)
            # Documents in project.json might be listed in 'documents' array or implied by file structure.
            # In ReqView folder format, project.json often contains the list of documents.
            doc_list = project_data.get('documents', [])
            # doc_list is usually a list of strings (IDs) or objects
            doc_ids = []
            for d in doc_list:
                if isinstance(d, dict):
                    doc_ids.append(d.get('id', ''))
                elif isinstance(d, str):
                    doc_ids.append(d)
            
            # If doc_list is empty/strings, we might need to rely on the IDs found.
            # However, in folder format, docs are folders. The verifier check depends on project.json structure.
            # Let's assume project.json tracks the IDs.
            
            missing_docs = []
            for req_doc in ['NEEDS', 'SRS', 'TESTS']:
                if req_doc not in doc_ids:
                    missing_docs.append(req_doc)
            
            if not missing_docs:
                score += 30
                feedback_parts.append("All 3 documents created")
            else:
                score += (3 - len(missing_docs)) * 10
                feedback_parts.append(f"Missing documents: {missing_docs}")

        except Exception as e:
            feedback_parts.append(f"Error parsing project.json: {str(e)}")

        # 3. Analyze SRS.json for Custom Attribute (50 points)
        srs_json_path = os.path.join(temp_dir, "SRS.json")
        if result_data.get('srs_exists', False):
            try:
                copy_from_env("/tmp/task_export/SRS.json", srs_json_path)
                with open(srs_json_path, 'r') as f:
                    srs_data = json.load(f)
                
                # Check for attribute definition
                # Attributes can be in 'attributes' dictionary or list
                # ReqView 2.x usually stores document-specific attributes in the document file
                # or project-wide attributes in project.json. The task instructions said "Open SRS document attributes".
                # If they are document specific, they appear in SRS.json. If project global, project.json.
                # We check both to be generous, but task implies SRS specific.
                
                attributes = srs_data.get('attributes', {})
                # If list, convert to dict by id
                if isinstance(attributes, list):
                    attributes = {a.get('id'): a for a in attributes}
                
                # Look for complexity
                target_attr = None
                
                # Check by ID
                if expected_attr_id in attributes:
                    target_attr = attributes[expected_attr_id]
                else:
                    # Check by Name if ID doesn't match
                    for k, v in attributes.items():
                        if v.get('name', '').lower() == "complexity":
                            target_attr = v
                            break
                
                if target_attr:
                    score += 20
                    feedback_parts.append("'Complexity' attribute found")
                    
                    # Check Type (10 points)
                    # Type could be 'enum', 'enumeration', or 'xg-enum' etc
                    attr_type = target_attr.get('type', '').lower()
                    if 'enum' in attr_type:
                        score += 10
                    else:
                        feedback_parts.append(f"Attribute type mismatch: {attr_type}")

                    # Check Values (20 points)
                    # Values might be in 'values' or 'options'
                    vals = target_attr.get('values', [])
                    if not vals: 
                        vals = target_attr.get('options', [])
                    
                    # Normalize vals to list of strings
                    str_vals = []
                    for v in vals:
                        if isinstance(v, dict):
                            str_vals.append(v.get('key', v.get('name', '')))
                        else:
                            str_vals.append(str(v))
                    
                    matches = 0
                    for ev in expected_attr_vals:
                        if any(ev.lower() == sv.lower() for sv in str_vals):
                            matches += 1
                    
                    if matches == 3:
                        score += 20
                        feedback_parts.append("Enum values correct")
                    elif matches > 0:
                        score += 10
                        feedback_parts.append(f"Partial enum values ({matches}/3)")
                    else:
                        feedback_parts.append("Enum values incorrect")

                else:
                    feedback_parts.append("Attribute 'Complexity' not found in SRS")

            except Exception as e:
                feedback_parts.append(f"Error parsing SRS.json: {str(e)}")
        else:
            feedback_parts.append("SRS.json not found (Attribute check failed)")

        passed = score >= 70
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        shutil.rmtree(temp_dir)