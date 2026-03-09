#!/usr/bin/env python3
"""
Verifier for VAWT Torque Ripple Analysis task.
"""

import json
import os
import tempfile
import base64
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_content(base64_content):
    """Decodes and parses the user report."""
    if not base64_content:
        return {}
    
    try:
        text = base64.b64decode(base64_content).decode('utf-8', errors='ignore')
        logger.info(f"Report content:\n{text}")
        
        # Extract values using regex to handle various formats like "Q_max: 123", "Q_max=123", etc.
        data = {}
        
        # Regex patterns for the required fields
        patterns = {
            'Q_max': r'Q_?max\s*[:=]\s*([\d\.]+)',
            'Q_min': r'Q_?min\s*[:=]\s*([\d\.]+)',
            'Q_avg': r'Q_?avg\s*[:=]\s*([\d\.]+)',
            'Ripple_Factor': r'Ripple_?Factor\s*[:=]\s*([\d\.]+)'
        }
        
        for key, pattern in patterns.items():
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                try:
                    data[key] = float(match.group(1))
                except ValueError:
                    pass
                    
        return data
    except Exception as e:
        logger.error(f"Error parsing report: {e}")
        return {}

def verify_vawt_torque_ripple(traj, env_info, task_info):
    """
    Verifies the VAWT torque ripple analysis task.
    
    Criteria:
    1. Project file exists and is valid (15 pts)
    2. Report file exists (15 pts)
    3. Simulation data export found (10 pts)
    4. Q_avg is physically plausible for the specified turbine (20 pts)
    5. Ripple Factor calculation is consistent with reported Q values (20 pts)
    6. Ripple Factor is physically plausible (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    physics_ranges = metadata.get('physics_ranges', {})
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # 1. Project File Verification (15 pts)
    if result.get('project_exists') and result.get('project_created_during_task'):
        if result.get('project_size', 0) > 1000: # Ensure it's not empty
            score += 15
            feedback_parts.append("Project file saved successfully")
        else:
            score += 5
            feedback_parts.append("Project file exists but is very small")
    else:
        feedback_parts.append("Project file missing or not created during task")
        
    # 2. Report File Existence (15 pts)
    report_data = {}
    if result.get('report_exists') and result.get('report_created_during_task'):
        score += 15
        feedback_parts.append("Report file created")
        report_data = parse_report_content(result.get('report_content_base64'))
    else:
        feedback_parts.append("Report file missing")
        
    # 3. Data Export Verification (10 pts)
    if result.get('data_export_found'):
        score += 10
        feedback_parts.append("Simulation data export detected")
    else:
        feedback_parts.append("No exported simulation data file found")
        
    # 4. Physics Check: Q_avg (20 pts)
    # Target: ~200 Nm for this configuration. Allow 100-300 range.
    q_avg = report_data.get('Q_avg')
    q_avg_valid = False
    
    if q_avg is not None:
        q_min_expected = physics_ranges.get('q_avg_min', 100.0)
        q_max_expected = physics_ranges.get('q_avg_max', 300.0)
        
        if q_min_expected <= q_avg <= q_max_expected:
            score += 20
            q_avg_valid = True
            feedback_parts.append(f"Q_avg ({q_avg} Nm) is within expected physics range")
        else:
            feedback_parts.append(f"Q_avg ({q_avg} Nm) is outside expected physics range ({q_min_expected}-{q_max_expected})")
    else:
        feedback_parts.append("Q_avg not found in report")

    # 5. Calculation Consistency Check (20 pts)
    # Check if user's Ripple Factor matches their own Q values: TRF = (Qmax - Qmin) / Qavg
    q_max = report_data.get('Q_max')
    q_min = report_data.get('Q_min')
    user_trf = report_data.get('Ripple_Factor')
    
    calc_consistent = False
    if q_max is not None and q_min is not None and q_avg is not None and user_trf is not None and q_avg != 0:
        calculated_trf = (q_max - q_min) / q_avg
        # Allow small tolerance for rounding
        if abs(calculated_trf - user_trf) < 0.05:
            score += 20
            calc_consistent = True
            feedback_parts.append("Ripple Factor calculation is consistent with reported torque values")
        else:
            feedback_parts.append(f"Ripple Factor calculation error: Reported {user_trf}, Calculated {calculated_trf:.3f} from Q values")
    else:
        feedback_parts.append("Insufficient data in report to verify calculation consistency")
        
    # 6. Physics Check: Ripple Factor (20 pts)
    # TRF should be positive and reasonable (e.g., 0.05 to 1.0 for a 3-bladed VAWT)
    if user_trf is not None:
        trf_min = physics_ranges.get('trf_min', 0.05)
        trf_max = physics_ranges.get('trf_max', 1.0)
        
        if trf_min <= user_trf <= trf_max:
            score += 20
            feedback_parts.append(f"Ripple Factor ({user_trf}) is physically plausible")
        else:
            feedback_parts.append(f"Ripple Factor ({user_trf}) seems physically unrealistic")

    # Pass logic
    # Must have project, report, and reasonable physics
    passed = (score >= 70) and result.get('project_exists') and result.get('report_exists') and q_avg_valid
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }