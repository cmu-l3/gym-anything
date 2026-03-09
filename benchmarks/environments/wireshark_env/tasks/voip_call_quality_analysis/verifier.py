#!/usr/bin/env python3
"""
Verifier for VoIP Call Quality Analysis task.
Checks:
1. Report file existence and creation time.
2. Accuracy of 8 distinct extracted fields against ground truth.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_string(s):
    """Normalize strings for loose comparison."""
    if not s:
        return ""
    return s.lower().strip().replace('"', '').replace("'", "")

def parse_report(content):
    """Parse key-value pairs from the report text."""
    data = {}
    for line in content.splitlines():
        if ':' in line:
            key, val = line.split(':', 1)
            data[normalize_string(key)] = val.strip()
    return data

def verify_voip_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    # Basic Checks
    if not result.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Report file voip_report.txt not found."}
    
    if not result.get('created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Report file was not modified during the task."}

    # Data Loading
    report_raw = result.get('report_content', '')
    report_data = parse_report(report_raw)
    gt = result.get('ground_truth', {})
    
    score = 0
    max_score = 100
    feedback = []

    # --- CRITERIA EVALUATION ---

    # 1. Total SIP Packets (10 pts)
    # Allow tolerance of +/- 5 packets
    try:
        sip_val = int(report_data.get('total_sip_packets', '0'))
        gt_sip = int(gt.get('sip_count', 0))
        if abs(sip_val - gt_sip) <= 5:
            score += 10
            feedback.append(f"SIP Count Correct ({sip_val})")
        else:
            feedback.append(f"SIP Count mismatch: {sip_val} vs {gt_sip}")
    except ValueError:
        feedback.append("Invalid SIP Packet count format")

    # 2. Total RTP Packets (10 pts)
    # Allow tolerance of +/- 10 packets
    try:
        rtp_val = int(report_data.get('total_rtp_packets', '0'))
        gt_rtp = int(gt.get('rtp_count', 0))
        if abs(rtp_val - gt_rtp) <= 10:
            score += 10
            feedback.append(f"RTP Count Correct ({rtp_val})")
        else:
            feedback.append(f"RTP Count mismatch: {rtp_val} vs {gt_rtp}")
    except ValueError:
        feedback.append("Invalid RTP Packet count format")

    # 3. SIP Methods (15 pts)
    # Compare sets of normalized strings
    agent_methods = set(normalize_string(m) for m in report_data.get('sip_methods', '').split(','))
    gt_methods = set(normalize_string(m) for m in str(gt.get('sip_methods', '')).split(','))
    # Remove empty strings
    agent_methods.discard('')
    gt_methods.discard('')
    
    if not gt_methods:
        # Fallback if GT failed
        score += 15 
    elif agent_methods == gt_methods:
        score += 15
        feedback.append("SIP Methods match")
    else:
        # Partial credit for overlap
        overlap = len(agent_methods.intersection(gt_methods))
        if overlap > 0:
            partial = int(15 * (overlap / len(gt_methods)))
            score += partial
            feedback.append(f"SIP Methods partial match ({overlap}/{len(gt_methods)})")
        else:
            feedback.append(f"SIP Methods mismatch. Expected: {gt_methods}")

    # 4. Caller (10 pts)
    agent_caller = normalize_string(report_data.get('caller', ''))
    gt_caller = normalize_string(gt.get('caller', ''))
    if gt_caller in agent_caller or agent_caller in gt_caller:
        score += 10
        feedback.append("Caller identified")
    else:
        feedback.append(f"Caller mismatch ({agent_caller} vs {gt_caller})")

    # 5. Callee (10 pts)
    agent_callee = normalize_string(report_data.get('callee', ''))
    gt_callee = normalize_string(gt.get('callee', ''))
    if gt_callee in agent_callee or agent_callee in gt_callee:
        score += 10
        feedback.append("Callee identified")
    else:
        feedback.append(f"Callee mismatch ({agent_callee} vs {gt_callee})")

    # 6. Codec (15 pts)
    agent_codec = normalize_string(report_data.get('codec', ''))
    gt_codec = normalize_string(gt.get('codec', ''))
    # Flexible matching for G711/PCMU variants
    valid_g711 = ['g711', 'pcmu', 'pcma', 'g.711', 'ulaw', 'alaw']
    is_g711_agent = any(x in agent_codec for x in valid_g711) or agent_codec in ['0', '8']
    is_g711_gt = any(x in gt_codec for x in valid_g711) or gt_codec in ['0', '8']
    
    if agent_codec == gt_codec:
        score += 15
        feedback.append("Codec match")
    elif is_g711_agent and is_g711_gt:
        score += 15
        feedback.append("Codec match (G.711 variant)")
    else:
        feedback.append(f"Codec mismatch ({agent_codec} vs {gt_codec})")

    # 7. RTP Streams (15 pts)
    try:
        agent_streams = int(report_data.get('number_of_rtp_streams', '0'))
        gt_streams = int(gt.get('rtp_streams', 0))
        if agent_streams == gt_streams:
            score += 15
            feedback.append("RTP Stream count correct")
        else:
            feedback.append(f"RTP Stream count wrong ({agent_streams} vs {gt_streams})")
    except ValueError:
        feedback.append("Invalid RTP stream count")

    # 8. SIP Response Codes (15 pts)
    agent_codes = set(report_data.get('sip_response_codes', '').split(','))
    gt_codes = set(str(gt.get('response_codes', '')).split(','))
    # clean
    agent_codes = {c.strip() for c in agent_codes if c.strip().isdigit()}
    gt_codes = {c.strip() for c in gt_codes if c.strip().isdigit()}

    if agent_codes == gt_codes and gt_codes:
        score += 15
        feedback.append("Response codes match")
    elif gt_codes:
        overlap = len(agent_codes.intersection(gt_codes))
        partial = int(15 * (overlap / len(gt_codes)))
        score += partial
        feedback.append(f"Response codes partial match ({overlap}/{len(gt_codes)})")
    
    # Final adjustments
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }