"""
Verifier for devtools_security_header_audit task.

Scoring breakdown (100 points total):
- Criterion 1: All 5 domains visited in browser history (25 pts, 5 per domain)
- Criterion 2: JSON report file exists, is fresh, and valid JSON (15 pts)
- Criterion 3: All 5 required sites present as keys in the JSON (20 pts, 4 per site)
- Criterion 4: Each site has ≥3 non-empty header fields recorded (25 pts, 5 per site)
- Criterion 5: Header value plausibility — HSTS has "max-age", CSP has source directives (15 pts)

Pass threshold: 60/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

REQUIRED_SITES = ["github.com", "gitlab.com", "bitbucket.org", "npmjs.com", "pypi.org"]
SITE_VISIT_KEYS = {
    "github.com": "github_visits",
    "gitlab.com": "gitlab_visits",
    "bitbucket.org": "bitbucket_visits",
    "npmjs.com": "npm_visits",
    "pypi.org": "pypi_visits",
}


def verify_devtools_security_header_audit(traj, env_info, task_info):
    """
    Verify that the agent used Firefox DevTools to audit HTTP security headers
    on 5 developer platform sites and saved a JSON report.
    """
    copy_from_env = env_info.get("copy_from_env")

    result_json_path = "/tmp/devtools_security_header_audit_result.json"

    # Copy result from VM
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(result_json_path, tmp_path)
    except Exception as e:
        logger.warning(f"Could not copy result file: {e}")
        return {
            "score": 0,
            "passed": False,
            "feedback": "Could not retrieve result file from environment. Export script may have failed.",
            "subscores": {},
        }

    try:
        with open(tmp_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not parse result JSON: {e}")
        return {
            "score": 0,
            "passed": False,
            "feedback": "Could not parse result JSON from environment.",
            "subscores": {},
        }
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    subscores = {}
    feedback_parts = []

    # --- Gate check: no evidence of work ---
    github_visits = int(data.get("github_visits", 0) or 0)
    gitlab_visits = int(data.get("gitlab_visits", 0) or 0)
    bitbucket_visits = int(data.get("bitbucket_visits", 0) or 0)
    npm_visits = int(data.get("npm_visits", 0) or 0)
    pypi_visits = int(data.get("pypi_visits", 0) or 0)
    report_exists = bool(data.get("report_exists", False))

    total_visits = github_visits + gitlab_visits + bitbucket_visits + npm_visits + pypi_visits

    if total_visits == 0 and not report_exists:
        return {
            "score": 0,
            "passed": False,
            "feedback": "No evidence of task completion: no site visits and no report file found.",
            "subscores": {
                "domain_history": 0,
                "report_file": 0,
                "sites_in_report": 0,
                "header_counts": 0,
                "header_validity": 0,
            },
        }

    # --- Criterion 1: Domain history (25 pts, 5 per domain) ---
    visit_counts = {
        "github.com": github_visits,
        "gitlab.com": gitlab_visits,
        "bitbucket.org": bitbucket_visits,
        "npmjs.com": npm_visits,
        "pypi.org": pypi_visits,
    }
    domain_score = 0
    visited_domains = []
    missing_domains = []
    for site in REQUIRED_SITES:
        cnt = visit_counts.get(site, 0)
        if cnt >= 1:
            domain_score += 5
            visited_domains.append(site)
        else:
            missing_domains.append(site)

    subscores["domain_history"] = domain_score
    if domain_score == 25:
        feedback_parts.append(f"All 5 sites visited in history (+{domain_score})")
    elif domain_score > 0:
        feedback_parts.append(
            f"Visited {len(visited_domains)}/5 sites: {', '.join(visited_domains)} (+{domain_score}). "
            f"Missing: {', '.join(missing_domains)}"
        )
    else:
        feedback_parts.append("No required sites found in browser history after task start (+0)")

    # --- Criterion 2: Report file (15 pts) ---
    report_valid_json = bool(data.get("report_valid_json", False))
    report_fresh = bool(data.get("report_fresh", False))

    report_score = 0
    if report_exists and report_valid_json and report_fresh:
        report_score = 15
        feedback_parts.append("Security audit report exists, is fresh and valid JSON (+15)")
    elif report_exists and report_valid_json and not report_fresh:
        report_score = 8
        feedback_parts.append("Report exists and is valid JSON but was not created during this task (+8)")
    elif report_exists and not report_valid_json:
        report_score = 3
        feedback_parts.append("Report file exists but contains invalid JSON (+3)")
    else:
        feedback_parts.append("No security audit report found at ~/Documents/security_audit_report.json (+0)")

    subscores["report_file"] = report_score

    # --- Criterion 3: Sites present in report (20 pts, 4 per site) ---
    sites_present = data.get("sites_present", [])
    if not isinstance(sites_present, list):
        sites_present = []

    sites_score = 0
    sites_in_report = []
    sites_missing = []
    for site in REQUIRED_SITES:
        if site in sites_present:
            sites_score += 4
            sites_in_report.append(site)
        else:
            sites_missing.append(site)

    subscores["sites_in_report"] = sites_score
    if sites_score == 20:
        feedback_parts.append(f"All 5 sites present as keys in the JSON report (+{sites_score})")
    elif sites_score > 0:
        feedback_parts.append(
            f"{len(sites_in_report)}/5 sites in report: {', '.join(sites_in_report)} (+{sites_score}). "
            f"Missing: {', '.join(sites_missing)}"
        )
    else:
        if report_exists:
            feedback_parts.append("Report exists but no required site keys found (+0)")
        else:
            feedback_parts.append("No sites recorded in report (+0)")

    # --- Criterion 4: Header counts per site (25 pts, 5 per site) ---
    per_site_header_count = data.get("per_site_header_count", {})
    if not isinstance(per_site_header_count, dict):
        per_site_header_count = {}

    header_count_score = 0
    sites_with_good_headers = []
    sites_with_few_headers = []
    for site in REQUIRED_SITES:
        count = int(per_site_header_count.get(site, 0) or 0)
        if count >= 3:
            header_count_score += 5
            sites_with_good_headers.append(f"{site}({count})")
        elif count >= 1:
            header_count_score += 2
            sites_with_few_headers.append(f"{site}({count})")

    subscores["header_counts"] = header_count_score
    if header_count_score == 25:
        feedback_parts.append(
            f"All sites have ≥3 security headers recorded: {', '.join(sites_with_good_headers)} (+{header_count_score})"
        )
    elif header_count_score > 0:
        detail_parts = []
        if sites_with_good_headers:
            detail_parts.append(f"good: {', '.join(sites_with_good_headers)}")
        if sites_with_few_headers:
            detail_parts.append(f"few: {', '.join(sites_with_few_headers)}")
        feedback_parts.append(
            f"Header counts: {'; '.join(detail_parts)} (+{header_count_score})"
        )
    else:
        feedback_parts.append("No sites have ≥3 security headers recorded in report (+0)")

    # --- Criterion 5: Header value plausibility (15 pts) ---
    hsts_valid = int(data.get("hsts_looks_valid", 0) or 0)
    csp_valid = int(data.get("csp_looks_valid", 0) or 0)
    total_non_empty = int(data.get("total_non_empty_headers", 0) or 0)

    header_validity_score = 0
    validity_details = []

    # HSTS validity (up to 8 pts)
    if hsts_valid >= 3:
        header_validity_score += 8
        validity_details.append(f"HSTS valid on {hsts_valid} sites")
    elif hsts_valid >= 1:
        header_validity_score += 4
        validity_details.append(f"HSTS valid on {hsts_valid} site(s)")

    # CSP validity (up to 7 pts)
    if csp_valid >= 3:
        header_validity_score += 7
        validity_details.append(f"CSP valid on {csp_valid} sites")
    elif csp_valid >= 1:
        header_validity_score += 3
        validity_details.append(f"CSP valid on {csp_valid} site(s)")

    subscores["header_validity"] = header_validity_score
    if header_validity_score >= 12:
        feedback_parts.append(
            f"Header values are plausible: {', '.join(validity_details)} (+{header_validity_score})"
        )
    elif header_validity_score > 0:
        feedback_parts.append(
            f"Some valid header values: {', '.join(validity_details)} (+{header_validity_score})"
        )
    else:
        feedback_parts.append(
            "HSTS and CSP header values appear missing or implausible — "
            "ensure Strict-Transport-Security has 'max-age' and CSP has source directives (+0)"
        )

    # --- Total score ---
    total_score = sum(subscores.values())
    passed = total_score >= 60

    if passed:
        feedback_parts.insert(
            0,
            f"PASSED ({total_score}/100): Security header audit completed successfully. "
            f"Total non-empty headers recorded: {total_non_empty}.",
        )
    else:
        feedback_parts.insert(
            0,
            f"FAILED ({total_score}/100): Security header audit incomplete. "
            f"Tip: Use Firefox DevTools Network tab, reload each page, "
            f"inspect response headers and record HSTS/CSP/X-Content-Type-Options/X-Frame-Options values.",
        )

    return {
        "score": total_score,
        "passed": passed,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
