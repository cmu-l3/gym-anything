#!/usr/bin/env python3
"""Verifier for setup_scheduled_backup task.

Scoring (100 points):
- Scheduled backup exists: prerequisite
- All 3 domains included: 25 points
- Destination is /backup/virtualmin/: 20 points
- Schedule is daily: 15 points
- Includes required features (dir, mail, mysql, dns): 25 points
- Retention set to 7: 15 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_setup_scheduled_backup(traj, env_info, task_info):
    """Verify scheduled backup was configured correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    expected_domains = set(metadata.get('target_domains', [
        'acmecorp.test', 'brightstar.test', 'greenvalley.test'
    ]))
    expected_retention = metadata.get('retention_count', 7)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/setup_scheduled_backup_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Prerequisite 1: A scheduled backup must exist
        if not result.get('backup_found'):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No scheduled backup found. The agent did not create a scheduled backup."
            }

        # Prerequisite 2: At least one required domain must be included (wrong-target check)
        domains_covered = 0
        domain_details = []
        if result.get('has_all_domains'):
            domains_covered = 3
            domain_details.append("All domains selected")
        else:
            if result.get('has_acmecorp'):
                domains_covered += 1
                domain_details.append("acmecorp.test")
            if result.get('has_brightstar'):
                domains_covered += 1
                domain_details.append("brightstar.test")
            if result.get('has_greenvalley'):
                domains_covered += 1
                domain_details.append("greenvalley.test")

        if domains_covered == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "CRITICAL: Backup does not include any of the required domains (acmecorp.test, brightstar.test, greenvalley.test)."
            }

        if domains_covered == 3:
            score += 25
            subscores["all_domains"] = True
            feedback_parts.append(f"All 3 domains included ({', '.join(domain_details)})")
        elif domains_covered > 0:
            partial = int(25 * domains_covered / 3)
            score += partial
            feedback_parts.append(f"Only {domains_covered}/3 domains included: {', '.join(domain_details)}")
        else:
            feedback_parts.append("No domains included in backup")

        # Subtask 2: Destination is /backup/virtualmin/ (20 points)
        if result.get('dest_is_local'):
            score += 20
            subscores["destination"] = True
            feedback_parts.append(f"Backup destination: {result.get('dest_path', '/backup/virtualmin/')}")
        else:
            # Check if backup dir at least exists (agent created it)
            if result.get('backup_dir_exists'):
                score += 5
                feedback_parts.append("Backup directory exists but not set as destination")
            else:
                feedback_parts.append("Backup destination is NOT /backup/virtualmin/")

        # Subtask 3: Daily schedule (15 points)
        if result.get('schedule_daily'):
            score += 15
            subscores["daily_schedule"] = True
            feedback_parts.append("Backup scheduled daily")
        else:
            feedback_parts.append("Backup is NOT scheduled daily")

        # Subtask 4: Required features (25 points, ~6 each)
        features_found = 0
        feature_details = []
        for feature, key in [
            ('home/dir', 'has_dir_feature'),
            ('mail', 'has_mail_feature'),
            ('mysql', 'has_mysql_feature'),
            ('dns', 'has_dns_feature'),
        ]:
            if result.get(key):
                features_found += 1
                feature_details.append(feature)

        if features_found == 4:
            score += 25
            subscores["features"] = True
            feedback_parts.append(f"All 4 required features included: {', '.join(feature_details)}")
        elif features_found > 0:
            partial = int(25 * features_found / 4)
            score += partial
            feedback_parts.append(f"{features_found}/4 features included: {', '.join(feature_details)}")
        else:
            feedback_parts.append("No required features found in backup config")

        # Subtask 5: Retention count = 7 (15 points)
        retention = result.get('retention_count', 0)
        if retention == expected_retention:
            score += 15
            subscores["retention"] = True
            feedback_parts.append(f"Retention set to {retention}")
        elif retention > 0:
            score += 7  # Some retention set, just not the right number
            feedback_parts.append(f"Retention set to {retention} (expected {expected_retention})")
        else:
            feedback_parts.append("No retention policy configured")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "Backup configuration incomplete",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
