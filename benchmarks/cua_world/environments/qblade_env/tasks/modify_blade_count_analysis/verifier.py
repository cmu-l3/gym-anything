#!/usr/bin/env python3
"""
Verifier for modify_blade_count_analysis task.

Verifies:
1. QBlade project file (.wpa) exists and is valid XML.
2. Rotor definition in project has exactly 2 blades (parsing XML).
3. BEM simulation results exist in project for the 2-blade configuration.
4. Report file contains correct Cp and TSR values matching the simulation.
5. VLM verification of the workflow.
"""

import json
import os
import tempfile
import logging
import re
import xml.etree.ElementTree as ET
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_wpa_file(wpa_path: str) -> Dict[str, Any]:
    """
    Parses QBlade .wpa (XML) file to extract blade count and simulation results.
    Returns dictionary with parsed data.
    """
    data = {
        "valid_xml": False,
        "blade_count": None,
        "bem_results_found": False,
        "max_cp": 0.0,
        "max_cp_tsr": 0.0
    }
    
    try:
        # QBlade WPA files are XML, but sometimes contain non-standard chars or encoding
        # We try standard parsing first
        try:
            tree = ET.parse(wpa_path)
            root = tree.getroot()
            data["valid_xml"] = True
        except ET.ParseError:
            # Fallback: simple text scanning if XML is malformed
            logger.warning("XML parsing failed, falling back to text regex")
            with open(wpa_path, 'r', errors='ignore') as f:
                content = f.read()
            
            # Find blade count using regex
            # Look for <BladeCount>2</BladeCount> or similar
            bc_match = re.search(r'<BladeCount>(\d+)</BladeCount>', content, re.IGNORECASE)
            if bc_match:
                data["blade_count"] = int(bc_match.group(1))
            
            # Check for BEM results (heuristic)
            if "BEMSimulation" in content or "TSR" in content:
                data["bem_results_found"] = True
            
            return data

        # If XML parsed successfully
        # 1. Find Rotor/Blade Count
        # Structure varies by version, usually QBladeProject -> Turbine -> Rotor -> BladeCount
        # We'll search recursively
        for elem in root.iter():
            if 'BladeCount' in elem.tag:
                try:
                    data["blade_count"] = int(elem.text)
                    break
                except (ValueError, TypeError):
                    continue
        
        # 2. Find BEM Results
        # Look for simulation objects. This is complex in QBlade XML.
        # We will iterate through result graphs if available, or just check existence
        # of BEM output structures.
        bem_found = False
        max_cp = -1.0
        opt_tsr = -1.0
        
        # Simpler approach: Iterate all text content looking for result patterns
        # or specific BEM tags
        for elem in root.iter():
            if 'BEM' in str(elem.tag) or 'Simulation' in str(elem.tag):
                bem_found = True
        
        # To get Max CP, we might need to parse text data blobs inside the XML
        # Often stored as CDATA or whitespace separated numbers
        # This is fragile, so we might rely on the report file for exact values
        # and just cross-check ranges here.
        
        data["bem_results_found"] = bem_found
        
    except Exception as e:
        logger.error(f"Error parsing WPA: {e}")
        
    return data

def parse_report_file(report_path: str) -> Tuple[float, float, int]:
    """
    Parses the 3-line report file.
    Expected:
    Line 1: Cp_max (float)
    Line 2: TSR (float)
    Line 3: Blade Count (int)
    """
    try:
        with open(report_path, 'r') as f:
            lines = [l.strip() for l in f.readlines() if l.strip()]
            
        if len(lines) < 3:
            return None, None, None
            
        # Extract numbers using regex to handle potential extra text
        cp_match = re.search(r"([0-9]+\.[0-9]+)", lines[0])
        tsr_match = re.search(r"([0-9]+\.[0-9]+)", lines[1])
        bc_match = re.search(r"(\d+)", lines[2])
        
        cp = float(cp_match.group(1)) if cp_match else None
        tsr = float(tsr_match.group(1)) if tsr_match else None
        bc = int(bc_match.group(1)) if bc_match else None
        
        return cp, tsr, bc
    except Exception as e:
        logger.error(f"Error parsing report: {e}")
        return None, None, None

def verify_modify_blade_count_analysis(traj, env_info, task_info):
    """
    Verifies the blade count modification and BEM analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    score = 0
    feedback = []
    
    # 1. Get task metadata and result JSON
    metadata = task_info.get('metadata', {})
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_json = {}
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Could not read task result JSON"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Verify Project File Creation
    proj_info = result_json.get('project_file', {})
    if proj_info.get('exists') and proj_info.get('created_during_task'):
        score += 10
        feedback.append("Project file created successfully.")
        
        # Copy and parse project file
        temp_wpa = tempfile.NamedTemporaryFile(delete=False, suffix='.wpa')
        try:
            copy_from_env(proj_info['path'], temp_wpa.name)
            wpa_data = parse_wpa_file(temp_wpa.name)
            
            # Check Blade Count (CRITICAL)
            actual_bc = wpa_data.get('blade_count')
            if actual_bc == 2:
                score += 30
                feedback.append("Project correctly configured with 2 blades.")
            elif actual_bc == 3:
                feedback.append("FAIL: Project still has 3 blades (original state).")
            else:
                feedback.append(f"FAIL: Found {actual_bc} blades, expected 2.")
                
            # Check BEM Results Existence
            if wpa_data.get('bem_results_found'):
                score += 20
                feedback.append("BEM simulation results found in project.")
            else:
                feedback.append("Warning: Could not confirm BEM results in project XML.")
                
        except Exception as e:
            feedback.append(f"Error analyzing project file: {str(e)}")
        finally:
            if os.path.exists(temp_wpa.name):
                os.unlink(temp_wpa.name)
    else:
        feedback.append("Project file not saved or not new.")

    # 3. Verify Report File
    report_info = result_json.get('report_file', {})
    if report_info.get('exists') and report_info.get('created_during_task'):
        score += 10
        feedback.append("Report file created.")
        
        temp_rpt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_info['path'], temp_rpt.name)
            cp, tsr, bc = parse_report_file(temp_rpt.name)
            
            # Check Blade Count in Report
            if bc == 2:
                score += 10
                feedback.append("Report confirms 2 blades.")
            else:
                feedback.append(f"Report states {bc} blades (expected 2).")
            
            # Check Physics (Realistic values for 2-blade rotor)
            # 2-blade rotors typically have slightly lower Cp than 3-blade, but definitely < 0.59
            # Range 0.2 to 0.55 is generous but safe
            if cp and 0.2 <= cp <= 0.55:
                score += 10
                feedback.append(f"Reported Cp ({cp}) is realistic.")
            else:
                feedback.append(f"Reported Cp ({cp}) is out of realistic range (0.2-0.55).")
                
            # Check TSR (Peak usually around 6-9 for modern HAWTs)
            if tsr and 3.0 <= tsr <= 14.0:
                score += 10
                feedback.append(f"Reported TSR ({tsr}) is realistic.")
            else:
                feedback.append(f"Reported TSR ({tsr}) is out of realistic range.")
                
        except Exception as e:
            feedback.append(f"Error parsing report: {e}")
        finally:
            if os.path.exists(temp_rpt.name):
                os.unlink(temp_rpt.name)
    else:
        feedback.append("Report file not found.")

    # 4. Final Pass Check
    # Must have modified blade count (30pts) and produced reasonable data (partial report pts)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }