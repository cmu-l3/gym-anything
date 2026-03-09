"""
Verifier for sec_edgar_annual_report_analysis task.

Scoring breakdown (100 points total):
- Criterion 1: SEC EDGAR visited for all 3 companies (20 pts)
- Criterion 2: JSON report file exists, is fresh, and valid (15 pts)
- Criterion 3: All 3 companies present in JSON with required fields (20 pts)
- Criterion 4: Filing dates are plausible (15 pts, 5 per company)
- Criterion 5: Risk factor counts are plausible (15 pts, 5 per company)
- Criterion 6: Revenue figures are plausible (15 pts, 5 per company)
- Bonus: Bookmark folder "SEC EDGAR Research" with EDGAR URLs (included in criterion weights)

Pass threshold: 60/100
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

COMPANIES = ["microsoft", "apple", "alphabet"]


def verify_sec_edgar_annual_report_analysis(traj, env_info, task_info):
    """
    Verify that the agent researched SEC EDGAR 10-K filings for 3 tech companies
    and produced a structured JSON analysis report.
    """
    copy_from_env = env_info.get("copy_from_env")

    result_json_path = "/tmp/sec_edgar_annual_report_analysis_result.json"

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env(result_json_path, tmp_path)
    except Exception as e:
        logger.warning(f"Could not copy result file: {e}")
        return {
            "score": 0,
            "passed": False,
            "feedback": "Could not retrieve result file from environment.",
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
            "feedback": "Could not parse result JSON.",
            "subscores": {},
        }
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass

    subscores = {}
    feedback_parts = []

    sec_visits = int(data.get("sec_visits", 0) or 0)
    report_exists = bool(data.get("report_exists", False))
    report_valid_json = bool(data.get("report_valid_json", False))
    report_fresh = bool(data.get("report_fresh", False))
    companies_present = data.get("companies_present", []) or []

    # --- Gate check ---
    if sec_visits == 0 and not report_exists:
        return {
            "score": 0,
            "passed": False,
            "feedback": "No evidence of task completion: no SEC EDGAR visits and no analysis report found.",
            "subscores": {
                "edgar_visits": 0,
                "report_file": 0,
                "companies_in_report": 0,
                "filing_dates": 0,
                "risk_counts": 0,
                "revenues": 0,
            },
        }

    # --- Criterion 1: SEC EDGAR visits (20 pts) ---
    edgar_visits = int(data.get("edgar_visits", 0) or 0)
    visit_score = 0
    if edgar_visits >= 6:
        # Visited 6+ distinct EDGAR pages (likely accessed all 3 companies)
        visit_score = 20
        feedback_parts.append(f"Researched EDGAR thoroughly ({edgar_visits} distinct filing pages) (+20)")
    elif edgar_visits >= 3:
        visit_score = 15
        feedback_parts.append(f"Visited {edgar_visits} EDGAR filing pages (+15)")
    elif edgar_visits >= 1:
        visit_score = 8
        feedback_parts.append(f"Visited {edgar_visits} EDGAR filing page(s) (+8)")
    elif sec_visits >= 3:
        visit_score = 5
        feedback_parts.append(f"Visited SEC.gov ({sec_visits} pages) but few filing-specific pages (+5)")
    else:
        feedback_parts.append("No SEC EDGAR filing pages visited after task start (+0)")

    subscores["edgar_visits"] = visit_score

    # --- Criterion 2: Report file (15 pts) ---
    report_score = 0
    if report_exists and report_valid_json and report_fresh:
        report_score = 15
        feedback_parts.append("Analysis JSON exists, is fresh and valid (+15)")
    elif report_exists and report_valid_json and not report_fresh:
        report_score = 7
        feedback_parts.append("Analysis JSON exists and is valid but was not created during this task (+7)")
    elif report_exists and not report_valid_json:
        report_score = 3
        feedback_parts.append("Analysis JSON file exists but contains invalid JSON (+3)")
    else:
        feedback_parts.append("No edgar_analysis.json found at ~/Documents/ (+0)")

    subscores["report_file"] = report_score

    # --- Criterion 3: Companies in report (20 pts) ---
    company_score = 0
    per_company = data.get("per_company", {}) or {}
    present_companies = []
    missing_companies = []
    for company in COMPANIES:
        cp = per_company.get(company, {}) or {}
        if cp.get("present", False):
            # Award points based on how many fields are present
            has_date = cp.get("has_filing_date", False)
            has_risk = cp.get("has_risk_count", False)
            has_rev = cp.get("has_revenue", False)
            fields = sum([has_date, has_risk, has_rev])
            if fields >= 3:
                company_score += 7
                present_companies.append(company)
            elif fields >= 2:
                company_score += 4
                present_companies.append(company)
            elif fields >= 1:
                company_score += 2
                present_companies.append(company)
            else:
                missing_companies.append(f"{company}(no fields)")
        else:
            missing_companies.append(company)

    # Cap at 20
    company_score = min(company_score, 20)
    subscores["companies_in_report"] = company_score

    if company_score == 20:
        feedback_parts.append(f"All 3 companies with all required fields (+{company_score})")
    elif company_score > 0:
        feedback_parts.append(
            f"Companies found: {', '.join(present_companies)} (+{company_score}). "
            f"Missing/incomplete: {', '.join(missing_companies)}"
        )
    else:
        feedback_parts.append("No company data found in analysis report (+0)")

    # --- Criterion 4: Filing dates plausible (15 pts, 5 per company) ---
    filing_score = 0
    valid_dates = []
    invalid_dates = []
    for company in COMPANIES:
        cp = per_company.get(company, {}) or {}
        if cp.get("filing_date_valid", False):
            filing_score += 5
            valid_dates.append(company)
        elif cp.get("has_filing_date", False):
            filing_score += 1
            invalid_dates.append(company)

    subscores["filing_dates"] = filing_score
    if filing_score == 15:
        feedback_parts.append(f"All filing dates valid (2022–2025 range) (+{filing_score})")
    elif filing_score > 0:
        parts = []
        if valid_dates:
            parts.append(f"valid: {', '.join(valid_dates)}")
        if invalid_dates:
            parts.append(f"out-of-range: {', '.join(invalid_dates)}")
        feedback_parts.append(f"Filing dates: {'; '.join(parts)} (+{filing_score})")
    else:
        feedback_parts.append("No valid filing dates (expected YYYY-MM-DD in 2022–2025 range) (+0)")

    # --- Criterion 5: Risk factor counts plausible (15 pts, 5 per company) ---
    risk_score = 0
    plausible_risk = []
    implausible_risk = []
    for company in COMPANIES:
        cp = per_company.get(company, {}) or {}
        if cp.get("risk_count_plausible", False):
            risk_score += 5
            plausible_risk.append(company)
        elif cp.get("has_risk_count", False):
            risk_score += 1
            implausible_risk.append(company)

    subscores["risk_counts"] = risk_score
    if risk_score == 15:
        feedback_parts.append(f"All risk factor counts are plausible (5–250 range) (+{risk_score})")
    elif risk_score > 0:
        parts = []
        if plausible_risk:
            parts.append(f"plausible: {', '.join(plausible_risk)}")
        if implausible_risk:
            parts.append(f"implausible: {', '.join(implausible_risk)}")
        feedback_parts.append(f"Risk factor counts: {'; '.join(parts)} (+{risk_score})")
    else:
        feedback_parts.append("No plausible risk factor counts found (expected 5–250 per company) (+0)")

    # --- Criterion 6: Revenue figures plausible (15 pts, 5 per company) ---
    revenue_score = 0
    plausible_rev = []
    implausible_rev = []
    for company in COMPANIES:
        cp = per_company.get(company, {}) or {}
        if cp.get("revenue_plausible", False):
            revenue_score += 5
            plausible_rev.append(company)
        elif cp.get("has_revenue", False):
            revenue_score += 1
            implausible_rev.append(company)

    subscores["revenues"] = revenue_score
    if revenue_score == 15:
        feedback_parts.append(f"All revenue figures are plausible (+{revenue_score})")
    elif revenue_score > 0:
        parts = []
        if plausible_rev:
            parts.append(f"plausible: {', '.join(plausible_rev)}")
        if implausible_rev:
            parts.append(f"out-of-range: {', '.join(implausible_rev)} (must be in billions USD)")
        feedback_parts.append(f"Revenue figures: {'; '.join(parts)} (+{revenue_score})")
    else:
        feedback_parts.append(
            "No plausible revenue figures. Expected in billions USD "
            "(Microsoft ~$245B, Apple ~$381B, Alphabet ~$308B) (+0)"
        )

    # --- Total score ---
    total_score = sum(subscores.values())
    passed = total_score >= 60

    if passed:
        feedback_parts.insert(
            0,
            f"PASSED ({total_score}/100): SEC EDGAR annual report analysis completed.",
        )
    else:
        feedback_parts.insert(
            0,
            f"FAILED ({total_score}/100): SEC EDGAR analysis incomplete. "
            f"Tip: Navigate to sec.gov/cgi-bin/browse-edgar?action=getcompany for each company, "
            f"find the most recent 10-K filing, and record the required data fields.",
        )

    return {
        "score": total_score,
        "passed": passed,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
