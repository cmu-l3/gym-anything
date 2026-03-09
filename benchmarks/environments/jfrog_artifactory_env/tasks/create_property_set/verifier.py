#!/usr/bin/env python3
"""
Verifier for create_property_set task in JFrog Artifactory.

Verification Strategy:
1. Parse the system configuration XML exported from Artifactory.
2. Verify 'build-info' property set exists.
3. Verify all 3 required properties exist with correct predefined values.
4. Verify 'example-repo-local' is configured to use this property set.
"""

import json
import os
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_property_set(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_set_name = metadata.get('property_set_name', 'build-info')
    expected_repo = metadata.get('repo_key', 'example-repo-local')
    expected_props = metadata.get('properties', [])

    # Temp files for artifacts
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')

    try:
        # Retrieve result JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {str(e)}"}

        if not result.get('valid_xml_captured', False):
            return {"passed": False, "score": 0, "feedback": "Failed to capture valid Artifactory configuration XML"}

        # Retrieve Config XML
        try:
            copy_from_env("/tmp/final_config.xml", temp_xml.name)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve configuration XML: {str(e)}"}

        # Parse XML
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
        except ET.ParseError as e:
            return {"passed": False, "score": 0, "feedback": f"XML Parse Error: {str(e)}"}

        # Scoring Variables
        score = 0
        max_score = 100
        feedback = []
        
        # 1. Verify Property Set Existence (15 pts)
        property_sets = root.find('propertySets')
        target_set = None
        if property_sets is not None:
            for pset in property_sets.findall('propertySet'):
                name = pset.find('name')
                if name is not None and name.text == expected_set_name:
                    target_set = pset
                    break
        
        if target_set is not None:
            score += 15
            feedback.append(f"Property set '{expected_set_name}' created.")
        else:
            return {"passed": False, "score": 0, "feedback": f"Property set '{expected_set_name}' NOT found."}

        # 2. Verify Properties and Values (10 pts per property definition + 10 pts per value set)
        xml_props = target_set.find('properties')
        if xml_props is None:
            feedback.append("No properties found in the property set.")
        else:
            existing_props = {p.find('name').text: p for p in xml_props.findall('property') if p.find('name') is not None}
            
            for expected in expected_props:
                p_name = expected['name']
                p_values = set(expected['values']) # Expected predefined values
                
                if p_name in existing_props:
                    score += 10 # Property exists
                    feedback.append(f"Property '{p_name}' found.")
                    
                    # Check predefined values if required
                    if p_values:
                        xml_p_node = existing_props[p_name]
                        xml_predefined = xml_p_node.find('predefinedValues')
                        found_values = set()
                        if xml_predefined is not None:
                            for val in xml_predefined.findall('predefinedValue'):
                                if val.text:
                                    found_values.add(val.text)
                        
                        # Check if all expected values are present
                        if p_values.issubset(found_values):
                            score += 10
                            feedback.append(f"Values for '{p_name}' are correct.")
                        else:
                            feedback.append(f"Missing values for '{p_name}'. Expected: {p_values}, Found: {found_values}")
                    else:
                        # For build.number, we just expect it to exist, no predefined values needed
                        score += 10
                else:
                    feedback.append(f"Property '{p_name}' missing.")

        # 3. Verify Repository Association (20 pts)
        # Search in localRepositories -> localRepository -> propertySets -> propertySetRef
        repo_assoc_found = False
        local_repos = root.find('localRepositories')
        if local_repos is not None:
            for repo in local_repos.findall('localRepository'):
                key = repo.find('key')
                if key is not None and key.text == expected_repo:
                    # Check assigned property sets
                    ps_node = repo.find('propertySets')
                    if ps_node is not None:
                        for ref in ps_node.findall('propertySetRef'):
                            if ref.text == expected_set_name:
                                repo_assoc_found = True
                                break
        
        if repo_assoc_found:
            score += 15 # Adjusted to match logic remainder
            feedback.append(f"Repository '{expected_repo}' is correctly associated with '{expected_set_name}'.")
        else:
            feedback.append(f"Repository '{expected_repo}' is NOT associated with '{expected_set_name}'.")

        # 4. Basic VLM / Trajectory check (Bonus/Safety 5 pts)
        # If we got this far, the XML proves config. We just add points for "app usage".
        score += 5

        passed = (score >= 60) and repo_assoc_found and (target_set is not None)
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        logger.exception("Verification failed with exception")
        return {"passed": False, "score": 0, "feedback": f"Verification system error: {str(e)}"}

    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)