#!/usr/bin/env python3
"""Verifier for Network Baseline Audit task.

Scoring (100 points):
- Criterion 1: Report file exists and is substantial (10 points)
- Criterion 2: Protocols identified (20 points)
- Criterion 3: IP endpoints listed (20 points)
- Criterion 4: Destination ports documented (15 points)
- Criterion 5: TCP retransmission analysis (15 points)
- Criterion 6: Packet count and byte volume (20 points)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_network_baseline_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []

        if not result.get('file_exists'):
            return {
                "passed": False,
                "score": 0,
                "feedback": "Report file not created. Agent must save findings to baseline_audit_report.txt"
            }

        # Criterion 1: Report exists and is substantial
        content_length = result.get('content_length', 0)
        if content_length >= 200:
            score += 10
            feedback_parts.append(f"Report exists ({content_length} chars)")
        elif content_length > 0:
            score += 5
            feedback_parts.append(f"Report exists but short ({content_length} chars)")
        else:
            feedback_parts.append("Report is empty")

        # Criterion 2: Protocols identified
        protos_found = result.get('protocols_found', 0)
        protos_total = result.get('protocols_total', 1)
        if protos_total > 0:
            proto_ratio = protos_found / protos_total
            if proto_ratio >= 0.6:
                score += 20
                feedback_parts.append(f"Protocols: {protos_found}/{protos_total} identified")
            elif protos_found >= 3:
                score += 12
                feedback_parts.append(f"Protocols: {protos_found}/{protos_total} identified (partial)")
            elif protos_found > 0:
                score += 6
                feedback_parts.append(f"Protocols: only {protos_found}/{protos_total} identified")
            else:
                feedback_parts.append("No protocols identified in report")

        # Criterion 3: IP endpoints
        ips_found = result.get('ips_found', 0)
        ips_total = result.get('ips_total', 1)
        if ips_total > 0:
            ip_ratio = ips_found / ips_total
            if ip_ratio >= 0.5:
                score += 20
                feedback_parts.append(f"IPs: {ips_found}/{ips_total} listed")
            elif ips_found >= 2:
                score += 12
                feedback_parts.append(f"IPs: {ips_found}/{ips_total} listed (partial)")
            elif ips_found > 0:
                score += 6
                feedback_parts.append(f"IPs: only {ips_found}/{ips_total} listed")
            else:
                feedback_parts.append("No IP addresses found in report")

        # Criterion 4: Destination ports
        ports_found = result.get('ports_found', 0)
        ports_total = result.get('ports_total', 1)
        if ports_total > 0:
            port_ratio = ports_found / ports_total
            if port_ratio >= 0.5:
                score += 15
                feedback_parts.append(f"Ports: {ports_found}/{ports_total} documented")
            elif ports_found >= 2:
                score += 8
                feedback_parts.append(f"Ports: {ports_found}/{ports_total} documented (partial)")
            elif ports_found > 0:
                score += 4
                feedback_parts.append(f"Ports: only {ports_found}/{ports_total} documented")
            else:
                feedback_parts.append("No destination ports found in report")

        # Criterion 5: Retransmission analysis
        if result.get('has_retrans'):
            score += 15
            feedback_parts.append("TCP retransmission analysis present")
        else:
            feedback_parts.append("TCP retransmission analysis missing")

        # Criterion 6: Total packets and bytes
        pkt_score = 0
        if result.get('has_total_packets'):
            pkt_score += 10
            feedback_parts.append("Total packet count correct")
        else:
            feedback_parts.append("Total packet count not found or incorrect")

        if result.get('has_total_bytes'):
            pkt_score += 10
            feedback_parts.append("Total bytes correct")
        else:
            feedback_parts.append("Total bytes not found or incorrect")

        score += pkt_score

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
