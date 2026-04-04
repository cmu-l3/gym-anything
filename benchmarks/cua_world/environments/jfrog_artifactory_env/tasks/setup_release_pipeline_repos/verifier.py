import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_setup_release_pipeline_repos(traj, env_info, task_info):
    """
    Verify all 5 artifact management requirements for the Meridian Payments
    microservices release pipeline:
      1. ms-releases       — local Maven repo                    (20 pts)
      2. maven-central-proxy — remote Maven repo + Maven Central URL (20 pts)
      3. ms-build-virtual  — virtual Maven repo with both repos  (20 pts)
      4. build-engineers   — group exists                        (20 pts)
      5. build-access      — permission: build-engineers d+r on ms-releases (20 pts)
    Pass threshold: 60 / 100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/setup_release_pipeline_repos_result.json", tmp.name)
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
    # Criterion 1: ms-releases — local Maven repo (20 pts)
    # ------------------------------------------------------------------
    r = result.get('ms_releases', {})
    if r.get('found') and r.get('type', '').upper() == 'LOCAL' and r.get('packageType', '').lower() == 'maven':
        score += 20
        feedback.append("PASS: ms-releases local Maven repo exists")
    elif r.get('found') and r.get('type', '').upper() == 'LOCAL':
        score += 12
        feedback.append(
            f"PARTIAL: ms-releases local repo exists (packageType={r.get('packageType','?')}, expected maven)"
        )
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: ms-releases local Maven repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 2: maven-central-proxy — remote Maven repo + URL (20 pts)
    # ------------------------------------------------------------------
    r = result.get('maven_central_proxy', {})
    if r.get('found') and r.get('type', '').upper() == 'REMOTE' and r.get('packageType', '').lower() == 'maven':
        remote_url = r.get('url', '')
        if remote_url and 'maven.org' in remote_url:
            score += 20
            feedback.append("PASS: maven-central-proxy remote Maven repo with correct Maven Central URL")
        else:
            score += 15
            feedback.append(
                f"PARTIAL: maven-central-proxy remote Maven repo exists "
                f"(remote URL not confirmed as Maven Central: '{remote_url}')"
            )
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: maven-central-proxy remote Maven repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 3: ms-build-virtual — virtual Maven repo containing both repos (20 pts)
    # ------------------------------------------------------------------
    r = result.get('ms_build_virtual', {})
    if r.get('found') and r.get('type', '').upper() == 'VIRTUAL' and r.get('packageType', '').lower() == 'maven':
        included = [x.lower() for x in (r.get('repositories') or []) if isinstance(x, str)]
        has_releases = 'ms-releases' in included
        has_proxy = 'maven-central-proxy' in included
        if has_releases and has_proxy:
            score += 20
            feedback.append("PASS: ms-build-virtual virtual Maven repo includes both ms-releases and maven-central-proxy")
        elif has_releases or has_proxy:
            score += 10
            missing = 'maven-central-proxy' if has_releases else 'ms-releases'
            feedback.append(f"PARTIAL: ms-build-virtual exists but missing {missing}")
        else:
            score += 10
            feedback.append("PARTIAL: ms-build-virtual virtual Maven repo exists (could not verify included repo list)")
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: ms-build-virtual virtual Maven repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 4: build-engineers group (20 pts)
    # ------------------------------------------------------------------
    if result.get('build_engineers_group', {}).get('found'):
        score += 20
        feedback.append("PASS: build-engineers group exists")
    else:
        feedback.append("FAIL: build-engineers group not found")

    # ------------------------------------------------------------------
    # Criterion 5: build-access permission — build-engineers d+r on ms-releases (20 pts)
    # ------------------------------------------------------------------
    perm = result.get('build_access_permission', {})
    if perm.get('found'):
        repos_in_perm = perm.get('repositories', []) or []
        group_privs = perm.get('group_privs', {}) or {}
        bg_privs = group_privs.get('build-engineers', [])
        repo_ok = 'ms-releases' in repos_in_perm
        has_deploy = 'd' in bg_privs
        has_read = 'r' in bg_privs
        if repo_ok and has_deploy and has_read:
            score += 20
            feedback.append("PASS: build-access grants build-engineers Deploy+Read on ms-releases")
        elif repo_ok and (has_deploy or has_read):
            missing_priv = 'Read' if has_deploy else 'Deploy'
            score += 10
            feedback.append(
                f"PARTIAL: build-access on ms-releases but build-engineers missing {missing_priv} privilege"
            )
        elif 'build-engineers' in group_privs:
            score += 8
            feedback.append("PARTIAL: build-access assigns build-engineers but ms-releases not in scope")
        else:
            score += 5
            feedback.append("PARTIAL: build-access permission exists but build-engineers not assigned")
    else:
        feedback.append("FAIL: build-access permission target not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
