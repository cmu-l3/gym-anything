#!/usr/bin/env python3
"""
Verifier for TLS Handshake Security Audit task.
"""

import json
import base64
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tls_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- 1. Load Result JSON ---
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

    # --- 2. Decode Content & Ground Truth ---
    try:
        if result.get('report_content_b64'):
            report_text = base64.b64decode(result['report_content_b64']).decode('utf-8', errors='ignore')
        else:
            report_text = ""
            
        gt = result.get('ground_truth', {})
        gt_snis = base64.b64decode(gt.get('snis_b64', '')).decode('utf-8').strip().split('\n')
        gt_snis = [s.strip() for s in gt_snis if s.strip()]
        
        gt_versions = base64.b64decode(gt.get('versions_b64', '')).decode('utf-8').strip().split('\n')
        gt_ciphers = base64.b64decode(gt.get('ciphers_b64', '')).decode('utf-8').strip().split('\n')
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Data decoding error: {e}"}

    score = 0
    feedback = []
    
    # --- Criterion 1: Report Exists & Anti-Gaming (10 pts) ---
    if result.get('report_exists') and result.get('report_mtime', 0) > result.get('task_start', 0):
        score += 10
        feedback.append("Report file created")
    else:
        feedback.append("Report file missing or not modified")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Helper to extract value by key regex
    def extract_val(pattern, text):
        match = re.search(pattern, text, re.IGNORECASE | re.MULTILINE)
        return match.group(1).strip() if match else None

    # --- Criterion 2: Client Hello Count (15 pts) ---
    agent_ch_str = extract_val(r"Total Client Hello messages:\s*(\d+)", report_text)
    gt_ch = gt.get('client_hellos', 0)
    
    if agent_ch_str and agent_ch_str.isdigit():
        agent_ch = int(agent_ch_str)
        if agent_ch == gt_ch:
            score += 15
            feedback.append(f"Client Hello count match ({agent_ch})")
        elif abs(agent_ch - gt_ch) <= 1:
            score += 10
            feedback.append(f"Client Hello count close ({agent_ch} vs {gt_ch})")
        else:
            feedback.append(f"Client Hello count mismatch ({agent_ch} vs {gt_ch})")
    else:
        feedback.append("Client Hello count missing/invalid")

    # --- Criterion 3: SNI Hostnames (20 pts) ---
    agent_snis_line = extract_val(r"Unique SNI hostnames:\s*(.*)", report_text)
    if agent_snis_line:
        # Normalize: remove whitespace, split by comma
        agent_snis = [s.strip() for s in agent_snis_line.split(',') if s.strip()]
        
        # Check intersections
        matches = 0
        for gt_sni in gt_snis:
            if any(gt_sni in s for s in agent_snis): # substring match allowed (e.g. www.google.com matches google.com)
                matches += 1
        
        if len(gt_snis) > 0:
            match_pct = matches / len(gt_snis)
            if match_pct >= 0.8:
                score += 20
                feedback.append("SNI hostnames correct")
            elif match_pct >= 0.5:
                score += 10
                feedback.append("SNI hostnames partially correct")
            else:
                feedback.append(f"SNI hostnames low match ({matches}/{len(gt_snis)})")
    else:
        feedback.append("SNI hostnames missing")

    # --- Criterion 4: Completed Handshakes (15 pts) ---
    agent_sh_str = extract_val(r"Total completed handshakes.*:\s*(\d+)", report_text)
    gt_sh = gt.get('server_hellos', 0)
    
    if agent_sh_str and agent_sh_str.isdigit():
        agent_sh = int(agent_sh_str)
        if agent_sh == gt_sh:
            score += 15
            feedback.append("Handshake count match")
        elif abs(agent_sh - gt_sh) <= 1:
            score += 10
            feedback.append("Handshake count close")
        else:
            feedback.append(f"Handshake count mismatch ({agent_sh} vs {gt_sh})")
    else:
        feedback.append("Handshake count missing")

    # --- Criterion 5: TLS Versions (15 pts) ---
    # Agent might write "TLS 1.2" or "1.2" or "0x0303"
    agent_vers_line = extract_val(r"TLS versions.*:\s*(.*)", report_text)
    if agent_vers_line:
        matches = 0
        normalized_agent = agent_vers_line.lower()
        
        # Check against ground truth hex codes
        for v in gt_versions:
            # Map hex to name
            name = "unknown"
            if "0301" in v: name = "1.0"
            if "0302" in v: name = "1.1"
            if "0303" in v: name = "1.2"
            if "0304" in v: name = "1.3"
            
            if name in normalized_agent or v in normalized_agent:
                matches += 1
        
        if len(gt_versions) > 0 and matches >= len(gt_versions):
            score += 15
            feedback.append("TLS versions identified")
        elif matches > 0:
            score += 7
            feedback.append("TLS versions partially identified")
        else:
            feedback.append("TLS versions mismatch")
    else:
        feedback.append("TLS versions missing")

    # --- Criterion 6: Cipher Suites (15 pts) ---
    agent_ciphers = extract_val(r"Server-selected cipher suites:\s*(.*)", report_text)
    if agent_ciphers:
        matches = 0
        for c in gt_ciphers:
            # Check for hex code (0x...) or just the code in the agent string
            if c.lower() in agent_ciphers.lower().replace("0x", ""):
                matches += 1
            # Or checking for standard names is harder without a lookup table, 
            # but usually partial hex match is enough for verification.
        
        if len(gt_ciphers) > 0 and matches >= len(gt_ciphers) * 0.7:
             score += 15
             feedback.append("Cipher suites correct")
        elif matches > 0:
             score += 7
             feedback.append("Cipher suites partially correct")
        else:
             feedback.append("Cipher suites mismatch")
    else:
        feedback.append("Cipher suites missing")

    # --- Criterion 7: Weak TLS (5 pts) ---
    agent_weak = extract_val(r"Weak TLS versions detected:\s*(Yes|No)", report_text)
    gt_weak = gt.get('weak_tls', 'No')
    if agent_weak and agent_weak.lower() == gt_weak.lower():
        score += 5
        feedback.append(f"Weak TLS assessment correct ({gt_weak})")
    else:
        feedback.append("Weak TLS assessment incorrect/missing")

    # --- Criterion 8: VLM Trajectory (5 pts) ---
    # Simple check if app was running as proxy
    if result.get('app_running'):
        score += 5
        feedback.append("Wireshark was running")
        
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }