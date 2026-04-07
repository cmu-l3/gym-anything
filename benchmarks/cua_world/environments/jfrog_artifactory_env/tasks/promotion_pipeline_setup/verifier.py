import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_promotion_pipeline_setup(traj, env_info, task_info):
    """
    Stub verifier for the promotion_pipeline_setup task.
    Primary verification is done via vlm_checklist_verifier.
    This programmatic verifier reads the export_result.sh output
    and performs basic existence checks.

    Criteria (100 pts total, pass at 50):
      1. Repository infrastructure — 5 repos exist with correct types  (25 pts)
      2. Virtual repo config — aggregation, order, deploy target       (15 pts)
      3. User & group setup — 2 groups + 1 user authenticable          (15 pts)
      4. Permission targets — 2 permissions exist                      (15 pts)
      5. Artifact pipeline — artifact in dev, staging, prod            (15 pts)
      6. System config — SMTP configured + anonymous access disabled   (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/promotion_pipeline_setup_result.json", tmp.name)
            with open(tmp.name) as f:
                data = json.load(f)
        finally:
            os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0,
                "feedback": f"Invalid JSON in result file: {e}"}
    except Exception as e:
        logger.error(f"Error reading result: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # 1. Repository infrastructure (25 pts)
    # ------------------------------------------------------------------
    repo_score = 0
    for slug, expected_type in [
        ("medsecure_dev", "LOCAL"),
        ("medsecure_staging", "LOCAL"),
        ("medsecure_prod", "LOCAL"),
    ]:
        r = data.get(slug, {})
        if r.get("found") and r.get("type", "").upper() == expected_type:
            if r.get("packageType", "").lower() == "maven":
                repo_score += 5
            else:
                repo_score += 3
        elif r.get("found"):
            repo_score += 2

    r = data.get("maven_central_proxy", {})
    if r.get("found") and r.get("type", "").upper() == "REMOTE":
        repo_score += 5
    elif r.get("found"):
        repo_score += 2

    r = data.get("medsecure_maven_all", {})
    if r.get("found") and r.get("type", "").upper() == "VIRTUAL":
        repo_score += 5
    elif r.get("found"):
        repo_score += 2

    repo_score = min(repo_score, 25)
    score += repo_score
    feedback.append(f"repos: {repo_score}/25")

    # ------------------------------------------------------------------
    # 2. Virtual repo configuration (15 pts)
    # ------------------------------------------------------------------
    virt_score = 0
    virt = data.get("medsecure_maven_all", {})
    if virt.get("found"):
        repos_in = virt.get("repositories", [])
        expected = {"medsecure-prod", "medsecure-staging", "medsecure-dev",
                    "maven-central-proxy"}
        if set(repos_in) >= expected:
            virt_score += 5
        elif len(set(repos_in) & expected) >= 2:
            virt_score += 2

        expected_order = ["medsecure-prod", "medsecure-staging",
                          "medsecure-dev", "maven-central-proxy"]
        if repos_in == expected_order:
            virt_score += 5
        elif repos_in and repos_in[0] == "medsecure-prod":
            virt_score += 2

        if virt.get("defaultDeploymentRepo") == "medsecure-dev":
            virt_score += 5
        elif virt.get("defaultDeploymentRepo"):
            virt_score += 2

    score += virt_score
    feedback.append(f"virtual: {virt_score}/15")

    # ------------------------------------------------------------------
    # 3. User & group setup (15 pts)
    # ------------------------------------------------------------------
    ug_score = 0
    if data.get("platform_engineers_group", {}).get("found"):
        ug_score += 5
    if data.get("qa_team_group", {}).get("found"):
        ug_score += 5
    if data.get("eng_sarah_user", {}).get("auth_works"):
        ug_score += 5
    score += ug_score
    feedback.append(f"users_groups: {ug_score}/15")

    # ------------------------------------------------------------------
    # 4. Permission targets (15 pts)
    # ------------------------------------------------------------------
    perm_score = 0
    dp = data.get("deploy_perms", {})
    if dp.get("found"):
        perm_score += 4
        gp = dp.get("group_privs", {})
        pe_privs = gp.get("platform-engineers", [])
        if "d" in pe_privs and "r" in pe_privs:
            perm_score += 4

    qp = data.get("qa_perms", {})
    if qp.get("found"):
        perm_score += 4
        gp = qp.get("group_privs", {})
        qt_privs = gp.get("qa-team", [])
        if "r" in qt_privs:
            perm_score += 3

    perm_score = min(perm_score, 15)
    score += perm_score
    feedback.append(f"permissions: {perm_score}/15")

    # ------------------------------------------------------------------
    # 5. Artifact pipeline (15 pts)
    # ------------------------------------------------------------------
    art_score = 0
    for slug in ("artifact_in_medsecure_dev",
                 "artifact_in_medsecure_staging",
                 "artifact_in_medsecure_prod"):
        if data.get(slug, {}).get("found"):
            art_score += 5
    score += art_score
    feedback.append(f"artifacts: {art_score}/15")

    # ------------------------------------------------------------------
    # 6. System configuration (15 pts)
    # ------------------------------------------------------------------
    sys_score = 0
    smtp = data.get("smtp_config", {})
    if smtp.get("found") and smtp.get("host"):
        sys_score += 4
        if smtp.get("tls"):
            sys_score += 2
        if smtp.get("port") == 587:
            sys_score += 2

    anon = data.get("anon_access_enabled")
    if anon is False:
        sys_score += 7
    sys_score = min(sys_score, 15)
    score += sys_score
    feedback.append(f"system: {sys_score}/15")

    # ------------------------------------------------------------------
    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": f"Total: {score}/100 (pass=50). " + " | ".join(feedback),
    }
