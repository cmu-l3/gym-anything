#!/usr/bin/env python3
"""
Verifier for hl7_canonical_xml_transformer task.
Verifies channel configuration and functional output logic (XML structure + Gender normalization).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET

def verify_hl7_canonical_xml_transformer(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Channel Configuration (30 points)
    if result.get("channel_found"):
        score += 10
        feedback.append("Channel 'Canonical_XML_Transformer' created.")
        
        if result.get("channel_status") == "STARTED":
            score += 10
            feedback.append("Channel is deployed and running.")
        else:
            feedback.append(f"Channel status is {result.get('channel_status')} (expected STARTED).")

        if str(result.get("listen_port")) == "6661":
            score += 5
            feedback.append("Listening on correct port 6661.")
        
        # Check datatypes if available
        src = result.get("source_datatype", "").upper()
        dst = result.get("dest_datatype", "").upper()
        if "HL7" in src and "XML" in dst:
            score += 5
            feedback.append("Correct Source(HL7)/Dest(XML) datatypes detected.")
    else:
        feedback.append("Channel 'Canonical_XML_Transformer' not found.")

    # 2. Output Directory Usage (10 points)
    if result.get("agent_files_created_count", 0) > 0 or result.get("verify_test_run"):
        score += 10
        feedback.append("Output files created in /home/ga/xml_out/.")
    else:
        feedback.append("No output files found in /home/ga/xml_out/.")

    # 3. Functional Verification & Logic (60 points)
    # This relies on the export script having successfully sent messages and captured output
    
    male_xml_content = result.get("test_result_male_content", "").strip()
    female_xml_content = result.get("test_result_female_content", "").strip()
    
    if not male_xml_content and not female_xml_content:
        feedback.append("Functional test failed: No XML output generated from test messages.")
    else:
        # 3a. Valid XML Structure (20 points)
        try:
            root_m = ET.fromstring(male_xml_content)
            score += 20
            feedback.append("Generated output is valid XML.")
            
            # Check Root Element
            if "PatientEvent" in root_m.tag:
                score += 5
                feedback.append("Root element is <PatientEvent>.")
            else:
                feedback.append(f"Incorrect root element: {root_m.tag}")
                
            # 3b. Data Mapping (MRN, Name) (20 points)
            mrn = root_m.find("MRN").text if root_m.find("MRN") is not None else ""
            family = root_m.find(".//Family").text if root_m.find(".//Family") is not None else ""
            
            if "TEST_M_999" in mrn:
                score += 10
                feedback.append("MRN mapped correctly.")
            if "TEST" in family:
                score += 10
                feedback.append("Patient Name mapped correctly.")
                
            # 3c. Gender Normalization Logic (15 points)
            # Check Male
            gender_m = root_m.find("Gender").text if root_m.find("Gender") is not None else ""
            if gender_m == "Male":
                score += 7.5
                feedback.append("Gender normalization (M -> Male) correct.")
            else:
                feedback.append(f"Gender normalization failed for Male. Got: '{gender_m}'")
                
            # Check Female
            if female_xml_content:
                try:
                    root_f = ET.fromstring(female_xml_content)
                    gender_f = root_f.find("Gender").text if root_f.find("Gender") is not None else ""
                    if gender_f == "Female":
                        score += 7.5
                        feedback.append("Gender normalization (F -> Female) correct.")
                    else:
                        feedback.append(f"Gender normalization failed for Female. Got: '{gender_f}'")
                except:
                    pass

        except ET.ParseError:
            feedback.append("Generated output is NOT valid XML.")
            feedback.append(f"Content preview: {male_xml_content[:100]}...")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }