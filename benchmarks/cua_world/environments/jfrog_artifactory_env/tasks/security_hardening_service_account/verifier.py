import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_security_hardening_service_account(traj, env_info, task_info):
    """
    Verify all 5 SOC-2 compliance findings are remediated for Apex Healthcare:
      1. svc-deploy user exists, non-admin, correct apex-healthcare.com email (20 pts)
      2. ci-services group exists + svc-deploy is a member                   (20 pts)
      3. npm-builds local npm repo exists                                     (20 pts)
      4. svc-deploy-perms: ci-services has Deploy+Read on npm-builds          (20 pts)
      5. Access token "Service account token - Q1 2026 rotation" exists       (20 pts)
    Pass threshold: 60 / 100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/security_hardening_service_account_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {e}"}
    except Exception as e:
        logger.error(f"Error reading result: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # Criterion 1: svc-deploy user — non-admin, correct email (20 pts)
    # ------------------------------------------------------------------
    user = result.get('svc_deploy_user', {})
    if user.get('found'):
        is_admin = user.get('admin', True)
        email = user.get('email', '')
        email_ok = 'apex-healthcare.com' in email.lower()
        if not is_admin and email_ok:
            score += 20
            feedback.append("PASS: svc-deploy user exists, non-admin, correct apex-healthcare.com email")
        elif not is_admin:
            score += 15
            feedback.append(
                "PARTIAL: svc-deploy user exists and is non-admin but email not confirmed as apex-healthcare.com"
            )
        else:
            score += 8
            feedback.append("PARTIAL: svc-deploy user exists but still has admin privileges (must be non-admin)")
    else:
        feedback.append("FAIL: svc-deploy user not found")

    # ------------------------------------------------------------------
    # Criterion 2: ci-services group exists + svc-deploy is a member (20 pts)
    # ------------------------------------------------------------------
    group = result.get('ci_services_group', {})
    group_exists = group.get('found', False)
    # Check membership via group's userNames list
    member_found = 'svc-deploy' in (group.get('userNames') or [])
    # Also check user's groups list from criterion 1 result
    if not member_found:
        member_found = 'ci-services' in (user.get('groups') or [])

    if group_exists and member_found:
        score += 20
        feedback.append("PASS: ci-services group exists and svc-deploy is a member")
    elif group_exists:
        score += 10
        feedback.append("PARTIAL: ci-services group exists but svc-deploy group membership not confirmed")
    else:
        feedback.append("FAIL: ci-services group not found")

    # ------------------------------------------------------------------
    # Criterion 3: npm-builds — local npm repo (20 pts)
    # ------------------------------------------------------------------
    repo = result.get('npm_builds_repo', {})
    if (repo.get('found')
            and repo.get('type', '').upper() == 'LOCAL'
            and repo.get('packageType', '').lower() == 'npm'):
        score += 20
        feedback.append("PASS: npm-builds local npm repo exists")
    elif repo.get('found'):
        score += 5
        feedback.append(
            f"PARTIAL: npm-builds repo exists but is not a LOCAL npm repository "
            f"(type={repo.get('type','?')}, packageType={repo.get('packageType','?')})"
        )
    else:
        feedback.append("FAIL: npm-builds local npm repository not found")

    # ------------------------------------------------------------------
    # Criterion 4: svc-deploy-perms — ci-services d+r on npm-builds (20 pts)
    # ------------------------------------------------------------------
    perm = result.get('svc_deploy_perms', {})
    if perm.get('found'):
        repos_in_perm = perm.get('repositories', []) or []
        group_privs = perm.get('group_privs', {}) or {}
        ci_privs = group_privs.get('ci-services', [])
        repo_ok = 'npm-builds' in repos_in_perm
        has_deploy = 'd' in ci_privs
        has_read = 'r' in ci_privs
        if repo_ok and has_deploy and has_read:
            score += 20
            feedback.append("PASS: svc-deploy-perms grants ci-services Deploy+Read on npm-builds")
        elif repo_ok and (has_deploy or has_read):
            missing = 'Read' if has_deploy else 'Deploy'
            score += 10
            feedback.append(f"PARTIAL: svc-deploy-perms on npm-builds but ci-services missing {missing}")
        elif 'ci-services' in group_privs:
            score += 8
            feedback.append("PARTIAL: svc-deploy-perms assigns ci-services but npm-builds not in repo scope")
        else:
            score += 5
            feedback.append("PARTIAL: svc-deploy-perms permission exists but ci-services not assigned")
    else:
        feedback.append("FAIL: svc-deploy-perms permission target not found")

    # ------------------------------------------------------------------
    # Criterion 5: Access token "Service account token - Q1 2026 rotation" (20 pts)
    # ------------------------------------------------------------------
    if result.get('q1_rotation_token', {}).get('found'):
        score += 20
        feedback.append("PASS: Access token 'Service account token - Q1 2026 rotation' exists")
    else:
        feedback.append("FAIL: Access token with description 'Service account token - Q1 2026 rotation' not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
