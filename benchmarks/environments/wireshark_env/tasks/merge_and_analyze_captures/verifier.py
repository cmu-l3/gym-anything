#!/usr/bin/env python3
"""
Verifier for merge_and_analyze_captures task.

Verifies:
1. Merged PCAP file exists, is valid, and created during task.
2. Merged PCAP contains all packets from sources (count check).
3. Merged PCAP contains expected protocols (DNS, HTTP).
4. Merged PCAP is chronologically sorted.
5. Text report exists and contains correct data extracted from file.
"""

import json
import tempfile
import os
import logging
import base64

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_merge_and_analyze_captures(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
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
    
    # Extract data sections
    gt = result.get('ground_truth', {})
    pcap = result.get('pcap_analysis', {})
    report = result.get('report_analysis', {})

    expected_total = gt.get('expected_total', 0)
    
    # --- Criterion 1: Merged File Creation (30 pts) ---
    if pcap.get('exists') and pcap.get('valid'):
        if pcap.get('created_during_task'):
            score += 30
            feedback_parts.append("Merged PCAP created successfully")
        else:
            score += 10
            feedback_parts.append("Merged PCAP exists but timestamp is old")
    else:
        feedback_parts.append("Merged PCAP file not found or invalid")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: Packet Consistency (20 pts) ---
    actual_count = pcap.get('packet_count', 0)
    if actual_count == expected_total and expected_total > 0:
        score += 20
        feedback_parts.append(f"Correct packet count ({actual_count})")
    else:
        feedback_parts.append(f"Incorrect packet count: {actual_count} (Expected: {expected_total})")

    # --- Criterion 3: Protocols & Sorting (20 pts) ---
    protocols = pcap.get('protocols_found', "")
    if "DNS" in protocols and "HTTP" in protocols:
        score += 10
        feedback_parts.append("Both DNS and HTTP protocols present")
    else:
        feedback_parts.append("Missing required protocols in merged file")

    if pcap.get('is_chronological'):
        score += 10
        feedback_parts.append("File is strictly chronological")
    else:
        feedback_parts.append("File is NOT strictly chronological")

    # --- Criterion 4: Report Accuracy (30 pts) ---
    if report.get('exists'):
        score += 5 # Base points for file existence
        
        # Check reported count
        try:
            reported_count = int(report.get('extracted_count', -1))
            if reported_count == expected_total:
                score += 10
                feedback_parts.append("Report: Packet count correct")
            else:
                feedback_parts.append(f"Report: Packet count mismatch ({reported_count} vs {expected_total})")
        except:
            feedback_parts.append("Report: Could not parse packet count")

        # Check reported protocols
        reported_protos = report.get('extracted_protocols', "").upper()
        if "DNS" in reported_protos and "HTTP" in reported_protos:
            score += 10
            feedback_parts.append("Report: Protocols listed correctly")
        else:
            feedback_parts.append("Report: Protocols missing or incorrect")
            
        # Check for timestamps in report content
        try:
            content = base64.b64decode(report.get('content_base64', '')).decode('utf-8', errors='ignore')
            if "First Packet" in content and "Last Packet" in content:
                # Basic check that some value follows
                import re
                if re.search(r"First Packet: .+", content) and re.search(r"Last Packet: .+", content):
                    score += 5
                    feedback_parts.append("Report: Timestamps present")
        except Exception:
            pass
            
    else:
        feedback_parts.append("Report file not found")

    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }