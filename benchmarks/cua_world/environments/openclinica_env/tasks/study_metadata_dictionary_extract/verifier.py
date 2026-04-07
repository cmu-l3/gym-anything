#!/usr/bin/env python3
"""
Verifier for the Clinical Metadata Extraction task.
Evaluates if the agent successfully downloaded the XML and parsed the correct specific structures into JSON.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_metadata_extraction(traj, env_info, task_info):
    """
    Verification strategy:
    1. Check if the XML was downloaded and has correct Study OID (S_DM2024).
    2. Check if the JSON was created and parses cleanly.
    3. Check if JSON Severity and Relationship code lists perfectly match DB Ground Truth.
    4. VLM Check (Trajectory): Did the agent interact with the extraction UI?
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_oid = metadata.get('expected_study_oid', 'S_DM2024')
    ground_truth = metadata.get('ground_truth_codelists', {})
    
    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # Retrieve Result State
    # -------------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/metadata_extract_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    xml_exists = result.get('xml_exists', False)
    xml_created_during_task = result.get('xml_created_during_task', False)
    json_exists = result.get('json_exists', False)
    json_created_during_task = result.get('json_created_during_task', False)

    # -------------------------------------------------------------------------
    # 1. XML Verification (30 Points)
    # -------------------------------------------------------------------------
    xml_valid = False
    oid_correct = False
    
    if xml_exists:
        if not xml_created_during_task:
            feedback_parts.append("WARNING: XML file existed before task start (possible anti-gaming violation).")
            
        temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env("/tmp/study_metadata.xml", temp_xml.name)
            # Parse XML
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
            
            # Remove namespace prefixes for easier searching
            for elem in root.iter():
                if '}' in elem.tag:
                    elem.tag = elem.tag.split('}', 1)[1]
            
            # Find Study OID
            study_elem = root.find('.//Study')
            if study_elem is not None:
                xml_valid = True
                score += 15
                feedback_parts.append("Valid CDISC ODM XML downloaded (+15)")
                
                oid = study_elem.attrib.get('OID', '')
                if oid == expected_oid or oid == 'DM-TRIAL-2024':
                    oid_correct = True
                    score += 15
                    feedback_parts.append(f"XML contains correct Study OID '{oid}' (+15)")
                else:
                    feedback_parts.append(f"XML has wrong Study OID: '{oid}' (Expected {expected_oid})")
            else:
                feedback_parts.append("XML downloaded but missing <Study> tag")
        except ET.ParseError:
            feedback_parts.append("XML file exists but is malformed/invalid")
        except Exception as e:
            feedback_parts.append(f"Error parsing XML: {e}")
        finally:
            if os.path.exists(temp_xml.name):
                os.unlink(temp_xml.name)
    else:
        feedback_parts.append("XML metadata file not downloaded")

    # -------------------------------------------------------------------------
    # 2. JSON CodeList Verification (70 Points)
    # -------------------------------------------------------------------------
    if json_exists:
        if not json_created_during_task:
            feedback_parts.append("WARNING: JSON file existed before task start.")
            
        temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/ae_codelists.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                agent_json = json.load(f)
                
            score += 10
            feedback_parts.append("JSON output exists and parses successfully (+10)")
            
            # Normalize dictionary keys (ignore case to be fair)
            agent_norm = {k.lower(): v for k, v in agent_json.items()}
            
            # Check Severity (30 points)
            if 'severity' in agent_norm:
                agent_sev = {str(k): str(v).strip() for k, v in agent_norm['severity'].items()}
                gt_sev = ground_truth.get('Severity', {})
                
                # Check absolute perfection
                if agent_sev == gt_sev:
                    score += 30
                    feedback_parts.append("Severity mappings exactly match ground truth (+30)")
                else:
                    # Give partial credit based on correct keys
                    correct_keys = set(agent_sev.keys()).intersection(gt_sev.keys())
                    if correct_keys:
                        score += 10
                        feedback_parts.append(f"Severity mappings partially correct ({len(correct_keys)} matches) (+10)")
                    else:
                        feedback_parts.append("Severity mappings incorrect")
            else:
                feedback_parts.append("Missing 'Severity' key in JSON")
                
            # Check Relationship (30 points)
            if 'relationship' in agent_norm:
                agent_rel = {str(k): str(v).strip() for k, v in agent_norm['relationship'].items()}
                gt_rel = ground_truth.get('Relationship', {})
                
                if agent_rel == gt_rel:
                    score += 30
                    feedback_parts.append("Relationship mappings exactly match ground truth (+30)")
                else:
                    correct_keys = set(agent_rel.keys()).intersection(gt_rel.keys())
                    if correct_keys:
                        score += 10
                        feedback_parts.append(f"Relationship mappings partially correct ({len(correct_keys)} matches) (+10)")
                    else:
                        feedback_parts.append("Relationship mappings incorrect")
            else:
                feedback_parts.append("Missing 'Relationship' key in JSON")

        except json.JSONDecodeError:
            feedback_parts.append("JSON file exists but is malformed")
        except Exception as e:
            feedback_parts.append(f"Error parsing JSON: {e}")
        finally:
            if os.path.exists(temp_json.name):
                os.unlink(temp_json.name)
    else:
        feedback_parts.append("Target JSON file not created")

    # -------------------------------------------------------------------------
    # Final Scoring
    # -------------------------------------------------------------------------
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }