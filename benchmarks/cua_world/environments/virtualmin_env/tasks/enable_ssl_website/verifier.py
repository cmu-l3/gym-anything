#!/usr/bin/env python3
"""
Verifier for enable_ssl_website task.

VERIFICATION CRITERIA:
1. SSL Feature Enabled (20 pts)
2. HTTPS Responds 200 OK (15 pts)
3. Certificate Details Match (50 pts total)
   - Organization (O): 15 pts
   - Unit (OU): 10 pts
   - Locality (L): 10 pts
   - State (ST): 10 pts
   - Country (C): 5 pts
4. Certificate Validity ~365 days (5 pts)
5. Anti-gaming: Cert files created during task (5 pts)
6. Anti-gaming: VLM verification of UI usage (5 pts)

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_ssl_website(traj, env_info, task_info):
    """
    Verify the agent enabled SSL and generated a correct self-signed certificate.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # Metadata targets
    targets = task_info.get('metadata', {}).get('cert_details', {
        "O": "Acme Corporation",
        "OU": "Web Services",
        "L": "San Francisco",
        "ST": "California",
        "C": "US",
        "validity_days": 365
    })

    # --- Criterion 1: SSL Feature Enabled (20 pts) ---
    if result.get("ssl_feature_enabled", False):
        score += 20
        feedback_parts.append("SSL feature enabled (+20)")
    else:
        feedback_parts.append("SSL feature NOT enabled (0)")

    # --- Criterion 2: HTTPS Responds (15 pts) ---
    http_code = str(result.get("http_response_code", "000"))
    if http_code == "200":
        score += 15
        feedback_parts.append("HTTPS responds 200 OK (+15)")
    elif http_code.startswith("2") or http_code.startswith("3"):
        score += 10
        feedback_parts.append(f"HTTPS responds {http_code} (+10)")
    else:
        feedback_parts.append(f"HTTPS failed ({http_code}) (0)")

    # --- Criterion 3: Certificate Details (50 pts) ---
    cert = result.get("cert_details", {})
    
    # Check Organization (O)
    if targets["O"] in cert.get("O", ""):
        score += 15
        feedback_parts.append("Org correct (+15)")
    else:
        feedback_parts.append(f"Org mismatch: found '{cert.get('O')}' (0)")

    # Check Org Unit (OU)
    if targets["OU"] in cert.get("OU", ""):
        score += 10
        feedback_parts.append("Unit correct (+10)")
    else:
        feedback_parts.append(f"Unit mismatch: found '{cert.get('OU')}' (0)")

    # Check Locality (L)
    if targets["L"] in cert.get("L", ""):
        score += 10
        feedback_parts.append("Locality correct (+10)")
    else:
        feedback_parts.append(f"Locality mismatch: found '{cert.get('L')}' (0)")

    # Check State (ST)
    if targets["ST"] in cert.get("ST", ""):
        score += 10
        feedback_parts.append("State correct (+10)")
    else:
        feedback_parts.append(f"State mismatch: found '{cert.get('ST')}' (0)")

    # Check Country (C)
    if targets["C"] in cert.get("C", ""):
        score += 5
        feedback_parts.append("Country correct (+5)")
    else:
        feedback_parts.append(f"Country mismatch: found '{cert.get('C')}' (0)")

    # --- Criterion 4: Validity (5 pts) ---
    actual_days = cert.get("validity_days", 0)
    if 335 <= actual_days <= 395:
        score += 5
        feedback_parts.append(f"Validity {actual_days} days (+5)")
    else:
        feedback_parts.append(f"Validity invalid ({actual_days} days) (0)")

    # --- Criterion 5: Anti-gaming Timestamp (5 pts) ---
    if result.get("files_created_during_task", False):
        score += 5
        feedback_parts.append("New cert generated (+5)")
    else:
        feedback_parts.append("No new cert detected (0)")

    # --- Criterion 6: VLM UI Verification (5 pts) ---
    # We want to ensure they actually used the UI and didn't just CLI it
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = "Does this sequence show a user interacting with the Virtualmin web interface to configure SSL settings or certificates? Look for 'SSL', 'Certificate', 'Manage SSL', or 'Enable features'."
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        
        # Simple boolean check based on VLM response text (heuristic)
        response_lower = vlm_result.get("response", "").lower()
        if "yes" in response_lower and ("virtualmin" in response_lower or "ssl" in response_lower):
            score += 5
            feedback_parts.append("UI usage verified (+5)")
        else:
            feedback_parts.append("UI usage not clear (0)")
    else:
        feedback_parts.append("No frames to verify (0)")

    passed = score >= 60 and result.get("ssl_feature_enabled", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }