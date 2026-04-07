#!/usr/bin/env python3
"""
Verifier for the fix_network_protocol_dissector task.
Evaluates if the agent successfully patched 5 distinct protocol parser bugs.

Bugs and Point Values (18 pts each, +10 for VLM trajectory verification):
1. IP Checksum carry fold
2. TCP Seq wraparound modulo arithmetic
3. DNS pointer base offset
4. HTTP Content-Length int conversion
5. TLS version handshake check
"""

import os
import json
import re
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_network_protocol_dissector(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the fixes via static analysis of the modified files and VLM checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='packet_dissector_verify_')
    result_json_path = os.path.join(temp_dir, "packet_dissector_result.json")
    
    try:
        copy_from_env("/tmp/packet_dissector_result.json", result_json_path)
        with open(result_json_path, 'r', encoding='utf-8') as f:
            export_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read exported results: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read task results from environment."}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)
        os.rmdir(temp_dir)

    files = export_data.get("files", {})
    
    score = 0
    feedback_parts = []
    
    # ─── 1. IP Parser Check (18 pts) ──────────────────────────────────────────
    ip_data = files.get("parsers/ip_parser.py", {})
    ip_src = ip_data.get("content", "")
    ip_mod = ip_data.get("modified_during_task", False)
    
    # Look for carry fold: (total >> 16) + (total & 0xFFFF) or while total > 0xFFFF
    has_shift = bool(re.search(r'>>\s*16', ip_src))
    has_while = bool(re.search(r'while\s+total\s*>', ip_src))
    
    if "ERROR" in ip_src:
        feedback_parts.append("❌ ip_parser.py could not be read")
    elif not ip_mod:
        feedback_parts.append("❌ ip_parser.py was not modified")
    elif has_shift or has_while:
        score += 18
        feedback_parts.append("✅ IP checksum carry folding implemented")
    else:
        feedback_parts.append("❌ IP checksum carry folding missing")

    # ─── 2. TCP Tracker Check (18 pts) ────────────────────────────────────────
    tcp_data = files.get("parsers/tcp_tracker.py", {})
    tcp_src = tcp_data.get("content", "")
    tcp_mod = tcp_data.get("modified_during_task", False)
    
    # Look for modulo arithmetic: % (1 << 32) or % 4294967296 or similar
    has_modulo = bool(re.search(r'%|mod', tcp_src))
    has_32bit = bool(re.search(r'1\s*<<\s*32|4294967296|0x100000000', tcp_src))
    has_buggy_cmp = bool(re.search(r'seq_num\s*>=\s*last_ack', tcp_src))
    
    if "ERROR" in tcp_src:
        feedback_parts.append("❌ tcp_tracker.py could not be read")
    elif not tcp_mod:
        feedback_parts.append("❌ tcp_tracker.py was not modified")
    elif (has_modulo and has_32bit) or (not has_buggy_cmp and "-" in tcp_src):
        score += 18
        feedback_parts.append("✅ TCP sequence wraparound fixed")
    else:
        feedback_parts.append("❌ TCP sequence comparison still buggy")

    # ─── 3. DNS Parser Check (18 pts) ─────────────────────────────────────────
    dns_data = files.get("parsers/dns_parser.py", {})
    dns_src = dns_data.get("content", "")
    dns_mod = dns_data.get("modified_during_task", False)
    
    # Look for pointer + dns_msg_start
    has_addition = bool(re.search(r'pointer\s*\+\s*dns_msg_start', dns_src))
    buggy_call = "decompress_name(packet_bytes, pointer, dns_msg_start)"
    
    if "ERROR" in dns_src:
        feedback_parts.append("❌ dns_parser.py could not be read")
    elif not dns_mod:
        feedback_parts.append("❌ dns_parser.py was not modified")
    elif has_addition or (buggy_call not in dns_src and "dns_msg_start" in dns_src):
        score += 18
        feedback_parts.append("✅ DNS pointer offset fixed")
    else:
        feedback_parts.append("❌ DNS pointer base offset not corrected")

    # ─── 4. HTTP Parser Check (18 pts) ────────────────────────────────────────
    http_data = files.get("parsers/http_parser.py", {})
    http_src = http_data.get("content", "")
    http_mod = http_data.get("modified_during_task", False)
    
    # Look for int() conversion
    has_int = bool(re.search(r'int\s*\(', http_src))
    still_string = bool(re.search(r'>\s*["\']1000["\']', http_src))
    
    if "ERROR" in http_src:
        feedback_parts.append("❌ http_parser.py could not be read")
    elif not http_mod:
        feedback_parts.append("❌ http_parser.py was not modified")
    elif has_int and not still_string:
        score += 18
        feedback_parts.append("✅ HTTP Content-Length converted to integer")
    else:
        feedback_parts.append("❌ HTTP Content-Length still compared as string")

    # ─── 5. TLS Parser Check (18 pts) ─────────────────────────────────────────
    tls_data = files.get("parsers/tls_parser.py", {})
    tls_src = tls_data.get("content", "")
    tls_mod = tls_data.get("modified_during_task", False)
    
    # Look for inspection of extensions (0x002B, 43, supported_versions)
    has_ext = bool(re.search(r'0x002B|0x2b|43|supported_versions', tls_src, re.IGNORECASE))
    
    if "ERROR" in tls_src:
        feedback_parts.append("❌ tls_parser.py could not be read")
    elif not tls_mod:
        feedback_parts.append("❌ tls_parser.py was not modified")
    elif has_ext:
        score += 18
        feedback_parts.append("✅ TLS version detection checks extensions")
    else:
        feedback_parts.append("❌ TLS version detection still checks record layer only")

    # ─── 6. VLM Trajectory Check (10 pts) ─────────────────────────────────────
    query_vlm = env_info.get('query_vlm')
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if query_vlm and images:
        prompt = """Look at these screenshots from a VSCode session. 
        Did the user actively edit Python code in the parser modules?
        Respond with a JSON object containing a single boolean field 'edited_code'."""
        
        vlm_result = query_vlm(images=images, prompt=prompt)
        
        if vlm_result and vlm_result.get('parsed', {}).get('edited_code', False):
            score += 10
            feedback_parts.append("✅ VLM confirmed code editing workflow")
        else:
            feedback_parts.append("❌ VLM could not confirm code editing workflow")
    else:
        # If VLM is unavailable, award the points to avoid penalizing the agent
        score += 10
        feedback_parts.append("⚠️ VLM verification skipped (API unavailable)")

    # ─── Final Score Evaluation ───────────────────────────────────────────────
    pass_threshold = task_info.get('metadata', {}).get('pass_threshold', 60)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }