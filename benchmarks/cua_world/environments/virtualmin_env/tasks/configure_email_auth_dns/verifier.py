#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_email_auth_dns(traj, env_info, task_info):
    """
    Verifies that SPF and DMARC records were correctly added to localbiz.test.
    
    Scoring Criteria (100 pts total):
    1. SPF Record (40 pts):
       - Exists and contains 'v=spf1': 10 pts
       - Contains 'a': 5 pts
       - Contains 'mx': 5 pts
       - Contains 'ip4:127.0.0.1': 10 pts
       - Contains '~all': 10 pts
    2. DMARC Record (40 pts):
       - Exists at _dmarc subdomain: 10 pts
       - Contains 'p=quarantine': 10 pts
       - Contains 'rua=mailto:admin@localbiz.test': 10 pts
       - Contains 'pct=100': 10 pts
    3. Anti-Gaming / Zone Update (20 pts):
       - Zone Serial number increased: 10 pts
       - BIND Zone file modified during task: 10 pts
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    dns_dump = result_data.get("dns_records_dump", "")
    dig_spf = result_data.get("dig_spf", "").strip('"').strip() # Dig often quotes output
    dig_dmarc = result_data.get("dig_dmarc", "").strip('"').strip()
    
    initial_serial = int(result_data.get("initial_serial", 0))
    final_serial = int(result_data.get("final_serial", 0))
    zone_modified = result_data.get("zone_modified_timestamp", False)

    # --- PART 1: SPF Verification (40 pts) ---
    # We prefer dig output as it proves the server is actually serving the record
    # Fallback to virtualmin dump if dig fails (e.g. propagation delay, though unlikely on local)
    spf_found = False
    spf_content = ""
    
    if "v=spf1" in dig_spf:
        spf_found = True
        spf_content = dig_spf
    elif "v=spf1" in dns_dump:
        # Parse from dump: look for line containing v=spf1
        for line in dns_dump.split('\n'):
            if "v=spf1" in line and "localbiz.test" in line:
                spf_found = True
                spf_content = line
                break
    
    if spf_found:
        score += 10
        feedback.append("SPF record found (+10)")
        
        if "a" in spf_content.lower().split(): # Split to ensure 'a' isn't part of another word
            score += 5
        else:
            feedback.append("SPF missing 'a' mechanism")
            
        if "mx" in spf_content.lower().split():
            score += 5
        else:
            feedback.append("SPF missing 'mx' mechanism")
            
        if "ip4:127.0.0.1" in spf_content:
            score += 10
        else:
            feedback.append("SPF missing or incorrect ip4 mechanism")
            
        if "~all" in spf_content:
            score += 10
        else:
            feedback.append("SPF missing '~all' qualifier")
    else:
        feedback.append("No SPF record found (0/40)")

    # --- PART 2: DMARC Verification (40 pts) ---
    dmarc_found = False
    dmarc_content = ""
    
    if "v=DMARC1" in dig_dmarc or "v=dmarc1" in dig_dmarc.lower():
        dmarc_found = True
        dmarc_content = dig_dmarc
    elif "_dmarc" in dns_dump and "v=DMARC1" in dns_dump:
        for line in dns_dump.split('\n'):
            if "_dmarc" in line and "v=DMARC1" in line:
                dmarc_found = True
                dmarc_content = line
                break

    if dmarc_found:
        score += 10
        feedback.append("DMARC record found (+10)")
        
        if "p=quarantine" in dmarc_content:
            score += 10
        else:
            feedback.append("DMARC policy is not 'quarantine'")
            
        if "rua=mailto:admin@localbiz.test" in dmarc_content:
            score += 10
        else:
            feedback.append("DMARC rua email incorrect")
            
        if "pct=100" in dmarc_content:
            score += 10
        else:
            feedback.append("DMARC percentage incorrect")
    else:
        feedback.append("No DMARC record found (0/40)")

    # --- PART 3: Anti-Gaming / Persistence (20 pts) ---
    if final_serial > initial_serial:
        score += 10
        feedback.append("DNS Zone Serial incremented (+10)")
    else:
        feedback.append("DNS Zone Serial did not change (changes not applied?)")
        
    if zone_modified:
        score += 10
        feedback.append("Zone file modified on disk (+10)")
    else:
        feedback.append("Zone file timestamp unchanged")

    # --- VLM SANITY CHECK (Optional but recommended) ---
    # If score is high but we want to ensure they didn't just use a backdoor script 
    # (though in this env, using terminal is valid, so this is just informational or for tie-breaking)
    if score >= 60:
        frames = sample_trajectory_frames(traj, n=3)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        # We don't penalize score here because CLI is a valid way to solve this task in Linux,
        # but we log it for the feedback.
        try:
            vlm_res = query_vlm(
                images=frames,
                prompt="Do these screenshots show a user interacting with a DNS management interface in Virtualmin or Webmin? Look for 'DNS Records', 'Edit Records', or a table of DNS entries."
            )
            if vlm_res.get('success'):
                feedback.append(f"VLM Analysis: {vlm_res.get('answer', 'N/A')}")
        except:
            pass

    passed = score >= 60 and spf_found and dmarc_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }