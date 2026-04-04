#!/usr/bin/env python3
"""
Verifier for create_repo_layout task.

Verifies that a custom Repository Layout was created in JFrog Artifactory
by parsing the system configuration XML exported from the environment.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET

def verify_create_repo_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('layout_name', 'flat-org-layout')
    expected_artifact_pattern = metadata.get('expected_artifact_pattern', '[org]/[module]/[baseRev]/[module]-[baseRev](-[classifier]).[ext]')
    expected_descriptor_pattern = metadata.get('expected_descriptor_pattern', '[org]/[module]/[baseRev]/[module]-[baseRev].pom')
    expected_folder_regexp = metadata.get('expected_folder_integration_regexp', 'SNAPSHOT')
    expected_file_regexp = metadata.get('expected_file_integration_regexp', 'SNAPSHOT')

    # Temporary files
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')

    try:
        # 1. Get result JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

        if not result.get('config_retrieved', False):
            return {"passed": False, "score": 0, "feedback": "Failed to retrieve Artifactory system configuration"}

        # 2. Get system config XML
        try:
            copy_from_env("/tmp/system_config.xml", temp_xml.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve configuration XML: {str(e)}"}

        # 3. Parse XML and find the layout
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
            
            # Artifactory config XML structure usually has <repoLayouts> containing multiple <repoLayout>
            # Namespace handling might be needed depending on the exact XML version, usually it's plain or simple namespace
            
            layout_found = None
            for layout in root.findall(".//repoLayout"):
                name_elem = layout.find("name")
                if name_elem is not None and name_elem.text == expected_name:
                    layout_found = layout
                    break
            
            if layout_found is None:
                return {
                    "passed": False, 
                    "score": 0, 
                    "feedback": f"Repository layout '{expected_name}' not found in system configuration."
                }

            # 4. Verify fields
            score = 30 # Base score for existence
            feedback_parts = [f"Layout '{expected_name}' found."]
            
            # Helper to check fields safely
            def check_field(elem_name, expected, points):
                elem = layout_found.find(elem_name)
                val = elem.text if elem is not None else ""
                if val == expected:
                    return points, f"{elem_name} correct."
                return 0, f"{elem_name} incorrect (expected '{expected}', got '{val}')."

            s, f = check_field("artifactPathPattern", expected_artifact_pattern, 25)
            score += s
            feedback_parts.append(f)

            s, f = check_field("descriptorPathPattern", expected_descriptor_pattern, 15)
            score += s
            feedback_parts.append(f)

            s, f = check_field("folderIntegrationRevisionRegExp", expected_folder_regexp, 15)
            score += s
            feedback_parts.append(f)

            s, f = check_field("fileIntegrationRevisionRegExp", expected_file_regexp, 15)
            score += s
            feedback_parts.append(f)

            passed = score >= 100
            
            return {
                "passed": passed,
                "score": score,
                "feedback": " ".join(feedback_parts)
            }

        except ET.ParseError:
            return {"passed": False, "score": 0, "feedback": "Failed to parse system configuration XML."}

    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)