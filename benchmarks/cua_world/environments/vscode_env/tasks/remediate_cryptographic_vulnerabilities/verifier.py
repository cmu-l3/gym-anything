#!/usr/bin/env python3
"""
Verifier for Cryptographic Vulnerabilities Remediation Task.
Checks static properties of the Python code + dynamic file output + VLM trajectory.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to ensure trajectory proves agent did the work
VLM_PROMPT = """
Look at these screenshots from a VS Code coding session.
Did the user/agent actively edit Python files (specifically encryption.py, tokens.py, or auth.py) 
AND run a script in the terminal? 

Reply in JSON format:
{
    "edited_code": true/false,
    "ran_terminal": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_crypto_remediation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read exported result
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

    code = result.get('code', {})
    enc_code = code.get('encryption', '')
    tok_code = code.get('tokens', '')
    auth_code = code.get('auth', '')

    score = 0
    feedback = []

    # ---------------------------------------------------------
    # STATIC ANALYSIS CHECKS (10 points per vulnerability fixed)
    # ---------------------------------------------------------

    # 1. ECB Mode Fixed
    has_ecb = 'AES.MODE_ECB' in enc_code
    has_secure_mode = ('AES.MODE_GCM' in enc_code) or ('AES.MODE_CBC' in enc_code)
    has_random_iv = ('get_random_bytes' in enc_code) or ('urandom' in enc_code) or ('secrets' in enc_code)
    if not has_ecb and has_secure_mode and has_random_iv:
        score += 10
        feedback.append("[+] ECB mode removed; Secure mode and random IV found.")
    else:
        feedback.append("[-] ECB mode not properly fixed or static IV still used.")

    # 2. Weak Randomness Fixed
    has_random_choices = 'random.choices' in tok_code
    has_secrets = ('secrets.choice' in tok_code) or ('secrets.token_' in tok_code)
    if not has_random_choices and has_secrets:
        score += 10
        feedback.append("[+] Weak randomness fixed (secrets module used).")
    else:
        feedback.append("[-] Session tokens still use weak randomness.")

    # 3. JWT 'none' Algorithm Fixed
    has_none_alg = ('"none"' in tok_code) or ("'none'" in tok_code)
    if not has_none_alg:
        score += 10
        feedback.append("[+] JWT 'none' algorithm vulnerability removed.")
    else:
        feedback.append("[-] JWT verify still accepts 'none' algorithm.")

    # 4. MD5 Hashing Fixed
    has_md5 = 'hashlib.md5' in auth_code
    has_secure_hash = ('pbkdf2_hmac' in auth_code) or ('sha256' in auth_code) or ('bcrypt' in auth_code)
    if not has_md5 and has_secure_hash:
        score += 10
        feedback.append("[+] MD5 removed; secure hashing algorithm found.")
    else:
        feedback.append("[-] MD5 still present or no secure alternative used.")

    # 5. Timing Attack Fixed
    has_equals = '==' in auth_code.split("def verify_password")[-1]  # roughly checking the function
    has_compare_digest = 'compare_digest' in auth_code
    if has_compare_digest:
        score += 10
        feedback.append("[+] Timing attack fixed (compare_digest used).")
    else:
        feedback.append("[-] Timing attack vulnerability remains (compare_digest missing).")

    # ---------------------------------------------------------
    # DYNAMIC PIPELINE CHECK (25 points) - Anti-gaming
    # ---------------------------------------------------------
    output_exists = result.get('output_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if output_exists and file_created:
        score += 25
        feedback.append("[+] Pipeline ran successfully; encrypted output generated dynamically.")
    elif output_exists:
        feedback.append("[-] Pipeline output exists but timestamp suggests it wasn't created during the task (gaming attempt).")
    else:
        feedback.append("[-] Pipeline failed to run or assertion blocked execution (output file missing).")

    # ---------------------------------------------------------
    # VLM TRAJECTORY VERIFICATION (25 points) - Anti-gaming
    # ---------------------------------------------------------
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        try:
            vlm_response = query_vlm(images=frames + [final], prompt=VLM_PROMPT)
            parsed = vlm_response.get("parsed", {})
            
            if parsed.get("edited_code", False) and parsed.get("ran_terminal", False):
                score += 25
                feedback.append("[+] VLM confirmed agent actively edited code and ran the terminal.")
            else:
                feedback.append("[-] VLM could not confirm active terminal usage or code editing.")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback.append(f"[!] VLM check skipped/failed: {e}")

    # Calculate final status
    key_criteria_met = output_exists and file_created and (not has_ecb) and has_compare_digest
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }