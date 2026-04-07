#!/usr/bin/env python3
"""
Verifier for the debug_iot_telemetry_decoder task.

Checks whether the agent identified and fixed 5 protocol and domain logic
bugs in the IoT telemetry pipeline.

Each fix is worth 20 points (total 100). Pass threshold: 60.
"""

import sys
import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_iot_decoder(traj, env_info, task_info):
    """
    Verify the 5 code fixes applied by the agent.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='iot_verify_')
    
    try:
        result_src = "/tmp/iot_telemetry_result.json"
        local_result = os.path.join(temp_dir, "iot_telemetry_result.json")

        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not access result file: {e}"}

        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {"passed": False, "score": 0, "feedback": "Result file empty or missing"}

        with open(local_result, 'r') as f:
            file_contents = json.load(f)

        score = 0
        feedback = []
        
        decoder_src = file_contents.get("decoder.py", "")
        db_mgr_src = file_contents.get("db_manager.py", "")

        # ── Bug 1: Endianness & Unpack Format (decoder.py) ──────────
        # Fix requires changing ">IHHHHBB" to "<IHhHBB" (Little endian, signed Int16 for Temp)
        # We look for the correct format string structure.
        unpack_fixed = bool(re.search(r'<\s*I\s*H\s*h\s*H\s*B\s*B', decoder_src))
        still_big_endian = bool(re.search(r'>\s*I', decoder_src))
        
        if unpack_fixed:
            score += 20
            feedback.append("[+] Unpack Format: correctly switched to Little Endian and Int16 (<IHhHBB) (20/20)")
        elif not still_big_endian and '<' in decoder_src and 'h' in decoder_src:
            score += 10
            feedback.append("[~] Unpack Format: Attempted to fix endianness/signedness but string is imperfect (10/20)")
        else:
            feedback.append("[-] Unpack Format: Endianness (> to <) or Signedness (H to h) not fixed (0/20)")

        # ── Bug 2: Checksum Loop (decoder.py) ──────────
        # Fix requires slicing payload[:11] or payload[:-1] to exclude the checksum byte from the XOR
        checksum_fixed = bool(
            re.search(r'payload\s*\[\s*:\s*11\s*\]', decoder_src) or 
            re.search(r'payload\s*\[\s*:-\s*1\s*\]', decoder_src) or
            re.search(r'range\(\s*11\s*\)', decoder_src) or
            re.search(r'len\(payload\)\s*-\s*1', decoder_src)
        )
        hardcoded_true = bool(re.search(r'return\s+True', decoder_src))

        if hardcoded_true:
            feedback.append("[-] Checksum Loop: Hardcoded 'return True' bypass detected (0/20)")
        elif checksum_fixed:
            score += 20
            feedback.append("[+] Checksum Loop: Correctly sliced payload to XOR bytes 0-10 only (20/20)")
        else:
            feedback.append("[-] Checksum Loop: Still XORing all bytes or slicing incorrectly (0/20)")

        # ── Bug 3: Temperature Scale Factor (decoder.py) ──────────
        # Fix requires changing `* 0.1` to `* 0.01` or `/ 100`
        scale_fixed = bool(
            re.search(r'temp_raw.*\*\s*0\.01', decoder_src) or
            re.search(r'temp_raw.*/\s*100', decoder_src)
        )
        still_point_one = bool(re.search(r'temp_raw.*\*\s*0\.1([^0-9]|$)', decoder_src))

        if scale_fixed and not still_point_one:
            score += 20
            feedback.append("[+] Scale Factor: Temperature scale correctly changed to 0.01 (20/20)")
        else:
            feedback.append("[-] Scale Factor: Temperature scale not corrected to 0.01 (0/20)")

        # ── Bug 4: Dew Point Magnus Formula (decoder.py) ──────────
        # Fix requires `math.log(rh / 100)` instead of `math.log(rh)`
        dp_fixed = bool(
            re.search(r'math\.log\s*\(\s*rh\s*/\s*100(?:\.0)?\s*\)', decoder_src) or
            re.search(r'math\.log\s*\(\s*rh\s*\*\s*0\.01\s*\)', decoder_src)
        )
        
        if dp_fixed:
            score += 20
            feedback.append("[+] Magnus Formula: Correctly applied RH fraction (rh/100) inside natural log (20/20)")
        else:
            feedback.append("[-] Magnus Formula: Still passing raw RH percentage to natural log (0/20)")

        # ── Bug 5: Event-time vs Processing-time (db_manager.py) ──────────
        # Fix requires replacing `time.time()` with `reading["timestamp"]`
        event_time_fixed = bool(
            re.search(r'event_time\s*=\s*int\(\s*reading\s*\[\s*[\'"]timestamp[\'"]\s*\]\s*\)', db_mgr_src) or
            re.search(r'=\s*reading\s*\[\s*[\'"]timestamp[\'"]\s*\]', db_mgr_src)
        )
        still_system_time = bool(re.search(r'time\.time\(\)', db_mgr_src))
        
        if event_time_fixed and not still_system_time:
            score += 20
            feedback.append("[+] Temporal Aggregation: Successfully mapped to event-time (reading['timestamp']) (20/20)")
        else:
            feedback.append("[-] Temporal Aggregation: Still anchoring data to system processing time (0/20)")

        passed = score >= task_info.get("metadata", {}).get("pass_threshold", 60)

        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}