#!/usr/bin/env python3
"""
Verifier for Determine Optimal RPM task.

Verifies:
1. Project file existence and validity (XML parsing of .wpa).
2. Report file content (TSR, Cp, RPM values).
3. Mathematical correctness of RPM calculation based on reported TSR.
4. Aerodynamic plausibility of the results.
5. VLM check for polar extrapolation workflow.
"""

import json
import os
import re
import math
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from gym_anything.vlm import sample_trajectory_frames, query_vlm

def verify_determine_optimal_rpm(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_wind_speed = metadata.get('target_wind_speed', 12.0)
    target_radius = metadata.get('target_radius', 10.0)
    
    # Files to inspect
    project_path = metadata.get('expected_project_path', '/home/ga/Documents/projects/rpm_study.wpa')
    
    score = 0
    max_score = 100
    feedback = []
    
    # ---------------------------------------------------
    # 1. Load Result JSON
    # ---------------------------------------------------
    result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as tf:
        try:
            copy_from_env("/tmp/task_result.json", tf.name)
            tf.seek(0)
            result = json.load(tf)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}

    # ---------------------------------------------------
    # 2. Verify Project File (Geometry Check)
    # ---------------------------------------------------
    project_exists = result.get('project_exists', False)
    project_modified = result.get('project_modified_during_task', False)
    
    if project_exists and project_modified:
        score += 10
        feedback.append("Project file saved.")
        
        # Analyze Project XML content
        with tempfile.NamedTemporaryFile(suffix='.wpa') as pf:
            try:
                copy_from_env(project_path, pf.name)
                pf.seek(0)
                
                # QBlade .wpa is XML. Let's parse it to check blade radius.
                tree = ET.parse(pf.name)
                root = tree.getroot()
                
                # Check for Blade definition
                # Structure varies by version, but usually look for <Blade> or <BladeDesign>
                # and <Station> elements with Pos_z or Radius
                
                # Simplistic text check if XML parsing fails or structure is complex
                content = open(pf.name, 'r', encoding='utf-8', errors='ignore').read()
                
                # Check for NACA 4412
                if "4412" in content:
                    score += 5
                    feedback.append("NACA 4412 airfoil found in project.")
                
                # Check for Blade Radius ~ 10m
                # QBlade typically stores station positions. Look for max position.
                # Regex for <Pos_z>10...</Pos_z> or similar
                if re.search(r'<Pos_z>10\.|<Pos>10\.', content) or "10.000000" in content:
                    score += 15
                    feedback.append("Blade geometry appears to match 10m radius.")
                else:
                    feedback.append("Could not confirm 10m blade radius in project file.")
                    
                # Check for Simulation Results (BEM)
                if "<BEM_Simulation>" in content or "Tip Speed Ratio" in content:
                    score += 15
                    feedback.append("BEM simulation results found in project.")
                else:
                    feedback.append("No BEM simulation data found in project.")
                    
            except Exception as e:
                feedback.append(f"Failed to parse project file: {str(e)}")
    else:
        feedback.append("Project file missing or not modified.")

    # ---------------------------------------------------
    # 3. Verify Report & Calculation
    # ---------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', "")
    
    reported_tsr = None
    reported_rpm = None
    
    if report_exists and len(report_content) > 10:
        score += 10
        feedback.append("Report file created.")
        
        # Extract values using regex
        # Look for "Optimal TSR: 6.5" or similar
        tsr_match = re.search(r'Optimal TSR[:\s=]+([0-9.]+)', report_content, re.IGNORECASE)
        rpm_match = re.search(r'Optimal RPM[:\s=]+([0-9.]+)', report_content, re.IGNORECASE)
        
        if tsr_match:
            reported_tsr = float(tsr_match.group(1))
            
            # Aerodynamic Plausibility Check
            # For a tapered NACA 4412, max Cp usually around TSR 5-8
            if 4.0 <= reported_tsr <= 9.0:
                score += 15
                feedback.append(f"Reported Optimal TSR ({reported_tsr}) is plausible.")
            else:
                feedback.append(f"Reported Optimal TSR ({reported_tsr}) is outside expected range (4-9).")
        else:
            feedback.append("Could not parse 'Optimal TSR' from report.")

        if rpm_match:
            reported_rpm = float(rpm_match.group(1))
        else:
            feedback.append("Could not parse 'Calculated Optimal RPM' from report.")
            
        # Calculation Check
        if reported_tsr and reported_rpm:
            # Formula: RPM = (TSR * V) / R * (60 / 2pi)
            # V=12, R=10
            # RPM = (TSR * 1.2) * 9.54929...
            expected_rpm = (reported_tsr * target_wind_speed / target_radius) * (60 / (2 * math.pi))
            
            error_margin = abs(reported_rpm - expected_rpm) / expected_rpm
            
            if error_margin < 0.05: # 5% tolerance
                score += 15
                feedback.append(f"RPM calculation is correct (Reported: {reported_rpm:.2f}, Expected: {expected_rpm:.2f}).")
            else:
                feedback.append(f"RPM calculation incorrect. For TSR {reported_tsr}, expected ~{expected_rpm:.2f} RPM, got {reported_rpm}.")
    else:
        feedback.append("Report file missing or empty.")

    # ---------------------------------------------------
    # 4. VLM Workflow Verification (Polar Extrapolation)
    # ---------------------------------------------------
    # We verify if the agent entered the Polar Extrapolation module.
    # This is critical for 360-degree polar generation.
    
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying a QBlade workflow. Look at these screenshots of the user interface.
    
    I am looking for evidence of two specific steps:
    1. "Polar Extrapolation" or "360 Polar" module. This usually looks like a graph with curves extending from -180 to 180 degrees, or a dialog box titled "Extrapolate Polar" / "Viterna".
    2. "BEM Simulation" or "Rotor Simulation". This looks like a graph plotting Power Coefficient (Cp) vs Tip Speed Ratio (TSR).
    
    Return JSON:
    {
        "seen_extrapolation": boolean,
        "seen_bem_simulation": boolean,
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    
    seen_extrapolation = False
    seen_bem = False
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        seen_extrapolation = parsed.get('seen_extrapolation', False)
        seen_bem = parsed.get('seen_bem_simulation', False)
        feedback.append(f"VLM Analysis: {parsed.get('reasoning', '')}")
    
    if seen_extrapolation:
        score += 15
        feedback.append("VLM confirmed Polar Extrapolation step.")
    else:
        feedback.append("VLM did not observe 360° Polar Extrapolation (required for correct BEM).")
        
    if seen_bem:
        score += 10
        feedback.append("VLM confirmed BEM Simulation step.")

    # ---------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------
    passed = score >= 65 and project_exists and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }