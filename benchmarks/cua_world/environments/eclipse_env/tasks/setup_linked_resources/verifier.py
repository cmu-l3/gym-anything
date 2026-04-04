#!/usr/bin/env python3
"""Verifier for setup_linked_resources task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_linked_resources(traj, env_info, task_info):
    """
    Verify that the agent correctly configured an Eclipse Linked Resource
    and used it to list files.
    
    Criteria:
    1. .project file contains <linkedResources> pointing to /opt/hospital/protocols (40 pts)
    2. protocol_index.txt contains the correct file list (20 pts)
    3. protocol_index.txt was created during the task (10 pts)
    4. Java source file exists (10 pts)
    5. Folder is NOT a physical copy in the workspace (20 pts)
    
    Total: 100 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('external_path', '/opt/hospital/protocols')
    expected_link_name = metadata.get('link_name', 'protocols')
    expected_files = metadata.get('expected_files', [])

    # Read result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Project Configuration (XML) - 40 pts
    project_content = result.get('project_file_content', '')
    link_verified = False
    
    if project_content:
        try:
            root = ET.fromstring(project_content)
            linked_resources = root.find('linkedResources')
            if linked_resources is not None:
                # Find the link
                found_link = False
                for link in linked_resources.findall('link'):
                    name_tag = link.find('name')
                    loc_tag = link.find('location')
                    uri_tag = link.find('locationURI')
                    
                    name = name_tag.text if name_tag is not None else ""
                    location = loc_tag.text if loc_tag is not None else (uri_tag.text if uri_tag is not None else "")
                    
                    if name == expected_link_name:
                        found_link = True
                        # Verify path (allow trailing slashes or URI format)
                        if expected_path in location:
                            score += 40
                            link_verified = True
                            feedback_parts.append(f"Linked resource '{name}' correctly configured pointing to {location}")
                        else:
                            score += 10 # Partial credit for creating link with wrong path
                            feedback_parts.append(f"Linked resource '{name}' found but points to incorrect location: {location}")
                        break
                
                if not found_link:
                    feedback_parts.append(f"No linked resource named '{expected_link_name}' found")
            else:
                feedback_parts.append("No <linkedResources> section in .project file")
        except ET.ParseError:
            feedback_parts.append("Failed to parse .project XML")
    else:
        feedback_parts.append(".project file not found or empty")

    # 2. Check Output File Content - 20 pts
    output_content = result.get('output_file_content', '')
    if output_content:
        # Check if expected files are listed
        found_files = 0
        for f in expected_files:
            if f in output_content:
                found_files += 1
        
        if found_files >= len(expected_files):
            score += 20
            feedback_parts.append("Output file contains correct file listing")
        elif found_files > 0:
            score += 10
            feedback_parts.append(f"Output file missing some entries ({found_files}/{len(expected_files)} found)")
        else:
            feedback_parts.append("Output file content incorrect")
    else:
        feedback_parts.append("Output file protocol_index.txt not found/empty")

    # 3. Check Timestamp - 10 pts
    if result.get('output_created_during_task', False):
        score += 10
        feedback_parts.append("Output file created during task")
    else:
        feedback_parts.append("Output file stale or not created")

    # 4. Check Source Code Existence - 10 pts
    if result.get('source_file_exists', False):
        score += 10
        feedback_parts.append("Java source file exists")
    else:
        feedback_parts.append("Java source file missing")

    # 5. Verify it's NOT a copy (Physical folder check) - 20 pts
    # If the user copied the folder, 'protocols' exists as a real directory.
    # If linked properly, it does NOT exist as a directory in the workspace (it's virtual).
    real_folder_exists = result.get('real_folder_exists_in_workspace', False)
    is_symlink = result.get('is_symlink', False)

    if link_verified:
        if not real_folder_exists:
            score += 20
            feedback_parts.append("Verified: Resource is linked, not copied")
        elif is_symlink:
             # Symlinks are acceptable "linking" mechanism in Linux, though not strict Eclipse feature
             score += 15
             feedback_parts.append("Resource linked via OS symlink (acceptable but not standard Eclipse link)")
        else:
            # It's a real folder copy!
            score = max(0, score - 20) # Penalize for copying
            feedback_parts.append("PENALTY: 'protocols' is a physical folder copy, not a link!")
    
    # Calculate Final Score
    passed = score >= 70 and link_verified
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }