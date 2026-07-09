"""Verifier for sec_edgar_cybersecurity_disclosure_audit."""

from __future__ import annotations

import json
import os
import tempfile

REMOTE_RESULT = "/tmp/edgar_cybersecurity_audit_result.json"

REQUIRED_BANKS = [
    "JPMorgan Chase",
    "Bank of America",
    "Wells Fargo",
    "Citigroup",
    "Goldman Sachs",
]


def verify_sec_edgar_cybersecurity_disclosure_audit(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    tmp.close()
    try:
        copy_from_env(REMOTE_RESULT, tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}",
        }
    finally:
        os.unlink(tmp.name)

    # ── Gate 1: no work at all ────────────────────────────────────────────────
    history   = result.get("history", {})
    edgar_visits = history.get("edgar_visits", 0)
    total_visits = sum(history.values())
    report_exists = result.get("report_exists", False)

    if total_visits == 0 and not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No SEC EDGAR visits detected and no output file found. Agent did not attempt the task.",
        }

    # ── Gate 2: EDGAR must have been visited ─────────────────────────────────
    if edgar_visits == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No visits to sec.gov detected. The task requires retrieving 10-K filings "
                "directly from SEC EDGAR (sec.gov/cgi-bin/browse-edgar or EDGAR full-text search)."
            ),
        }

    # ── Gate 3: output file must exist and be post-setup ─────────────────────
    if not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "edgar_cybersecurity_audit.json not found in ~/Documents/. Agent visited EDGAR but produced no output.",
        }

    if not result.get("report_written_after_start", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file predates task setup — appears to be a stale file not produced by this run.",
        }

    if result.get("parse_error"):
        return {
            "passed": False,
            "score": 5,
            "feedback": f"Output file exists but is not valid JSON: {result['parse_error']}",
        }

    # ── Scoring ───────────────────────────────────────────────────────────────
    # 15 pts: ≥1 bank entry found
    # 15 pts: EDGAR visited (already gated, guaranteed here)
    # 25 pts: ≥3 banks with all required fields + long cybersecurity excerpt
    # 25 pts: ≥4 banks complete
    # 20 pts: all 5 banks complete
    score = 0
    feedback_parts = []
    subscores = {}

    banks_found    = result.get("banks_found", [])
    banks_complete = result.get("banks_complete", [])
    bank_details   = result.get("bank_details", {})

    # 15 pts: presence
    if banks_found:
        score += 15
        subscores["banks_present"] = 15
    else:
        subscores["banks_present"] = 0
        feedback_parts.append("No bank entries matched any of the required banks.")

    # 15 pts: EDGAR visited (guaranteed at this point)
    score += 15
    subscores["edgar_sourced"] = 15

    # 25 pts: ≥3 complete
    if len(banks_complete) >= 3:
        score += 25
        subscores["three_banks_complete"] = 25
    else:
        subscores["three_banks_complete"] = 0
        missing = [b for b in REQUIRED_BANKS if b not in banks_complete]
        feedback_parts.append(
            f"Only {len(banks_complete)} bank(s) had all required fields + 100-word cybersecurity excerpt. "
            f"Incomplete or missing: {missing[:3]}."
        )

    # 25 pts: ≥4 complete
    if len(banks_complete) >= 4:
        score += 25
        subscores["four_banks_complete"] = 25
    else:
        subscores["four_banks_complete"] = 0

    # 20 pts: all 5 complete
    if len(banks_complete) == 5:
        score += 20
        subscores["all_five_complete"] = 20
    else:
        subscores["all_five_complete"] = 0
        incomplete = [b for b in REQUIRED_BANKS if b not in banks_complete]
        if incomplete:
            feedback_parts.append(f"Banks missing full data: {incomplete}.")

    # Per-bank detail feedback
    for bank in REQUIRED_BANKS:
        detail = bank_details.get(bank)
        if detail is None:
            feedback_parts.append(f"{bank}: not found in output.")
        else:
            issues = []
            if not detail.get("has_cik"):
                issues.append("missing cik")
            if not detail.get("has_fiscal_year"):
                issues.append("missing fiscal_year_end")
            if not detail.get("has_filing_date"):
                issues.append("missing filing_date")
            if not detail.get("has_long_excerpt"):
                issues.append(f"excerpt too short ({detail.get('excerpt_words', 0)} words, need ≥100)")
            if not detail.get("is_cyber_excerpt"):
                issues.append("excerpt does not discuss cybersecurity/technology risk")
            if issues:
                feedback_parts.append(f"{bank}: {'; '.join(issues)}.")

    passed = score >= 70
    if not feedback_parts:
        feedback = f"Score {score}/100. All banks complete." if passed else f"Score {score}/100."
    else:
        feedback = f"Score {score}/100. " + " ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "subscores": subscores,
    }
