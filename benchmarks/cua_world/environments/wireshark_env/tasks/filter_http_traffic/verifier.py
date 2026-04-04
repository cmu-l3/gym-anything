#!/usr/bin/env python3
"""Verifier for filter_http_traffic task."""

import json
import tempfile
import os


def verify_filter_http_traffic(traj, env_info, task_info):
    """Verify that the user filtered HTTP traffic and exported the result."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

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

    feedback_parts = []
    score = 0

    # Criterion 1: Filtered file exists (30 pts)
    if result.get('filtered_file_exists'):
        score += 30
        feedback_parts.append("Filtered PCAP file created")
    else:
        feedback_parts.append("Filtered PCAP file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Filtered file has packets (20 pts)
    filtered_count = result.get('filtered_packet_count', 0)
    initial_http = result.get('initial_http_packets', 0)
    http_in_file = result.get('http_packets_in_file', 0)
    if filtered_count > 0:
        score += 20
        feedback_parts.append(f"Filtered file contains {filtered_count} packets ({http_in_file} HTTP)")
    else:
        feedback_parts.append("Filtered file is empty")

    # Criterion 3: File contains HTTP traffic only (30 pts)
    # Wireshark's "Export Specified Packets" with "Displayed" filter exports
    # the displayed packets plus underlying TCP segments. This is correct behavior.
    # We accept: all packets are HTTP, OR all non-HTTP packets are TCP segments.
    if result.get('all_packets_are_http'):
        score += 30
        feedback_parts.append("All packets are HTTP/TCP traffic (correctly filtered)")
    elif http_in_file > 0:
        # Partial credit if file has some HTTP packets
        score += 15
        feedback_parts.append(f"File has {http_in_file} HTTP packets but also contains non-HTTP/TCP traffic")
    else:
        feedback_parts.append("No HTTP packets found in filtered file")

    # Criterion 4: HTTP packet count matches expected (20 pts)
    if initial_http > 0 and http_in_file > 0:
        ratio = http_in_file / initial_http
        if 0.8 <= ratio <= 1.2:
            score += 20
            feedback_parts.append(f"HTTP count matches expected ({http_in_file} vs {initial_http} expected)")
        elif 0.5 <= ratio <= 2.0:
            score += 10
            feedback_parts.append(f"HTTP count close to expected ({http_in_file} vs {initial_http} expected)")
        else:
            feedback_parts.append(f"HTTP count mismatch ({http_in_file} vs {initial_http} expected)")
    elif filtered_count > 0 and initial_http > 0:
        # Check total packet count as fallback
        ratio = filtered_count / initial_http
        if 0.5 <= ratio <= 5.0:
            score += 10
            feedback_parts.append(f"Packet count in reasonable range ({filtered_count} total)")
        else:
            feedback_parts.append(f"Packet count unexpected ({filtered_count} vs {initial_http} HTTP expected)")
    elif filtered_count > 0:
        score += 10
        feedback_parts.append("Could not verify exact count match")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
