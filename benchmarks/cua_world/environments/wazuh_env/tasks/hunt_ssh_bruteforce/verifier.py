#!/usr/bin/env python3
"""
Verifier for hunt_ssh_bruteforce task.
Validates the JSON report against ground truth data injected during setup.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hunt_ssh_bruteforce(traj, env_info, task_info):
    """
    Verify the threat hunt report.
    
    Criteria:
    1. Report file exists and is valid JSON.
    2. Report created during task session.
    3. Correctly identifies 3 attacker IPs.
    4. Correctly identifies counts (+/- tolerance).
    5. Correctly identifies compromised hosts.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', {})
    
    # 1. Load Task Result Metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            meta_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task metadata: {e}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)
            
    if not meta_result.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file ~/threat_hunt_report.json not found"}
        
    if not meta_result.get('report_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Report file timestamp indicates it was not created during this task session"}

    # 2. Load the Actual Report Content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/exported_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError:
        return {"passed": False, "score": 5, "feedback": "Report file exists but is not valid JSON"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read report content: {e}"}
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # 3. Score the Report Content
    score = 0
    feedback = []
    
    # Base points for valid file
    score += 5
    
    # Check Counts (Tolerance +/- 15 for total failures to account for noise generation variations)
    # The generator uses random timestamps and counts, so we check against ranges based on generator logic
    # Generator: 87+43+15 = 145 attacker failures + 20 noise = 165 total expected roughly
    # Wait, generator logic:
    # Attacker 1: 87
    # Attacker 2: 43
    # Attacker 3: 15
    # Noise: 20
    # Total Failures: 165
    # Attacker 1 Success: 1
    # Attacker 3 Success: 1
    # Noise Success: 20
    # Total Success: 22
    
    # Let's use the ground_truth from metadata but adjust for the noise added in setup_task.sh
    # Ideally setup_task.sh should write the exact truth to a hidden file, but for now we use loose tolerances
    
    reported_fails = report.get('total_ssh_failure_alerts', 0)
    if 150 <= reported_fails <= 180:
        score += 10
        feedback.append("Total failure count correct")
    else:
        feedback.append(f"Total failure count {reported_fails} out of expected range (150-180)")

    reported_success = report.get('total_ssh_success_alerts', 0)
    if 18 <= reported_success <= 26:
        score += 10
        feedback.append("Total success count correct")
    else:
        feedback.append(f"Total success count {reported_success} out of expected range (18-26)")

    # Check Attackers
    reported_attackers = report.get('top_attacker_ips', [])
    gt_attackers = ground_truth.get('attackers', [])
    
    attacker_ips_found = 0
    for gt_at in gt_attackers:
        gt_ip = gt_at['ip']
        found = False
        for rep_at in reported_attackers:
            if rep_at.get('ip') == gt_ip:
                found = True
                attacker_ips_found += 1
                # Check individual count
                diff = abs(rep_at.get('failed_attempts', 0) - gt_at['failures'])
                if diff <= 5:
                    score += 3  # Good count per IP
                
                # Check success flag
                should_have_success = len(gt_at['compromised']) > 0
                if rep_at.get('had_successful_login') == should_have_success:
                    score += 3
                break
        if found:
            score += 6 # Found the IP
            
    feedback.append(f"Identified {attacker_ips_found}/3 attacker IPs")
    
    # Check Compromised Hosts
    reported_compromised = report.get('compromised_hosts', [])
    
    # We expect web-server-01 (by 185.220.101.42) and db-server-01 (by 103.253.41.98)
    expected_compromises = {
        "web-server-01": "185.220.101.42",
        "db-server-01": "103.253.41.98"
    }
    
    compromise_score = 0
    for rep_comp in reported_compromised:
        hostname = rep_comp.get('hostname')
        attacker = rep_comp.get('attacker_ip')
        
        if hostname in expected_compromises:
            if expected_compromises[hostname] == attacker:
                compromise_score += 10
                feedback.append(f"Correctly identified compromise: {hostname} by {attacker}")
            else:
                compromise_score += 5
                feedback.append(f"Identified compromised host {hostname} but wrong attacker {attacker}")
    
    score += compromise_score
    
    # Severity check
    if report.get('severity', '').lower() == 'critical':
        score += 5
        feedback.append("Severity assessment correct")
        
    # Evidence check
    if meta_result.get('history_evidence_found', False):
        score += 5
        feedback.append("Process evidence found (CLI usage)")
        
    passed = score >= 60 and attacker_ips_found >= 2 and compromise_score >= 10
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }