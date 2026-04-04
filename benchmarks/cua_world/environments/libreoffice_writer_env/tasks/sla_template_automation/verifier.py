#!/usr/bin/env python3
"""
Verifier for SLA Template Automation task.

Verifies:
1. ODT file existence and timestamp.
2. Definition of specific User Fields (ClientName, ContractDate, etc.) in the ODF XML.
3. Usage/Insertion of these fields in the document body.
4. Absence of original text placeholders (e.g., [CLIENT]).
"""

import json
import tempfile
import os
import zipfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODF Namespaces
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
}

def verify_sla_automation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vars = metadata.get('variables', {})
    placeholders_to_check = metadata.get('placeholders', [])

    # Load export result
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result JSON: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check 1: File Existence (10 pts)
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not saved during the task (stale file)."}

    score = 10
    feedback_parts = ["File saved successfully."]

    # Check 2: ODT Content Parsing (Variables & Placeholders)
    temp_odt = tempfile.NamedTemporaryFile(delete=False, suffix='.odt')
    try:
        copy_from_env(metadata['output_file'], temp_odt.name)
        
        # Open ODT (it's a zip) and parse content.xml
        with zipfile.ZipFile(temp_odt.name, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()

        # 2a. Check Variable Declarations (20 pts)
        # Look for <text:user-field-decl>
        # Path: office:body -> office:text -> text:user-field-decls -> text:user-field-decl
        decls = root.findall('.//text:user-field-decl', NS)
        defined_vars = {}
        for d in decls:
            name = d.get(f"{{{NS['text']}}}name")
            value = d.get(f"{{{NS['office']}}}string-value")
            if name:
                defined_vars[name] = value

        vars_defined_count = 0
        for expected_name, expected_val in expected_vars.items():
            if expected_name in defined_vars:
                actual_val = defined_vars[expected_name]
                # Allow slight tolerance in value string formatting if needed, but exact is best
                if actual_val == expected_val:
                    vars_defined_count += 1
                else:
                    feedback_parts.append(f"Variable '{expected_name}' defined but value mismatch (Expected: '{expected_val}', Got: '{actual_val}').")
            else:
                feedback_parts.append(f"Variable '{expected_name}' NOT defined.")
        
        if vars_defined_count == len(expected_vars):
            score += 20
            feedback_parts.append("All variables defined correctly.")
        else:
            partial = int(20 * (vars_defined_count / len(expected_vars)))
            score += partial

        # 2b. Check Variable Usages (Field Insertions) (50 pts split)
        # Look for <text:user-field-get text:name="...">
        gets = root.findall('.//text:user-field-get', NS)
        field_counts = {name: 0 for name in expected_vars.keys()}
        
        for g in gets:
            name = g.get(f"{{{NS['text']}}}name")
            if name in field_counts:
                field_counts[name] += 1
        
        # ClientName should appear at least 3 times (Preamble, Signatures, etc)
        if field_counts['ClientName'] >= 2:
            score += 20
            feedback_parts.append(f"ClientName field inserted {field_counts['ClientName']} times.")
        else:
            feedback_parts.append(f"ClientName field inserted only {field_counts['ClientName']} times (expected >= 2).")

        # UptimeTarget should appear ~2 times
        if field_counts['UptimeTarget'] >= 2:
            score += 10
            feedback_parts.append("UptimeTarget field inserted correctly.")
        else:
            feedback_parts.append("UptimeTarget field missing or insufficient.")

        # ContractDate should appear ~2 times
        if field_counts['ContractDate'] >= 2:
            score += 10
            feedback_parts.append("ContractDate field inserted correctly.")
        else:
            feedback_parts.append("ContractDate field missing or insufficient.")
            
        # ServiceCredit should appear 1 time
        if field_counts['ServiceCredit'] >= 1:
            score += 10
            feedback_parts.append("ServiceCredit field inserted correctly.")
        else:
            feedback_parts.append("ServiceCredit field missing.")

        # 2c. Check for Leftover Placeholders (20 pts)
        # We need to extract all text from paragraphs to check for "[CLIENT]", etc.
        # Recursively get text from elements
        def get_all_text(elem):
            text = elem.text or ""
            for child in elem:
                text += get_all_text(child)
            if elem.tail:
                text += elem.tail
            return text

        full_text = get_all_text(root)
        
        placeholders_found = 0
        for ph in placeholders_to_check:
            if ph in full_text:
                placeholders_found += 1
                # Only report the first few to avoid spam
                if placeholders_found <= 3:
                    feedback_parts.append(f"Found leftover placeholder: '{ph}'")
        
        if placeholders_found == 0:
            score += 20
            feedback_parts.append("No leftover placeholders found.")
        else:
            feedback_parts.append(f"Found {placeholders_found} leftover placeholder(s).")
            # Severe penalty for leaving placeholders, but partial credit possible
            score -= min(10, placeholders_found * 2)

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Error during verification: {str(e)}"}
    finally:
        if os.path.exists(temp_odt.name):
            os.unlink(temp_odt.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }