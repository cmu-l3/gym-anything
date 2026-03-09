#!/usr/bin/env python3
"""
Verifier for NREL Phase VI Rotor Validation task.

Checks:
1. Report file exists and contains valid Power/Cp/TSR values.
2. Values are physically consistent and within plausible ranges for BEM.
3. Project file exists and appears valid.
4. VLM verifies workflow trajectory (Airfoil -> Polar -> Blade -> BEM).
"""

import json
import base64
import re
import os
import sys
import logging
import tempfile
from math import pi

# Try to import optional vlm utilities if available in env
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_content(base64_content):
    """Decodes and parses the report file content."""
    try:
        content = base64.b64decode(base64_content).decode('utf-8')
        data = {}
        
        # Regex patterns for flexible parsing
        # Look for "Key: Value" or "Key = Value" pattern
        power_match = re.search(r'(?:Power|P).*?[:=]\s*([\d\.]+)', content, re.IGNORECASE)
        cp_match = re.search(r'(?:Cp|Coeff).*?[:=]\s*([\d\.]+)', content, re.IGNORECASE)
        tsr_match = re.search(r'(?:TSR|Lambda).*?[:=]\s*([\d\.]+)', content, re.IGNORECASE)
        
        if power_match: data['Power'] = float(power_match.group(1))
        if cp_match: data['Cp'] = float(cp_match.group(1))
        if tsr_match: data['TSR'] = float(tsr_match.group(1))
        
        return data, content
    except Exception as e:
        logger.error(f"Failed to parse report: {e}")
        return {}, ""

def verify_nrel_phase6_validation(traj, env_info, task_info):
    """
    Main verification function.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Defaults
    TARGET_WIND = metadata.get('target_wind_speed', 7.0)
    ROTOR_RADIUS = metadata.get('rotor_radius', 5.029)
    AIR_DENSITY = metadata.get('air_density', 1.225)
    
    # Calculate available power for consistency check
    # P_avail = 0.5 * rho * pi * R^2 * V^3
    SWEPT_AREA = pi * (ROTOR_RADIUS ** 2)
    P_AVAIL = 0.5 * AIR_DENSITY * SWEPT_AREA * (TARGET_WIND ** 3)
    # P_AVAIL approx 16,698 W
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence & Timestamp (Anti-gaming)
    task_start = result.get('task_start_time', 0)
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    project_exists = result.get('project_exists', False)
    project_mtime = result.get('project_mtime', 0)
    
    # Check if files were created/modified DURING the task
    report_valid_time = report_exists and (report_mtime > task_start)
    project_valid_time = project_exists and (project_mtime > task_start)
    
    if report_valid_time:
        score += 10
        feedback_parts.append("Report file created.")
    else:
        feedback_parts.append("Report file missing or stale.")
        
    if project_valid_time:
        score += 10
        feedback_parts.append("Project file saved.")
    else:
        feedback_parts.append("Project file missing or stale.")

    # 3. Parse Report Data
    parsed_data, raw_content = parse_report_content(result.get('report_content_base64', ''))
    
    reported_power = parsed_data.get('Power')
    reported_cp = parsed_data.get('Cp')
    reported_tsr = parsed_data.get('TSR')
    
    # 4. Verify Physical Values
    values_plausible = False
    
    # TSR Check
    # Expected TSR = (72 * 2pi/60 * 5.029) / 7.0 approx 5.41
    if reported_tsr is not None:
        if 4.9 <= reported_tsr <= 6.0:
            score += 10
            feedback_parts.append(f"TSR {reported_tsr} is correct.")
        else:
            feedback_parts.append(f"TSR {reported_tsr} is out of expected range (~5.4).")
    
    # Cp Check
    # Typical Cp for S809 rotor is 0.35-0.45 peak, maybe lower if stall/pitch issues
    if reported_cp is not None:
        if 0.25 <= reported_cp <= 0.55:
            score += 10
            feedback_parts.append(f"Cp {reported_cp} is physically reasonable.")
        else:
            feedback_parts.append(f"Cp {reported_cp} is outside typical range (0.25-0.55).")
            
    # Power Check
    # P = Cp * P_avail = Cp * 16698
    # If Cp=0.35, P=5844. If Cp=0.45, P=7514.
    # Allow broad range for simulation differences
    if reported_power is not None:
        if 2000 <= reported_power <= 9000:
            score += 10
            feedback_parts.append(f"Power {reported_power}W is physically reasonable.")
            values_plausible = True
        else:
            feedback_parts.append(f"Power {reported_power}W is outside reasonable range (2000-9000W).")
            
    # Self-Consistency Check (Cp = P / P_avail)
    # This prevents entering random numbers
    if reported_power and reported_cp:
        calculated_cp = reported_power / P_AVAIL
        # Allow 20% error margin for rounding or slight density/radius differences in sim
        if abs(calculated_cp - reported_cp) / reported_cp < 0.20:
            score += 15
            feedback_parts.append("Power and Cp values are self-consistent.")
        else:
            feedback_parts.append(f"Inconsistent values: Power {reported_power}W implies Cp ~{calculated_cp:.2f}, but reported {reported_cp}.")

    # 5. Project File Content Check
    if result.get('is_valid_project_content', False) and result.get('project_size', 0) > 1000:
        score += 10
        feedback_parts.append("Project file appears valid.")

    # 6. VLM Verification (Trajectory)
    # Use trajectory frames to verify workflow steps
    if VLM_AVAILABLE:
        try:
            # Sample frames from trajectory
            frames = sample_trajectory_frames(traj, n=4)
            
            prompt = """
            Analyze these screenshots of QBlade software.
            I am looking for evidence of the following workflow steps:
            1. 'Airfoil Design' / 'XFoil' (graphs of Cl/Cd, polar curves)
            2. 'Blade Design' (3D view of a twisted blade, tables of chord/twist)
            3. 'Simulation' (BEM module, graphs showing Cp or Power curves)
            
            Return JSON:
            {
                "airfoil_polar_seen": boolean,
                "blade_design_seen": boolean,
                "simulation_seen": boolean,
                "confidence": "high/medium/low"
            }
            """
            
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                vlm_score = 0
                if parsed.get('airfoil_polar_seen'): vlm_score += 5
                if parsed.get('blade_design_seen'): vlm_score += 10
                if parsed.get('simulation_seen'): vlm_score += 10
                
                score += vlm_score
                feedback_parts.append(f"VLM verified workflow steps ({vlm_score} pts).")
            else:
                # Fallback if VLM fails: give partial credit if project file exists
                if project_valid_time: 
                    score += 10
                    feedback_parts.append("VLM unavailable, trusting project file.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if project_valid_time: score += 10 # Grace points

    # Final Pass Determination
    # Threshold: 60 points + Valid Report File + Plausible Values
    passed = (score >= 60) and report_valid_time and values_plausible
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }