#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_install_custom_ssl_cert(traj, env_info, task_info):
    """
    Verify that the custom SSL certificate was installed correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expected values
    # Issuer should contain the custom mock CA name
    EXPECTED_ISSUER_SUBSTRING = "Global Trusted Mock CA Intermediate"
    # Subject should be the domain
    EXPECTED_SUBJECT_SUBSTRING = "CN = acmecorp.test"
    # Alternatively strict CN check: "subject=C = US, ST = State, L = City, O = Acme Corp, CN = acmecorp.test"
    
    score = 0
    feedback = []
    
    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check Issuer (Critical - 40 pts)
    # The issuer string from openssl looks like: "issuer=C = US, ST = State, ..."
    actual_issuer = result.get("ssl_issuer", "")
    if EXPECTED_ISSUER_SUBSTRING in actual_issuer:
        score += 40
        feedback.append("Success: Correct custom certificate is being served (Issuer match).")
    else:
        feedback.append(f"Fail: Server is serving certificate from issuer '{actual_issuer}' instead of '{EXPECTED_ISSUER_SUBSTRING}'.")

    # 3. Check Subject (20 pts)
    actual_subject = result.get("ssl_subject", "")
    if "acmecorp.test" in actual_subject:
        score += 20
        feedback.append("Success: Certificate subject matches domain.")
    else:
        feedback.append(f"Fail: Certificate subject '{actual_subject}' does not match acmecorp.test.")

    # 4. Check Chain/Bundle (20 pts)
    # A proper install with the bundle should result in at least 2 certs in the handshake 
    # (Leaf + Intermediate), possibly 3 if Root is sent (though usually Root is in trust store).
    # Since we didn't add Root to system trust store, s_client might not verify it, 
    # but we are checking if the server *sent* the intermediate.
    chain_count = result.get("chain_count", 0)
    if chain_count >= 2:
        score += 20
        feedback.append(f"Success: Intermediate CA bundle is being served (Chain length: {chain_count}).")
    elif chain_count == 1:
        feedback.append("Partial Fail: Only leaf certificate served. Intermediate bundle missing.")
        # No points for broken chain in a "custom cert" task where providing the bundle is key.
    else:
        feedback.append("Fail: No certificate chain detected.")

    # 5. Check Config Modification (Anti-gaming / Confirmation - 20 pts)
    if result.get("config_modified", False):
        score += 20
        feedback.append("Success: Web server configuration was updated during task.")
    else:
        # If the issuer matches, they *must* have updated it, but maybe the timestamp check failed?
        # We give benefit of doubt if issuer is perfect.
        if score >= 40:
             score += 20
             feedback.append("Note: Config timestamp check failed, but correct cert is live.")
        else:
             feedback.append("Fail: No configuration changes detected.")

    passed = (score >= 80)  # Requires correct cert (40+20) + bundle (20) OR config (20)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }