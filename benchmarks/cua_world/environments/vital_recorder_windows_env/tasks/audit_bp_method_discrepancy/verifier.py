#!/usr/bin/env python3
"""
Verifier for audit_bp_method_discrepancy task.

Checks:
1. Report file existence and creation time.
2. Report structure (3 measurements).
3. Data consistency: Gradient = ART - NIBP.
4. Physiological plausibility (SBP 60-220 mmHg).
5. Timestamp validity (approx 15m, 45m, 75m).
"""

import json
import re
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_time_str(t_str):
    """Parse HH:MM:SS to seconds."""
    try:
        parts = list(map(int, t_str.strip().split(':')))
        if len(parts) == 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        elif len(parts) == 2:
            return parts[0] * 60 + parts[1]
    except:
        pass
    return None

def verify_audit_bp_method_discrepancy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON from the Windows environment
    # Note: Windows path inside container might need handling, but copy_from_env usually handles the container path provided in export_result
    # The export script saved to C:\tmp\task_result.json, which maps to /tmp/task_result.json in some dockur/windows implementations or similar path.
    # We will try the standard linux-style path that the base environment usually maps 'C:\tmp' to, or standard location.
    # Assuming the environment handles path mapping for '/tmp/task_result.json' -> 'C:\tmp\task_result.json'
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Try copying from standard temp location
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check File Existence & Creation (20 pts)
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    score += 10
    if result.get('file_created_during_task'):
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("File timestamp indicates it was not created during this session.")
        
    content = result.get('report_content', '')
    if not content:
        return {"passed": False, "score": score, "feedback": "Report file is empty."}

    # 2. Parse Content
    # Expected format:
    # Measurement X ...
    #   Time: ...
    #   NIBP SBP: ...
    #   ART SBP: ...
    #   Gradient: ...
    
    measurements = []
    # Regex to find blocks
    blocks = re.split(r'Measurement \d+', content)
    
    # Skip header
    for block in blocks[1:]:
        m_data = {}
        
        # Extract Time
        t_match = re.search(r'Time:\s*([\d:]+)', block)
        if t_match: m_data['time'] = t_match.group(1)
        
        # Extract Values
        nibp_match = re.search(r'NIBP\s*SBP:\s*([\d\.]+)', block, re.IGNORECASE)
        if nibp_match: m_data['nibp'] = float(nibp_match.group(1))
        
        art_match = re.search(r'ART\s*SBP:\s*([\d\.]+)', block, re.IGNORECASE)
        if art_match: m_data['art'] = float(art_match.group(1))
        
        grad_match = re.search(r'Gradient:\s*([\-\d\.]+)', block, re.IGNORECASE)
        if grad_match: m_data['gradient'] = float(grad_match.group(1))
        
        if 'time' in m_data and 'nibp' in m_data and 'art' in m_data:
            measurements.append(m_data)

    if len(measurements) < 3:
        feedback.append(f"Found {len(measurements)}/3 required measurements.")
        # Scale score for partial
        score += len(measurements) * 10
    else:
        score += 30
        feedback.append("Found all 3 measurement blocks.")

    # 3. Analyze Data (50 pts distributed)
    valid_points = 0
    
    # Target windows in seconds
    targets = [
        (15*60, "15m"), 
        (45*60, "45m"), 
        (75*60, "1h15m")
    ]
    
    for i, m in enumerate(measurements[:3]):
        p_score = 0
        p_feedback = []
        
        # Check A: Math Consistency (5 pts)
        # Gradient = ART - NIBP
        calc_grad = m['art'] - m['nibp']
        # Allow small float error
        if abs(calc_grad - m.get('gradient', -999)) < 0.5:
            p_score += 5
        else:
            p_feedback.append(f"Math error (Exp {calc_grad:.1f}, Got {m.get('gradient')})")

        # Check B: Physiological Plausibility (5 pts)
        if 60 <= m['art'] <= 240 and 60 <= m['nibp'] <= 240:
            p_score += 5
        else:
            p_feedback.append("Values out of physiological range")

        # Check C: Timeline Constraints (roughly) (6-7 pts)
        t_sec = parse_time_str(m['time'])
        if t_sec:
            target_sec = targets[i][0]
            # Expecting it to be AFTER the target time, but reasonably close (within 15 mins)
            # Since NIBP is intermittent (e.g. every 5 mins), it should be target < t < target + 900
            if t_sec >= target_sec and t_sec < target_sec + 1800:
                p_score += 6
            else:
                p_feedback.append(f"Time {m['time']} outside expected window >{targets[i][1]}")
        else:
            p_feedback.append("Invalid time format")
            
        score += p_score
        if not p_feedback:
            valid_points += 1
            
    if valid_points == 3:
        feedback.append("All data points valid and consistent.")
    
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }