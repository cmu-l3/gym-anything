#!/usr/bin/env python3
"""
verifier.py — Enterprise SAML SSO Authentication Setup

Scoring (100 pts total, pass threshold 60):
  Criterion 1: IdP Name configured correctly (`Azure-Entra-ID`) — 20 pts
  Criterion 2: IdP Login URL configured correctly (`https://login.microsoftonline.com/dummy-tenant/saml2`) — 20 pts
  Criterion 3: IdP Logout URL configured correctly (`https://login.microsoftonline.com/dummy-tenant/saml2/logout`) — 20 pts
  Criterion 4: Entity ID configured correctly (`https://sts.windows.net/dummy-tenant/`) — 20 pts
  Criterion 5: Name ID Format (`EmailAddress`) configured OR certificate evidence found — 20 pts
"""

import json
import os
import re

def verify_enterprise_saml_sso_authentication_setup(traj, env_info, task_info):
    """
    Verify the SAML SSO task configuration using the exported database and filesystem state.
    """
    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/saml_sso_result.json')
    local_path = '/tmp/saml_sso_verify_result.json'

    # 1. Retrieve the result file via copy_from_env
    if 'copy_from_env' not in env_info:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Execution environment error: copy_from_env not available."
        }

    try:
        env_info['copy_from_env'](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}. Check that export_result.sh ran successfully."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse result file: {e}"
        }

    db_dump = data.get("saml_db_dump", "").lower()
    fs_changes = data.get("saml_fs_changes", "").lower()

    score = 0
    details = []

    # Expected values
    expected_idp_name = metadata.get("expected_idp_name", "Azure-Entra-ID").lower()
    expected_login_url = metadata.get("expected_login_url", "https://login.microsoftonline.com/dummy-tenant/saml2").lower()
    expected_logout_url = metadata.get("expected_logout_url", "https://login.microsoftonline.com/dummy-tenant/saml2/logout").lower()
    expected_entity_id = metadata.get("expected_entity_id", "https://sts.windows.net/dummy-tenant/").lower()
    
    # We check for EmailAddress without strict spaces since the UI might format it differently internally
    expected_name_id_formats = ["emailaddress", "email address"]

    # Criterion 1: IdP Name
    if expected_idp_name in db_dump:
        score += 20
        details.append("PASS: IdP Name 'Azure-Entra-ID' found in configuration (+20)")
    else:
        details.append("FAIL: IdP Name 'Azure-Entra-ID' not found in configuration (0/20)")

    # Criterion 2: IdP Login URL
    if expected_login_url in db_dump:
        score += 20
        details.append("PASS: IdP Login URL correctly configured (+20)")
    else:
        details.append("FAIL: IdP Login URL not found or incorrect (0/20)")

    # Criterion 3: IdP Logout URL
    if expected_logout_url in db_dump:
        score += 20
        details.append("PASS: IdP Logout URL correctly configured (+20)")
    else:
        details.append("FAIL: IdP Logout URL not found or incorrect (0/20)")

    # Criterion 4: Entity ID
    if expected_entity_id in db_dump:
        score += 20
        details.append("PASS: IdP Issuer / Entity ID correctly configured (+20)")
    else:
        details.append("FAIL: IdP Issuer / Entity ID not found or incorrect (0/20)")

    # Criterion 5: Name ID Format OR Certificate evidence
    # Some builds of OpManager might obscure the exact Name ID format or store it differently,
    # so we also accept evidence of the certificate being uploaded.
    format_found = any(fmt in db_dump for fmt in expected_name_id_formats)
    cert_found = "azure_idp_cert.pem" in db_dump or "azure_idp_cert.pem" in fs_changes or ".pem" in fs_changes
    
    if format_found:
        score += 20
        details.append("PASS: Name ID Format 'EmailAddress' correctly configured (+20)")
    elif cert_found:
        score += 20
        details.append("PASS: Name ID Format missing from plain text, but Certificate upload evidence found (+20)")
    else:
        details.append("FAIL: Name ID Format 'EmailAddress' and Certificate upload evidence not found (0/20)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }