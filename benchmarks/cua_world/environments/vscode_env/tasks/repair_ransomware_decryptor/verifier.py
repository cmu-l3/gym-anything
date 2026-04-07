#!/usr/bin/env python3
"""
Verifier for the repair_ransomware_decryptor task.

Verifies 5 critical bugs using a multi-signal approach:
For each bug, it checks if the exact file hash matches the ground truth (behavioral proof).
If the hash doesn't perfectly match (e.g., they didn't run the script), it parses the
AST/Code using Regex to see if the structural fix was applied (structural proof).

Points:
1. PBKDF2 Iterations (15 pts)
2. IV Extraction Size (15 pts)
3. PKCS7 Padding (15 pts)
4. Binary I/O (15 pts)
5. Recursive Traversal (15 pts)
6. VLM Trajectory Verification (25 pts)

Total: 100 points. Pass threshold: 60.
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


def verify_ransomware_decryptor(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    code = result.get('decryptor_code', '')
    recovered = result.get('recovered_files', {})
    ground_truth = result.get('ground_truth', {})

    score = 0
    feedback = []

    # ─────────────────────────────────────────────────────────────
    # 1. PBKDF2 Iterations (15 points)
    # ─────────────────────────────────────────────────────────────
    if 'notes.txt' in recovered and recovered['notes.txt'] == ground_truth.get('notes.txt'):
        score += 15
        feedback.append("[+] Iterations Fixed: Recovered notes.txt hash matches.")
    elif re.search(r'iterations\s*=\s*100000', code):
        score += 15
        feedback.append("[+] Iterations Fixed: Code updated to 100,000 iterations.")
    else:
        feedback.append("[-] Iterations Bug: Script still uses incorrect KDF iterations.")

    # ─────────────────────────────────────────────────────────────
    # 2. IV Extraction Size (15 points)
    # ─────────────────────────────────────────────────────────────
    if 'notes.txt' in recovered and recovered['notes.txt'] == ground_truth.get('notes.txt'):
        score += 15
        feedback.append("[+] IV Extraction Fixed: Recovered notes.txt hash matches.")
    elif re.search(r'\[16\s*:\s*32\]', code) and (re.search(r'\[32\s*:\]', code) or re.search(r'\[32\s*:\s*\]', code)):
        score += 15
        feedback.append("[+] IV Extraction Fixed: Code slices 16 bytes for IV.")
    else:
        feedback.append("[-] IV Extraction Bug: Code still slices 32 bytes for an AES IV.")

    # ─────────────────────────────────────────────────────────────
    # 3. PKCS7 Padding (15 points)
    # ─────────────────────────────────────────────────────────────
    if 'diagram.png' in recovered and recovered['diagram.png'] == ground_truth.get('diagram.png'):
        score += 15
        feedback.append("[+] PKCS7 Padding Fixed: Recovered diagram.png hash matches.")
    elif re.search(r'unpadder\(\)', code) or re.search(r'PKCS7', code):
        score += 15
        feedback.append("[+] PKCS7 Padding Fixed: Code uses proper cryptography unpadder.")
    else:
        feedback.append("[-] PKCS7 Padding Bug: Code still uses naive rstrip padding.")

    # ─────────────────────────────────────────────────────────────
    # 4. Binary I/O (15 points)
    # ─────────────────────────────────────────────────────────────
    if 'diagram.png' in recovered and recovered['diagram.png'] == ground_truth.get('diagram.png'):
        score += 15
        feedback.append("[+] Binary I/O Fixed: Recovered diagram.png hash matches.")
    elif re.search(r'open\([^,]+,\s*[\'"]wb[\'"]\)', code):
        score += 15
        feedback.append("[+] Binary I/O Fixed: Code opens files in 'wb' mode.")
    else:
        feedback.append("[-] Binary I/O Bug: Code still opens files in text 'w' mode.")

    # ─────────────────────────────────────────────────────────────
    # 5. Directory Traversal (15 points)
    # ─────────────────────────────────────────────────────────────
    if 'subdir/config.txt' in recovered and recovered['subdir/config.txt'] == ground_truth.get('subdir/config.txt'):
        score += 15
        feedback.append("[+] Recursive Traversal Fixed: Nested subdir/config.txt recovered.")
    elif re.search(r'os\.walk', code) or re.search(r'rglob', code) or re.search(r'glob\(.*recursive=True\)', code):
        score += 15
        feedback.append("[+] Recursive Traversal Fixed: Code uses recursive directory parsing.")
    else:
        feedback.append("[-] Recursive Traversal Bug: Code still uses os.listdir (top-level only).")

    # ─────────────────────────────────────────────────────────────
    # 6. VLM Trajectory Verification (25 points)
    # ─────────────────────────────────────────────────────────────
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        if frames and final:
            vlm_prompt = """
            Look at this sequence of screenshots from a VS Code session.
            Did the user actively edit the Python script and use the terminal to run it?
            Respond in JSON:
            {
                "edited_code": true/false,
                "used_terminal": true/false,
                "confidence": "high"/"low"
            }
            """
            vlm_result = query_vlm(images=frames + [final], prompt=vlm_prompt)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("edited_code") and parsed.get("used_terminal"):
                    score += 25
                    feedback.append("[+] VLM: Verified trajectory shows active code editing and terminal usage.")
                else:
                    feedback.append("[-] VLM: Trajectory lacks evidence of terminal execution or code editing.")
            else:
                feedback.append(f"[!] VLM Error: {vlm_result.get('error')}")
        else:
            feedback.append("[-] VLM: Missing trajectory frames.")
    else:
        feedback.append("[-] VLM query function unavailable.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }