#!/usr/bin/env python3
"""
Verifier for BitTorrent Traffic Forensics Task
"""

import json
import os
import tempfile
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bittorrent_forensics(traj, env_info, task_info):
    """
    Verifies the forensic report for BitTorrent traffic analysis.
    
    Scoring:
    - Report exists and created during task: 10 pts
    - Protocol identified as BitTorrent: 10 pts
    - Correct Info Hash: 30 pts
    - Correct Peer ID: 25 pts
    - Correct Client IP: 25 pts
    """
    
    # 1. Setup: Retrieve result from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # 2. Parse Data
    report_exists = result.get("report_exists", False)
    created_during_task = result.get("file_created_during_task", False)
    ground_truth = result.get("ground_truth", {})
    
    # Decode report content
    report_text = ""
    if result.get("report_content_base64"):
        try:
            report_text = base64.b64decode(result["report_content_base64"]).decode('utf-8', errors='ignore')
        except:
            report_text = ""

    # 3. Parse User Report (Key-Value)
    user_data = {}
    for line in report_text.split('\n'):
        if ':' in line:
            key, val = line.split(':', 1)
            user_data[key.strip().upper()] = val.strip()

    # 4. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: File Existence & Freshness (10 pts)
    if report_exists and created_during_task:
        score += 10
        feedback.append("Report file created successfully")
    elif report_exists:
        score += 5
        feedback.append("Report file exists but has old timestamp (stale?)")
    else:
        feedback.append("Report file not found")
        return {"passed": False, "score": 0, "feedback": "Report file missing"}

    # Criterion 2: Protocol Identification (10 pts)
    user_proto = user_data.get("PROTOCOL", "").upper()
    if "BITTORRENT" in user_proto or "P2P" in user_proto:
        score += 10
        feedback.append("Protocol identified correctly")
    else:
        feedback.append(f"Incorrect protocol: {user_proto}")

    # Criterion 3: Info Hash (30 pts)
    # Normalize: remove whitespace, lowercase
    gt_hash = ground_truth.get("info_hash", "").strip().lower()
    user_hash = user_data.get("INFO_HASH", "").strip().lower()
    
    # Handle possible hex prefixes like '0x' or spaces between bytes
    user_hash_clean = user_hash.replace("0x", "").replace(" ", "").replace(":", "")
    
    if user_hash_clean and user_hash_clean == gt_hash:
        score += 30
        feedback.append("Info Hash matches exactly")
    elif gt_hash in user_hash_clean: # Allow if they included extra data but hash is correct
        score += 30
        feedback.append("Info Hash found in output")
    else:
        feedback.append(f"Info Hash mismatch. Expected: {gt_hash}, Got: {user_hash}")

    # Criterion 4: Peer ID (25 pts)
    # Peer IDs can be tricky (ASCII vs Hex). The ground truth from tshark is usually the raw string or hex.
    gt_peer_id = ground_truth.get("peer_id", "").strip()
    user_peer_id = user_data.get("PEER_ID", "").strip()
    
    # We check if the significant part of the Peer ID matches
    # Common format is -UT1234-
    if user_peer_id and (user_peer_id == gt_peer_id or gt_peer_id in user_peer_id or user_peer_id in gt_peer_id):
        score += 25
        feedback.append("Peer ID matches")
    else:
        feedback.append(f"Peer ID mismatch. Expected: {gt_peer_id}, Got: {user_peer_id}")

    # Criterion 5: Client IP (25 pts)
    gt_ip = ground_truth.get("client_ip", "").strip()
    user_ip = user_data.get("CLIENT_IP", "").strip()
    
    if user_ip == gt_ip:
        score += 25
        feedback.append("Client IP matches")
    else:
        feedback.append(f"Client IP mismatch. Expected: {gt_ip}, Got: {user_ip}")

    # Final Pass Check
    # Need 70 points to pass (allows missing one tricky field like Peer ID if others are perfect)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }