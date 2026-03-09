import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_federated_npm_registry_setup(traj, env_info, task_info):
    """
    Verify all 6 npm registry infrastructure requirements for GlobalRetail:
      1. npm-internal  — local npm repo                              (20 pts)
      2. npmjs-mirror  — remote npm repo + registry.npmjs.org URL   (15 pts)
      3. npm-all       — virtual npm repo with both repos included  (15 pts)
      4. frontend-lead — non-admin user, correct globalretail.com email (15 pts)
      5. frontend-developers group exists + frontend-lead is member (15 pts)
      6. frontend-npm-perms — frontend-developers d+r on npm-internal (20 pts)
    Pass threshold: 60 / 100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/federated_npm_registry_setup_result.json", tmp.name)
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
    # Criterion 1: npm-internal — local npm repo (20 pts)
    # ------------------------------------------------------------------
    r = result.get('npm_internal', {})
    if r.get('found') and r.get('type', '').upper() == 'LOCAL' and r.get('packageType', '').lower() == 'npm':
        score += 20
        feedback.append("PASS: npm-internal local npm repo exists")
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: npm-internal local npm repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 2: npmjs-mirror — remote npm repo + URL check (15 pts)
    # ------------------------------------------------------------------
    r = result.get('npmjs_mirror', {})
    if r.get('found') and r.get('type', '').upper() == 'REMOTE' and r.get('packageType', '').lower() == 'npm':
        remote_url = r.get('url', '')
        if remote_url and 'registry.npmjs.org' in remote_url:
            score += 15
            feedback.append("PASS: npmjs-mirror remote npm repo with correct registry.npmjs.org URL")
        else:
            score += 10
            feedback.append(
                f"PARTIAL: npmjs-mirror remote npm repo exists "
                f"(registry.npmjs.org URL not confirmed: '{remote_url}')"
            )
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: npmjs-mirror remote npm repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 3: npm-all — virtual npm repo containing both repos (15 pts)
    # ------------------------------------------------------------------
    r = result.get('npm_all', {})
    if r.get('found') and r.get('type', '').upper() == 'VIRTUAL' and r.get('packageType', '').lower() == 'npm':
        included = [x.lower() for x in (r.get('repositories') or []) if isinstance(x, str)]
        has_internal = 'npm-internal' in included
        has_mirror = 'npmjs-mirror' in included
        if has_internal and has_mirror:
            score += 15
            feedback.append("PASS: npm-all virtual npm repo includes npm-internal and npmjs-mirror")
        elif has_internal or has_mirror:
            missing = 'npmjs-mirror' if has_internal else 'npm-internal'
            score += 8
            feedback.append(f"PARTIAL: npm-all virtual npm repo exists but missing {missing}")
        else:
            score += 8
            feedback.append("PARTIAL: npm-all virtual npm repo exists (could not verify included repos)")
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: npm-all virtual npm repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 4: frontend-lead — non-admin user, correct email (15 pts)
    # ------------------------------------------------------------------
    user = result.get('frontend_lead_user', {})
    if user.get('found'):
        is_admin = user.get('admin', True)
        email = user.get('email', '')
        email_ok = 'globalretail.com' in email.lower()
        if not is_admin and email_ok:
            score += 15
            feedback.append("PASS: frontend-lead user exists, non-admin, correct globalretail.com email")
        elif not is_admin:
            score += 10
            feedback.append(
                "PARTIAL: frontend-lead user exists and non-admin but email not confirmed as globalretail.com"
            )
        else:
            score += 5
            feedback.append("PARTIAL: frontend-lead user exists but has admin privileges (must be non-admin)")
    else:
        feedback.append("FAIL: frontend-lead user not found")

    # ------------------------------------------------------------------
    # Criterion 5: frontend-developers group + frontend-lead is a member (15 pts)
    # ------------------------------------------------------------------
    group = result.get('frontend_developers_group', {})
    group_exists = group.get('found', False)
    member_found = 'frontend-lead' in (group.get('userNames') or [])
    if not member_found:
        member_found = 'frontend-developers' in (user.get('groups') or [])

    if group_exists and member_found:
        score += 15
        feedback.append("PASS: frontend-developers group exists and frontend-lead is a member")
    elif group_exists:
        score += 8
        feedback.append("PARTIAL: frontend-developers group exists but frontend-lead membership not confirmed")
    else:
        feedback.append("FAIL: frontend-developers group not found")

    # ------------------------------------------------------------------
    # Criterion 6: frontend-npm-perms — frontend-developers d+r on npm-internal (20 pts)
    # ------------------------------------------------------------------
    perm = result.get('frontend_npm_perms', {})
    if perm.get('found'):
        repos_in_perm = perm.get('repositories', []) or []
        group_privs = perm.get('group_privs', {}) or {}
        fd_privs = group_privs.get('frontend-developers', [])
        repo_ok = 'npm-internal' in repos_in_perm
        has_deploy = 'd' in fd_privs
        has_read = 'r' in fd_privs
        if repo_ok and has_deploy and has_read:
            score += 20
            feedback.append("PASS: frontend-npm-perms grants frontend-developers Deploy+Read on npm-internal")
        elif repo_ok and (has_deploy or has_read):
            missing = 'Read' if has_deploy else 'Deploy'
            score += 10
            feedback.append(
                f"PARTIAL: frontend-npm-perms on npm-internal but missing {missing} for frontend-developers"
            )
        elif 'frontend-developers' in group_privs:
            score += 8
            feedback.append("PARTIAL: frontend-npm-perms assigns frontend-developers but npm-internal not in scope")
        else:
            score += 5
            feedback.append("PARTIAL: frontend-npm-perms exists but frontend-developers not assigned")
    else:
        feedback.append("FAIL: frontend-npm-perms permission target not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
