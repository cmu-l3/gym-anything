#!/usr/bin/env python3
"""Verifier for configure_domain_resource_limits task.

Scoring (100 points):
- Correct domain targeted: prerequisite (score=0 if wrong)
- Disk quota set to ~500MB: 25 points
- Bandwidth limit set to ~5GB: 25 points
- Max mailboxes set to 10: 20 points
- Max aliases set to 20: 15 points
- Max databases set to 3: 15 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_configure_domain_resource_limits(traj, env_info, task_info):
    """Verify that resource limits were correctly configured for greenvalley.test."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_domain = metadata.get('target_domain', 'greenvalley.test')
    expected_quota_mb = metadata.get('expected_quota_mb', 500)
    expected_bw_gb = metadata.get('expected_bw_gb', 5)
    expected_max_mailboxes = metadata.get('expected_max_mailboxes', 10)
    expected_max_aliases = metadata.get('expected_max_aliases', 20)
    expected_max_dbs = metadata.get('expected_max_dbs', 3)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_domain_resource_limits_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # CRITICAL: Check correct domain
        actual_domain = result.get('domain', '')
        if actual_domain != expected_domain:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"CRITICAL: Wrong domain! Expected {expected_domain}, got {actual_domain}"
            }

        # Subtask 1: Disk quota (~500MB)
        # Virtualmin reports quota in bytes or kB. 500MB = 512000 kB = 524288000 bytes
        quota_val = result.get('quota_parsed')
        if quota_val is not None and isinstance(quota_val, (int, float)):
            # Convert to MB for comparison (could be in bytes or kB)
            quota_mb = None
            if quota_val > 100000000:  # Likely bytes
                quota_mb = quota_val / (1024 * 1024)
            elif quota_val > 100000:  # Likely kB
                quota_mb = quota_val / 1024
            else:  # Likely already MB or small value
                quota_mb = quota_val

            # Allow ±10% tolerance
            if quota_mb is not None and abs(quota_mb - expected_quota_mb) / expected_quota_mb <= 0.10:
                score += 25
                subscores["disk_quota"] = True
                feedback_parts.append(f"Disk quota set correctly (~{quota_mb:.0f}MB)")
            else:
                feedback_parts.append(f"Disk quota incorrect: ~{quota_mb:.0f}MB (expected ~{expected_quota_mb}MB)")
        else:
            feedback_parts.append(f"Disk quota not set (still unlimited or unparseable: {result.get('quota_raw')})")

        # Subtask 2: Bandwidth limit (~5GB/month)
        # Virtualmin reports bandwidth in bytes. 5GB = 5368709120 bytes
        bw_val = result.get('bw_parsed')
        if bw_val is not None and isinstance(bw_val, (int, float)):
            bw_gb = None
            if bw_val > 1000000000:  # Likely bytes
                bw_gb = bw_val / (1024 * 1024 * 1024)
            elif bw_val > 1000000:  # Likely kB
                bw_gb = bw_val / (1024 * 1024)
            elif bw_val > 1000:  # Likely MB
                bw_gb = bw_val / 1024
            else:
                bw_gb = bw_val

            if bw_gb is not None and abs(bw_gb - expected_bw_gb) / expected_bw_gb <= 0.10:
                score += 25
                subscores["bandwidth_limit"] = True
                feedback_parts.append(f"Bandwidth limit set correctly (~{bw_gb:.1f}GB)")
            else:
                feedback_parts.append(f"Bandwidth limit incorrect: ~{bw_gb:.1f}GB (expected ~{expected_bw_gb}GB)")
        else:
            feedback_parts.append(f"Bandwidth limit not set (still unlimited: {result.get('bw_raw')})")

        # Subtask 3: Max mailboxes = 10
        max_mail = result.get('max_mailboxes_parsed')
        if max_mail is not None and isinstance(max_mail, (int, float)) and int(max_mail) == expected_max_mailboxes:
            score += 20
            subscores["max_mailboxes"] = True
            feedback_parts.append(f"Max mailboxes set to {int(max_mail)}")
        else:
            feedback_parts.append(f"Max mailboxes incorrect: {max_mail} (expected {expected_max_mailboxes})")

        # Subtask 4: Max aliases = 20
        max_alias = result.get('max_aliases_parsed')
        if max_alias is not None and isinstance(max_alias, (int, float)) and int(max_alias) == expected_max_aliases:
            score += 15
            subscores["max_aliases"] = True
            feedback_parts.append(f"Max aliases set to {int(max_alias)}")
        else:
            feedback_parts.append(f"Max aliases incorrect: {max_alias} (expected {expected_max_aliases})")

        # Subtask 5: Max databases = 3
        max_dbs = result.get('max_dbs_parsed')
        if max_dbs is not None and isinstance(max_dbs, (int, float)) and int(max_dbs) == expected_max_dbs:
            score += 15
            subscores["max_databases"] = True
            feedback_parts.append(f"Max databases set to {int(max_dbs)}")
        else:
            feedback_parts.append(f"Max databases incorrect: {max_dbs} (expected {expected_max_dbs})")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No limits configured",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
