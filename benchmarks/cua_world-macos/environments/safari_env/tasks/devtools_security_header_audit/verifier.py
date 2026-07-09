"""Verifier for the Safari port of devtools_security_header_audit.

Scoring (100 points, pass at 60):
- 25 pts  Criterion 1  Safari history shows each required site visited after
                       task start (5 pts × 5 sites, binary per site).
- 15 pts  Criterion 2  ~/Documents/security_audit_report.json exists, parses
                       as JSON, and was modified after task start.
                       Partial 8 (exists+valid but stale) / 3 (exists+invalid).
- 20 pts  Criterion 3  All 5 required sites appear as keys in the report
                       (4 pts × 5 sites, binary per site).
- 25 pts  Criterion 4  Each site entry has ≥3 non-empty header values
                       (5 pts × 5 sites; partial 2 if 1–2 headers present).
- 15 pts  Criterion 5  Header values look plausible: HSTS contains "max-age",
                       CSP contains a source directive. 8 + 7 split.

Partial-credit upper bound (no full credits on any criterion):
  0 + 8 + 0 + (2×5) + (4+3) = 25.  Pass threshold 60 > 25 → safe per Anti-
  Pattern 4.

Read pattern: copy_from_env(/tmp/devtools_security_header_audit_result.json,
local_tmp) — produced by export_result.sh.
"""

from __future__ import annotations

import json
import logging
import os
import tempfile
from typing import Any, Dict


logger = logging.getLogger(__name__)

REQUIRED_SITES = ["github.com", "gitlab.com", "bitbucket.org", "npmjs.com", "pypi.org"]
VISIT_KEYS = {
    "github.com": "github_visits",
    "gitlab.com": "gitlab_visits",
    "bitbucket.org": "bitbucket_visits",
    "npmjs.com": "npm_visits",
    "pypi.org": "pypi_visits",
}
PASS_THRESHOLD = 60
REMOTE_RESULT = "/tmp/devtools_security_header_audit_result.json"


def _empty_subscores() -> Dict[str, int]:
    return {
        "domain_history": 0,
        "report_file": 0,
        "sites_in_report": 0,
        "header_counts": 0,
        "header_validity": 0,
    }


def verify_devtools_security_header_audit(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    del traj, task_info
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"score": 0, "passed": False, "feedback": "env_info missing copy_from_env",
                "subscores": _empty_subscores()}

    # Pull the export-script JSON into a host-side temp file we can parse.
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        local_path = f.name
    try:
        try:
            copy_from_env(REMOTE_RESULT, local_path)
        except Exception as exc:
            logger.warning("copy_from_env failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Could not retrieve result file from sandbox: {exc}",
                    "subscores": _empty_subscores()}
        try:
            with open(local_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except Exception as exc:
            logger.warning("result JSON parse failed: %s", exc)
            return {"score": 0, "passed": False,
                    "feedback": f"Export produced unparseable JSON: {exc}",
                    "subscores": _empty_subscores()}
    finally:
        try:
            os.unlink(local_path)
        except Exception:
            pass

    # ---- Gate 1: no evidence of work at all ----
    visits = {site: int(data.get(VISIT_KEYS[site], 0) or 0) for site in REQUIRED_SITES}
    report_exists = bool(data.get("report_exists", False))
    if sum(visits.values()) == 0 and not report_exists:
        return {"score": 0, "passed": False,
                "feedback": "No evidence of task completion: no site visits after task start "
                            "and no report file at ~/Documents/security_audit_report.json.",
                "subscores": _empty_subscores()}

    # ---- Gate 2: strict wrong-target rejection (Pattern 2) ----
    # The export script emits `non_required_sites` (top-level keys in the
    # report that don't match any required site, e.g. ["google.com",
    # "facebook.com"]). If the report mentions non-required sites, no required
    # sites, AND no required-site browsing → wrong target. Per Pattern 2 in
    # 03_verification_patterns.md: immediate score=0, regardless of C2's
    # "file exists" credit.
    non_required = data.get("non_required_sites", []) or []
    if not isinstance(non_required, list):
        non_required = []
    sites_present_for_gate = data.get("sites_present", []) or []
    any_required_visited = any(v >= 1 for v in visits.values())
    if report_exists and non_required and not sites_present_for_gate \
            and not any_required_visited:
        return {"score": 0, "passed": False,
                "feedback": (f"Wrong target: report mentions {non_required} but none of the required "
                             f"sites {REQUIRED_SITES}, and no required-site visits occurred."),
                "subscores": _empty_subscores()}

    subscores = _empty_subscores()
    feedback: list[str] = []

    # ---- C1: Safari history (25 pts) ----
    visited, missing = [], []
    for site in REQUIRED_SITES:
        if visits[site] >= 1:
            subscores["domain_history"] += 5
            visited.append(site)
        else:
            missing.append(site)
    if subscores["domain_history"] == 25:
        feedback.append(f"All 5 sites visited after task start (+25)")
    elif subscores["domain_history"] > 0:
        feedback.append(
            f"Visited {len(visited)}/5 sites: {', '.join(visited)} (+{subscores['domain_history']}). "
            f"Missing: {', '.join(missing)}"
        )
    else:
        feedback.append("No required sites visited after task start (+0)")

    # ---- C2: report file (15 pts) ----
    valid_json = bool(data.get("report_valid_json", False))
    fresh = bool(data.get("report_fresh", False))
    if report_exists and valid_json and fresh:
        subscores["report_file"] = 15
        feedback.append("Report exists, fresh, valid JSON (+15)")
    elif report_exists and valid_json and not fresh:
        subscores["report_file"] = 8
        feedback.append("Report exists and is valid JSON but mtime predates task start (+8)")
    elif report_exists and not valid_json:
        subscores["report_file"] = 3
        feedback.append("Report file exists but does not parse as JSON (+3)")
    else:
        feedback.append("No report at ~/Documents/security_audit_report.json (+0)")

    # ---- C3: sites present (20 pts) ----
    # ADVERSARIAL HARDENING vs the source firefox verifier: per-site credit on
    # C3/C4/C5 is gated on whether the agent ACTUALLY visited that site after
    # task start (Safari History.db). This prevents an agent from fabricating a
    # plausible JSON without ever opening Web Inspector. Without this gate, a
    # perfect-JSON-no-visits agent would score 75 (15+20+25+15) and pass — see
    # Anti-Pattern 13 in 14_task_design_antipatterns.md.
    sites_present = data.get("sites_present", []) or []
    if not isinstance(sites_present, list):
        sites_present = []
    in_report, not_in_report, ungated = [], [], []
    for site in REQUIRED_SITES:
        if site not in sites_present:
            not_in_report.append(site)
            continue
        if visits[site] < 1:
            ungated.append(site)   # report mentions it but agent never visited
            continue
        subscores["sites_in_report"] += 4
        in_report.append(site)
    if subscores["sites_in_report"] == 20:
        feedback.append("All 5 sites appear as JSON keys AND were visited (+20)")
    elif subscores["sites_in_report"] > 0:
        msg = (f"{len(in_report)}/5 sites in report + visited: {', '.join(in_report)} "
               f"(+{subscores['sites_in_report']})")
        if ungated:
            msg += f". In report but NOT visited (ungated, +0): {', '.join(ungated)}"
        if not_in_report:
            msg += f". Missing from report: {', '.join(not_in_report)}"
        feedback.append(msg)
    else:
        if ungated:
            feedback.append(f"Report mentions sites but none were visited "
                            f"({', '.join(ungated)}) — fabrication suspected (+0)")
        else:
            feedback.append("No required sites appear as JSON keys (+0)")

    # ---- C4: header counts (25 pts; 5 per site, partial 2 if 1-2 headers) ----
    # Same per-site visit gate as C3 — only score sites the agent actually browsed.
    counts = data.get("per_site_header_count", {}) or {}
    if not isinstance(counts, dict):
        counts = {}
    good, few = [], []
    for site in REQUIRED_SITES:
        if visits[site] < 1:
            continue   # ungated: no visit, no header credit
        c = int(counts.get(site, 0) or 0)
        if c >= 3:
            subscores["header_counts"] += 5
            good.append(f"{site}({c})")
        elif c >= 1:
            subscores["header_counts"] += 2
            few.append(f"{site}({c})")
    if subscores["header_counts"] == 25:
        feedback.append(f"All sites have ≥3 headers AND were visited: {', '.join(good)} (+25)")
    elif subscores["header_counts"] > 0:
        parts = []
        if good: parts.append(f"good: {', '.join(good)}")
        if few: parts.append(f"few: {', '.join(few)}")
        feedback.append(f"Header counts (visited sites only) {'; '.join(parts)} (+{subscores['header_counts']})")
    else:
        feedback.append("No visited site has non-empty headers in the report (+0)")

    # ---- C5: header validity (15 pts; HSTS 8, CSP 7; both have 2-step partials) ----
    # Visit gate again — but use a single threshold: at least 1 visit anywhere
    # before we'll award C5 credit. (Per-site gating here would require parsing
    # the raw report; the visit count + plausibility flag is a coarser but
    # still adversarially-meaningful signal.)
    visited_any = any(v >= 1 for v in visits.values())
    hsts = int(data.get("hsts_looks_valid", 0) or 0)
    csp = int(data.get("csp_looks_valid", 0) or 0)
    bits = []
    if not visited_any:
        hsts = csp = 0   # zero out plausibility credit if agent never browsed
    if hsts >= 3:
        subscores["header_validity"] += 8; bits.append(f"HSTS valid on {hsts} sites")
    elif hsts >= 1:
        subscores["header_validity"] += 4; bits.append(f"HSTS valid on {hsts} site(s)")
    if csp >= 3:
        subscores["header_validity"] += 7; bits.append(f"CSP valid on {csp} sites")
    elif csp >= 1:
        subscores["header_validity"] += 3; bits.append(f"CSP valid on {csp} site(s)")
    if subscores["header_validity"] >= 12:
        feedback.append(f"Header values plausible: {', '.join(bits)} (+{subscores['header_validity']})")
    elif subscores["header_validity"] > 0:
        feedback.append(f"Some valid header values: {', '.join(bits)} (+{subscores['header_validity']})")
    else:
        feedback.append("HSTS/CSP values missing or implausible (HSTS needs 'max-age', "
                        "CSP needs a source directive) (+0)")

    total = sum(subscores.values())
    passed = total >= PASS_THRESHOLD
    if passed:
        feedback.insert(0, f"PASSED ({total}/100): security header audit complete. "
                           f"Total non-empty header values recorded: {data.get('total_non_empty_headers', 0)}.")
    else:
        feedback.insert(0, f"FAILED ({total}/100): audit incomplete (pass threshold {PASS_THRESHOLD}).")
    return {"score": total, "passed": passed, "feedback": " | ".join(feedback), "subscores": subscores}
