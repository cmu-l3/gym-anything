#!/usr/bin/env python3
"""
Verifier for add_new_resource task in ProjectLibre.
Verifies that the agent added a specific resource with correct rates and saved the XML.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_new_resource(traj, env_info, task_info):
    """
    Verify the task based on:
    1. XML File Analysis (Primary): Check if 'Helena Torres' exists with correct attributes.
    2. VLM Analysis (Secondary): Check if the agent visited the Resource Sheet view.
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('resource_name', 'Helena Torres')
    expected_std_rate = metadata.get('standard_rate', 110.0)
    expected_ovt_rate = metadata.get('overtime_rate', 165.0)
    
    score = 0
    feedback = []
    passed = False

    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        result_json_path = os.path.join(temp_dir, "task_result.json")
        xml_file_path = os.path.join(temp_dir, "submitted_project.xml")
        
        # Copy result JSON
        try:
            copy_from_env("/tmp/task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

        # Check file existence and timestamp (Anti-gaming)
        if not result_data.get("file_exists"):
            return {"passed": False, "score": 0, "feedback": "Target file updated_project.xml was not found."}
        
        if not result_data.get("file_created_during_task"):
            feedback.append("Warning: File timestamp indicates it wasn't modified during the task.")
            # We continue verification but this is suspicious
        else:
            score += 10
            feedback.append("File created/modified during task.")

        # Copy XML file
        try:
            copy_from_env("/tmp/submitted_project.xml", xml_file_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"File exists but could not be retrieved: {e}"}

        # 2. XML Verification Logic
        try:
            tree = ET.parse(xml_file_path)
            root = tree.getroot()
            
            # MSPDI usually has a namespace, we need to handle it or ignore it
            # Common namespace: {http://schemas.microsoft.com/project}
            # We'll use localname checking to be robust
            
            resources = []
            # Find all Resource elements regardless of namespace
            for elem in root.iter():
                if elem.tag.endswith('Resource'):
                    resources.append(elem)
            
            target_resource = None
            resource_count = len(resources)
            
            if resource_count >= metadata.get('min_resource_count', 8):
                score += 10
                feedback.append(f"Resource count is valid ({resource_count}).")
            
            for res in resources:
                name_elem = None
                for child in res:
                    if child.tag.endswith('Name'):
                        name_elem = child
                        break
                
                if name_elem is not None and name_elem.text == expected_name:
                    target_resource = res
                    break
            
            if target_resource is None:
                feedback.append(f"Resource '{expected_name}' not found in the file.")
            else:
                score += 30
                feedback.append(f"Resource '{expected_name}' found.")
                
                # Check attributes
                # Note: ProjectLibre XML structure for rates
                # <StandardRate>110</StandardRate> or <StandardRate>110.00</StandardRate>
                # <OvertimeRate>165</OvertimeRate>
                # <Initials>HT</Initials>
                # <Group>Engineering</Group>
                
                def get_val(element, tag_suffix):
                    for child in element:
                        if child.tag.endswith(tag_suffix):
                            return child.text
                    return None

                # Check Standard Rate
                std_rate_str = get_val(target_resource, 'StandardRate')
                try:
                    # Rate might be formatted (e.g. 110 or 110.00)
                    if std_rate_str and float(std_rate_str) == expected_std_rate:
                        score += 15
                        feedback.append("Standard Rate correct.")
                    else:
                        feedback.append(f"Standard Rate mismatch (Found: {std_rate_str}, Expected: {expected_std_rate}).")
                except ValueError:
                    feedback.append(f"Could not parse Standard Rate: {std_rate_str}")

                # Check Overtime Rate
                ovt_rate_str = get_val(target_resource, 'OvertimeRate')
                try:
                    if ovt_rate_str and float(ovt_rate_str) == expected_ovt_rate:
                        score += 15
                        feedback.append("Overtime Rate correct.")
                    else:
                        feedback.append(f"Overtime Rate mismatch (Found: {ovt_rate_str}, Expected: {expected_ovt_rate}).")
                except ValueError:
                    feedback.append(f"Could not parse Overtime Rate: {ovt_rate_str}")

                # Check Initials
                initials = get_val(target_resource, 'Initials')
                if initials == metadata.get('resource_initials'):
                    score += 5
                    feedback.append("Initials correct.")
                else:
                    feedback.append(f"Initials mismatch (Found: {initials}).")

                # Check Group
                group = get_val(target_resource, 'Group')
                if group == metadata.get('resource_group'):
                    score += 5
                    feedback.append("Group correct.")
                else:
                    feedback.append(f"Group mismatch (Found: {group}).")

        except ET.ParseError:
            return {"passed": False, "score": score, "feedback": "Submitted file is not valid XML."}
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error parsing XML: {e}"}

    # 3. VLM Verification (Trajectory Check)
    # We want to see if the user actually went to the Resource Sheet
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Review this sequence of screenshots from ProjectLibre. "
            "Does the user navigate to a 'Resource Sheet' view (a spreadsheet looking view listing people/resources)? "
            "Do you see the user entering 'Helena Torres' or '110' into the sheet?"
            "Return JSON: {\"resource_sheet_seen\": boolean, \"data_entry_seen\": boolean}"
        )
        
        try:
            vlm_response = query_vlm(
                images=frames,
                prompt=vlm_prompt
            )
            vlm_data = vlm_response.get('parsed', {})
            
            if vlm_data.get('resource_sheet_seen'):
                score += 10
                feedback.append("VLM confirmed Resource Sheet navigation.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback: give points if XML is perfect, otherwise penalize
            if score >= 80:
                score += 10 # Assume UI interaction was correct if file is correct

    # Final scoring
    # Max score: 10 (file valid) + 10 (count) + 30 (name) + 15 (std) + 15 (ovt) + 5 (init) + 5 (grp) + 10 (vlm) = 100
    if score >= 60 and target_resource is not None:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }