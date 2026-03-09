import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_multi_team_pypi_infrastructure(traj, env_info, task_info):
    """
    Verify all 6 PyPI infrastructure requirements for DataCore Technologies:
      1. pypi-datascience — local PyPI repo                   (12 pts)
      2. pypi-mlops       — local PyPI repo                   (12 pts)
      3. pypi-org-proxy   — remote PyPI repo + pypi.org URL   (14 pts)
      4. pypi-all         — virtual PyPI repo with all 3      (12 pts)
      5. data-scientists group (10 pts) + ds-pypi-perms (15 pts) = 25 pts
      6. mlops-engineers group (10 pts) + mlops-pypi-perms (15 pts) = 25 pts
    Total: 12+12+14+12+25+25 = 100
    Pass threshold: 60 / 100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/multi_team_pypi_infrastructure_result.json", tmp.name)
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

    def check_perm(key, expected_group, expected_repo, max_pts=15):
        """Returns (pts, feedback_str) for a permission target check."""
        perm = result.get(key, {})
        if not perm.get('found'):
            return 0, f"FAIL: {key} permission target not found"
        repos_in_perm = perm.get('repositories', []) or []
        group_privs = perm.get('group_privs', {}) or {}
        grp_privs = group_privs.get(expected_group, [])
        repo_ok = expected_repo in repos_in_perm
        has_deploy = 'd' in grp_privs
        has_read = 'r' in grp_privs
        if repo_ok and has_deploy and has_read:
            return max_pts, f"PASS: {key} grants {expected_group} Deploy+Read on {expected_repo}"
        elif repo_ok and (has_deploy or has_read):
            missing = 'Read' if has_deploy else 'Deploy'
            return 8, f"PARTIAL: {key} on {expected_repo} but {expected_group} missing {missing}"
        elif expected_group in group_privs:
            return 6, f"PARTIAL: {key} assigns {expected_group} but {expected_repo} not in scope"
        else:
            return 4, f"PARTIAL: {key} permission exists but {expected_group} not assigned"

    # ------------------------------------------------------------------
    # Criterion 1: pypi-datascience — local PyPI repo (12 pts)
    # ------------------------------------------------------------------
    r = result.get('pypi_datascience', {})
    if r.get('found') and r.get('type', '').upper() == 'LOCAL' and r.get('packageType', '').lower() == 'pypi':
        score += 12
        feedback.append("PASS: pypi-datascience local PyPI repo exists")
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: pypi-datascience local PyPI repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 2: pypi-mlops — local PyPI repo (12 pts)
    # ------------------------------------------------------------------
    r = result.get('pypi_mlops', {})
    if r.get('found') and r.get('type', '').upper() == 'LOCAL' and r.get('packageType', '').lower() == 'pypi':
        score += 12
        feedback.append("PASS: pypi-mlops local PyPI repo exists")
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: pypi-mlops local PyPI repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 3: pypi-org-proxy — remote PyPI repo + pypi.org URL (14 pts)
    # ------------------------------------------------------------------
    r = result.get('pypi_org_proxy', {})
    if r.get('found') and r.get('type', '').upper() == 'REMOTE' and r.get('packageType', '').lower() == 'pypi':
        remote_url = r.get('url', '')
        if remote_url and 'pypi.org' in remote_url:
            score += 14
            feedback.append("PASS: pypi-org-proxy remote PyPI repo with correct pypi.org URL")
        else:
            score += 10
            feedback.append(
                f"PARTIAL: pypi-org-proxy remote PyPI repo exists "
                f"(pypi.org URL not confirmed: '{remote_url}')"
            )
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: pypi-org-proxy remote PyPI repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 4: pypi-all — virtual PyPI repo with all 3 sources (12 pts)
    # ------------------------------------------------------------------
    r = result.get('pypi_all', {})
    if r.get('found') and r.get('type', '').upper() == 'VIRTUAL' and r.get('packageType', '').lower() == 'pypi':
        included = [x.lower() for x in (r.get('repositories') or []) if isinstance(x, str)]
        required = {'pypi-datascience', 'pypi-mlops', 'pypi-org-proxy'}
        present = required.intersection(set(included))
        if len(present) == 3:
            score += 12
            feedback.append("PASS: pypi-all virtual PyPI repo includes all 3 required repositories")
        elif len(present) == 2:
            missing = required - present
            score += 8
            feedback.append(f"PARTIAL: pypi-all virtual repo exists but missing {missing}")
        elif len(present) == 1:
            score += 4
            feedback.append(f"PARTIAL: pypi-all virtual repo exists but only includes {present}")
        else:
            score += 6
            feedback.append("PARTIAL: pypi-all virtual PyPI repo exists (could not verify included repos)")
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: pypi-all virtual PyPI repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 5: data-scientists group (10 pts) + ds-pypi-perms (15 pts)
    # ------------------------------------------------------------------
    if result.get('data_scientists_group', {}).get('found'):
        score += 10
        feedback.append("PASS: data-scientists group exists")
    else:
        feedback.append("FAIL: data-scientists group not found")

    pts, msg = check_perm('ds_pypi_perms', 'data-scientists', 'pypi-datascience')
    score += pts
    feedback.append(msg)

    # ------------------------------------------------------------------
    # Criterion 6: mlops-engineers group (10 pts) + mlops-pypi-perms (15 pts)
    # ------------------------------------------------------------------
    if result.get('mlops_engineers_group', {}).get('found'):
        score += 10
        feedback.append("PASS: mlops-engineers group exists")
    else:
        feedback.append("FAIL: mlops-engineers group not found")

    pts, msg = check_perm('mlops_pypi_perms', 'mlops-engineers', 'pypi-mlops')
    score += pts
    feedback.append(msg)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
