#!/usr/bin/env python3
"""
Verifier for the fix_aerospace_telemetry_parser task.

Checks whether the agent identified and fixed 5 binary parsing bugs:
1. Checksum validation algorithm (XOR instead of sum % 256)
2. GPS Endianness (>ff -> <ff)
3. IMU Padding (<Bfff -> <Bxxxfff or <B3xfff)
4. Barometer Type (<h -> <I)
5. Status Bitmask (0x04 -> 0x08)
6. Git workflow (staged and committed changes)

Each fix is worth ~15-20 points (total 100). Pass threshold: 60.
"""

import sys
import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_telemetry_parser(traj, env_info, task_info):
    """
    Verify the telemetry parser fixes using exported results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='telemetry_verify_')
    local_result = os.path.join(temp_dir, "telemetry_result.json")

    try:
        copy_from_env("/tmp/telemetry_result.json", local_result)
        with open(local_result, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not access result file: {str(e)}"}
    finally:
        if os.path.exists(local_result):
            os.unlink(local_result)
        os.rmdir(temp_dir)

    score = 0
    feedback = []
    
    code = result.get("parser_code", "")
    csv_exists = result.get("csv_exists", False)
    csv_stats = result.get("csv_stats", {})
    git_commits = result.get("git_commits", [])

    if not code or code.startswith("ERROR"):
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve parser.py code."}

    # ── Bug 1: Checksum fix (20 pts) ──────────
    # Can be verified via Regex (looks for ^ operator) AND if CSV was generated at all.
    has_xor = bool(re.search(r'\^=', code) or re.search(r'operator\.xor', code))
    has_sum_mod = bool(re.search(r'sum\(.*\) % 256', code))
    
    if csv_exists and len(csv_stats) > 0:
        score += 20
        feedback.append("[+] Checksum validation bypassed or fixed (CSV successfully generated)")
    elif has_xor and not has_sum_mod:
        score += 10
        feedback.append("[~] Checksum XOR implemented, but CSV was not generated")
    else:
        feedback.append("[-] Checksum algorithm still incorrect (CSV not generated)")

    # ── Bug 2: GPS Endianness (15 pts) ──────────
    # Check if `>ff` was changed to `<ff` AND if lat is realistic (~32.9)
    avg_lat = csv_stats.get("avg_lat", 0)
    has_little_endian_float = bool(re.search(r"['\"]<ff['\"]", code))
    
    if 32.0 < avg_lat < 34.0:
        score += 15
        feedback.append("[+] GPS Endianness fixed (Valid Lat/Lon extracted)")
    elif has_little_endian_float:
        score += 10
        feedback.append("[~] GPS unpack format fixed to '<ff', but CSV data missing")
    else:
        feedback.append("[-] GPS unpacking still uses incorrect endianness")

    # ── Bug 3: IMU Padding (15 pts) ──────────
    # Check if `<Bfff` was changed to handle padding (e.g. `<B3xfff`) AND az ~9.81
    initial_az = csv_stats.get("initial_az", -999)
    has_padding_format = bool(re.search(r"['\"]<B3xfff['\"]", code) or re.search(r"['\"]<Bxxxfff['\"]", code))
    
    if 9.0 < initial_az < 10.5:
        score += 15
        feedback.append("[+] IMU C-struct padding fixed (Correct Z-axis acceleration)")
    elif has_padding_format:
        score += 10
        feedback.append("[~] IMU unpack format fixed to include padding, but CSV data missing")
    else:
        feedback.append("[-] IMU unpacking still ignores 3-byte padding")

    # ── Bug 4: Barometer Data Type (15 pts) ──────────
    # Check if `<h` was changed to `<I` AND max_pressure ~86000
    max_pressure = csv_stats.get("max_pressure", 0)
    has_unsigned_int = bool(re.search(r"['\"]<[Ii]['\"]", code))
    
    if 80000 < max_pressure < 110000:
        score += 15
        feedback.append("[+] Barometer data type fixed (Pressure is realistic)")
    elif has_unsigned_int:
        score += 10
        feedback.append("[~] Barometer unpack format fixed to 32-bit unsigned, but CSV data missing")
    else:
        feedback.append("[-] Barometer unpacking still uses 16-bit signed integer")

    # ── Bug 5: Status Bitmask (15 pts) ──────────
    # Check if 0x04 was changed to 0x08 AND if parachute deployed became True
    parachute_any = csv_stats.get("parachute_deployed_any", False)
    has_correct_bitmask = bool(re.search(r'&\s*(0x08|8)\b', code))
    
    if parachute_any:
        score += 15
        feedback.append("[+] Status bitmask fixed (Parachute deployment detected)")
    elif has_correct_bitmask:
        score += 10
        feedback.append("[~] Status bitmask corrected to 0x08, but CSV data missing")
    else:
        feedback.append("[-] Status bitmask still uses incorrect bit (0x04)")

    # ── Bug 6: Git Workflow (20 pts) ──────────
    if len(git_commits) > 1:
        score += 20
        feedback.append("[+] Fixes were committed to Git successfully")
    else:
        feedback.append("[-] Changes were not committed to Git")

    # Ensure total score caps at 100 in case of edge logic
    score = min(score, 100)
    passed = score >= 60 and csv_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }