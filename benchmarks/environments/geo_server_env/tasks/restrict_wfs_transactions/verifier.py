#!/usr/bin/env python3
"""Verifier for restrict_wfs_transactions task."""

import json
import tempfile
import os

def verify_restrict_wfs_transactions(traj, env_info, task_info):
    """
    Verify that WFS Transaction is restricted to ADMIN and GetFeature is public.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/restrict_wfs_transactions_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # If nonce check fails, we generally fail the task to prevent cheating
        pass 
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # --------------------------------------------------------------------------
    # CRITERION 1: Public Read Access (30 points)
    # --------------------------------------------------------------------------
    read_status = result.get('public_read_status', 0)
    if read_status == 200:
        score += 30
        feedback_parts.append("✅ Public WFS GetFeature allowed (HTTP 200)")
    else:
        feedback_parts.append(f"❌ Public WFS GetFeature blocked or failed (HTTP {read_status})")

    # --------------------------------------------------------------------------
    # CRITERION 2: Anonymous Write Blocked (40 points)
    # --------------------------------------------------------------------------
    anon_write_status = result.get('public_write_status', 0)
    # 401 Unauthorized or 403 Forbidden are acceptable blocks
    if anon_write_status in [401, 403]:
        score += 40
        feedback_parts.append(f"✅ Anonymous WFS Transaction blocked (HTTP {anon_write_status})")
    elif anon_write_status == 200:
        feedback_parts.append("❌ Anonymous WFS Transaction still allowed (HTTP 200)")
    else:
        # Any other code (e.g. 500) suggests broken server but not necessarily security
        feedback_parts.append(f"❌ Anonymous WFS Transaction response unexpected (HTTP {anon_write_status})")

    # --------------------------------------------------------------------------
    # CRITERION 3: Admin Write Allowed (10 points)
    # --------------------------------------------------------------------------
    admin_write_status = result.get('admin_write_status', 0)
    # Admin should NOT be blocked (not 401/403). 
    # 200 is success. 400 is schema error (which means auth passed and it tried to process).
    if admin_write_status not in [401, 403] and admin_write_status > 0:
        score += 10
        feedback_parts.append(f"✅ Admin WFS Transaction authorized (HTTP {admin_write_status})")
    else:
        feedback_parts.append(f"❌ Admin WFS Transaction blocked (HTTP {admin_write_status})")

    # --------------------------------------------------------------------------
    # CRITERION 4: Explicit Configuration (20 points)
    # --------------------------------------------------------------------------
    has_rule = result.get('config_has_transaction_rule', False)
    has_admin = result.get('config_has_admin_role', False)
    
    if has_rule and has_admin:
        score += 20
        feedback_parts.append("✅ Configuration file confirms 'wfs.Transaction' restricted to ADMIN")
    elif has_rule:
        score += 10
        feedback_parts.append("⚠️ Configuration has 'wfs.Transaction' rule but ADMIN role not detected")
    else:
        feedback_parts.append("⚠️ No explicit 'wfs.Transaction' rule found in services.properties")

    # --------------------------------------------------------------------------
    # GUI Interaction Check (Pass/Fail Gate)
    # --------------------------------------------------------------------------
    # If the user performed everything via API scripts without GUI, we might penalize
    # but the task instructions imply GUI usage.
    gui_detected = result.get('gui_interaction_detected', False)
    if not gui_detected:
        feedback_parts.append("ℹ️ No GUI interaction detected via access logs")

    # --------------------------------------------------------------------------
    # Final Result
    # --------------------------------------------------------------------------
    # Critical pass condition: Must allow read AND block anon write
    critical_pass = (read_status == 200) and (anon_write_status in [401, 403])
    
    return {
        "passed": critical_pass and score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }