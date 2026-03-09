import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_tradex_platform_setup(traj, env_info, task_info):
    """
    Verify all 6 TradeX Platform Artifactory deliverables for Nexus Financial:
      1. tradex-artifacts     — local Generic repo                     (15 pts)
      2. tradex-maven-releases — local Maven repo                       (15 pts)
      3. tradex-developers    — group exists                            (15 pts)
      4. tradex-dev-perms     — tradex-developers m+d+n+r on BOTH repos (20 pts)
      5. Access token "TradeX CI/CD production token" exists            (15 pts)
      6. commons-io-2.15.1.jar uploaded to tradex-artifacts             (20 pts)
    Pass threshold: 60 / 100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/tradex_platform_setup_result.json", tmp.name)
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
    # Criterion 1: tradex-artifacts — local Generic repo (15 pts)
    # ------------------------------------------------------------------
    r = result.get('tradex_artifacts', {})
    if r.get('found') and r.get('type', '').upper() == 'LOCAL' and r.get('packageType', '').lower() in ('generic', ''):
        score += 15
        feedback.append("PASS: tradex-artifacts local Generic repo exists")
    elif r.get('found') and r.get('type', '').upper() == 'LOCAL':
        score += 12
        feedback.append(
            f"PARTIAL: tradex-artifacts local repo exists "
            f"(packageType={r.get('packageType','?')}, expected Generic)"
        )
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: tradex-artifacts local Generic repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 2: tradex-maven-releases — local Maven repo (15 pts)
    # ------------------------------------------------------------------
    r = result.get('tradex_maven_releases', {})
    if r.get('found') and r.get('type', '').upper() == 'LOCAL' and r.get('packageType', '').lower() == 'maven':
        score += 15
        feedback.append("PASS: tradex-maven-releases local Maven repo exists")
    else:
        got = f"type={r.get('type','?')} pkg={r.get('packageType','?')}" if r.get('found') else "not found"
        feedback.append(f"FAIL: tradex-maven-releases local Maven repo not found ({got})")

    # ------------------------------------------------------------------
    # Criterion 3: tradex-developers group (15 pts)
    # ------------------------------------------------------------------
    if result.get('tradex_developers_group', {}).get('found'):
        score += 15
        feedback.append("PASS: tradex-developers group exists")
    else:
        feedback.append("FAIL: tradex-developers group not found")

    # ------------------------------------------------------------------
    # Criterion 4: tradex-dev-perms — tradex-developers Admin+Deploy+Annotate+Read on BOTH repos (20 pts)
    # ------------------------------------------------------------------
    perm = result.get('tradex_dev_perms', {})
    if perm.get('found'):
        repos_in_perm = perm.get('repositories', []) or []
        group_privs = perm.get('group_privs', {}) or {}
        td_privs = group_privs.get('tradex-developers', [])

        has_artifacts = 'tradex-artifacts' in repos_in_perm
        has_maven = 'tradex-maven-releases' in repos_in_perm
        both_repos = has_artifacts and has_maven

        has_manage = 'm' in td_privs
        has_deploy = 'd' in td_privs
        has_annotate = 'n' in td_privs
        has_read = 'r' in td_privs
        all_privs = has_manage and has_deploy and has_annotate and has_read

        if both_repos and all_privs:
            score += 20
            feedback.append(
                "PASS: tradex-dev-perms grants tradex-developers Admin+Deploy+Annotate+Read "
                "on both tradex-artifacts and tradex-maven-releases"
            )
        elif both_repos and (has_deploy and has_read):
            score += 14
            missing = []
            if not has_manage:
                missing.append('Admin(m)')
            if not has_annotate:
                missing.append('Annotate(n)')
            feedback.append(
                f"PARTIAL: tradex-dev-perms on both repos but tradex-developers missing {', '.join(missing)}"
            )
        elif (has_artifacts or has_maven) and (has_deploy and has_read):
            score += 10
            missing_repo = 'tradex-maven-releases' if has_artifacts else 'tradex-artifacts'
            feedback.append(
                f"PARTIAL: tradex-dev-perms grants tradex-developers Deploy+Read "
                f"but {missing_repo} not in scope"
            )
        elif 'tradex-developers' in group_privs:
            score += 6
            feedback.append("PARTIAL: tradex-dev-perms assigns tradex-developers but repos/privileges incomplete")
        else:
            score += 4
            feedback.append("PARTIAL: tradex-dev-perms permission exists but tradex-developers not assigned")
    else:
        feedback.append("FAIL: tradex-dev-perms permission target not found")

    # ------------------------------------------------------------------
    # Criterion 5: Access token "TradeX CI/CD production token" (15 pts)
    # ------------------------------------------------------------------
    if result.get('tradex_cicd_token', {}).get('found'):
        score += 15
        feedback.append("PASS: Access token 'TradeX CI/CD production token' exists")
    else:
        feedback.append("FAIL: Access token 'TradeX CI/CD production token' not found")

    # ------------------------------------------------------------------
    # Criterion 6: commons-io-2.15.1.jar uploaded to tradex-artifacts (20 pts)
    # ------------------------------------------------------------------
    artifact = result.get('commons_io_artifact', {})
    if artifact.get('found'):
        score += 20
        feedback.append("PASS: commons-io-2.15.1.jar artifact found in tradex-artifacts repository")
    else:
        if result.get('tradex_artifacts', {}).get('found'):
            feedback.append(
                "FAIL: commons-io-2.15.1.jar not found in tradex-artifacts (repo exists but artifact not uploaded)"
            )
        else:
            feedback.append("FAIL: commons-io-2.15.1.jar not found (tradex-artifacts repo does not exist)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
