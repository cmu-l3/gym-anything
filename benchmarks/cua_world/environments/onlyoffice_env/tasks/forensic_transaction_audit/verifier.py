#!/usr/bin/env python3
"""
Verifier for Forensic Transaction Audit task.

Uses REAL data from the City of Chicago Open Data Portal - Vendor Payments
(data.cityofchicago.org). Since the data is real government financial records
(not synthetic with planted anomalies), the verifier evaluates METHODOLOGY
rather than specific anomaly detection.

Scoring (10 points total, pass threshold 5.0):
  - Wrong-target gate: file exists with sufficient content
  - CHECK 1: Data import and organization (1.0 pt)
  - CHECK 2: Benford's Law / digit distribution analysis (2.0 pts)
  - CHECK 3: Duplicate / vendor analysis (2.0 pts)
  - CHECK 4: Amount pattern analysis (1.5 pts)
  - CHECK 5: Temporal analysis (1.5 pts)
  - CHECK 6: Summary findings and risk assessment (2.0 pts)
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_all_text(wb):
    """Extract all text from all cells in all sheets of a workbook."""
    all_text = []
    for sheet_name in wb.sheetnames:
        sheet = wb[sheet_name]
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 500),
                                    max_col=min(sheet.max_column, 30)):
            for cell in row:
                if cell.value is not None:
                    all_text.append(str(cell.value).lower())
    return " ".join(all_text)


def count_sheets_with_content(wb):
    """Count sheets that have substantial content (more than 5 filled cells)."""
    count = 0
    for sheet_name in wb.sheetnames:
        sheet = wb[sheet_name]
        filled = 0
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 100),
                                    max_col=min(sheet.max_column, 20)):
            for cell in row:
                if cell.value is not None:
                    filled += 1
                    if filled > 5:
                        count += 1
                        break
            if filled > 5:
                break
    return count


def verify_forensic_audit(traj, env_info, task_info):
    """
    Verify forensic transaction audit on City of Chicago Vendor Payments data.

    Evaluates forensic METHODOLOGY rather than specific anomaly detection,
    since the dataset contains real government financial records.

    Scoring (10 points total, pass threshold 5.0):
      - Wrong-target gate: file exists with sufficient content
      - CHECK 1: Data import and organization (1.0 pt)
      - CHECK 2: Benford's Law / digit distribution analysis (2.0 pts)
      - CHECK 3: Duplicate / vendor analysis (2.0 pts)
      - CHECK 4: Amount pattern analysis (1.5 pts)
      - CHECK 5: Temporal analysis (1.5 pts)
      - CHECK 6: Summary findings and risk assessment (2.0 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/forensic_audit_report.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_forensic_')

    try:
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Wrong-target gate: Failed to load forensic_audit_report.xlsx: {error}"
            }

        feedback_parts = []
        score = 0.0

        # Extract all text for content analysis
        all_text = extract_all_text(wb)
        num_sheets = len(wb.sheetnames)
        content_sheets = count_sheets_with_content(wb)

        # Count total filled cells across all sheets
        total_cells = 0
        for sn in wb.sheetnames:
            sheet = wb[sn]
            for row in sheet.iter_rows(max_row=min(sheet.max_row, 500),
                                        max_col=min(sheet.max_column, 30)):
                for cell in row:
                    if cell.value is not None:
                        total_cells += 1

        # ===================================================================
        # WRONG-TARGET GATE: Must have substantial content
        # ===================================================================
        if total_cells < 20:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Wrong-target gate: File has insufficient content (< 20 cells filled)"
            }

        # ===================================================================
        # CHECK 1: Data import and organization (1.0 pt)
        # Records present, columns identified
        # ===================================================================
        column_terms = ["voucher", "amount", "check_date", "date", "department",
                        "contract", "vendor", "payment"]
        column_evidence = sum(1 for term in column_terms if term in all_text)

        # Check if data rows are present (look for voucher patterns or vendor names)
        data_terms = ["pv", "cvip", "pvci", "dv", "chicago", "department of"]
        data_evidence = sum(1 for term in data_terms if term in all_text)

        if column_evidence >= 3 and data_evidence >= 2:
            score += 1.0
            feedback_parts.append(f"Data import: records present, columns identified ({content_sheets} sheets)")
        elif column_evidence >= 2 or data_evidence >= 2:
            score += 0.5
            feedback_parts.append("Data import: partial - some data present but incomplete organization")
        else:
            feedback_parts.append("Data import: insufficient evidence of data organization")

        # ===================================================================
        # CHECK 2: Benford's Law / digit distribution analysis (2.0 pts)
        # Must mention "benford" or "digit distribution" or "first digit"
        # AND have frequency data
        # ===================================================================
        benford_terms = ["benford", "digit distribution", "first digit",
                         "leading digit", "digit frequency", "digit analysis",
                         "benford's law", "newcomb-benford", "digit test"]
        benford_mentioned = any(term in all_text for term in benford_terms)

        # Check for frequency data (numbers that look like counts or percentages)
        frequency_terms = ["frequency", "expected", "observed", "count",
                          "proportion", "percentage", "%", "distribution",
                          "chi-square", "chi square", "deviation", "conformity"]
        frequency_evidence = sum(1 for term in frequency_terms if term in all_text)

        # Check for digit references (1-9)
        digit_refs = sum(1 for d in ["digit 1", "digit 2", "digit 3", "digit 4",
                                      "digit 5", "digit 6", "digit 7", "digit 8", "digit 9",
                                      "30.1%", "17.6%", "12.5%", "9.7%",
                                      "0.301", "0.176", "0.125", "0.097"]
                         if d in all_text)

        if benford_mentioned and (frequency_evidence >= 2 or digit_refs >= 2):
            score += 2.0
            feedback_parts.append("Benford's Law: analysis present with frequency data")
        elif benford_mentioned and frequency_evidence >= 1:
            score += 1.5
            feedback_parts.append("Benford's Law: mentioned with some frequency data")
        elif benford_mentioned:
            score += 1.0
            feedback_parts.append("Benford's Law: mentioned but limited frequency data")
        elif frequency_evidence >= 2 and digit_refs >= 1:
            score += 0.5
            feedback_parts.append("Digit distribution: some analysis but Benford's not explicitly referenced")
        else:
            feedback_parts.append("Benford's Law / digit distribution: not detected")

        # ===================================================================
        # CHECK 3: Duplicate / vendor analysis (2.0 pts)
        # Duplicate payments, vendor concentration, repeat vendors
        # ===================================================================
        duplicate_terms = ["duplicate", "dup ", "duplicated", "repeated",
                          "double pay", "same amount", "identical",
                          "matching", "repeat payment"]
        duplicate_evidence = sum(1 for term in duplicate_terms if term in all_text)

        vendor_analysis_terms = ["vendor concentration", "top vendor",
                                "largest vendor", "vendor analysis",
                                "vendor summary", "vendor spend",
                                "highest paid", "most frequent",
                                "vendor count", "unique vendor",
                                "vendor distribution", "pareto",
                                "concentration", "80/20", "80-20"]
        vendor_evidence = sum(1 for term in vendor_analysis_terms if term in all_text)

        if duplicate_evidence >= 2 and vendor_evidence >= 2:
            score += 2.0
            feedback_parts.append("Duplicate/vendor analysis: thorough - duplicates and vendor concentration examined")
        elif duplicate_evidence >= 1 and vendor_evidence >= 1:
            score += 1.5
            feedback_parts.append("Duplicate/vendor analysis: both addressed but could be deeper")
        elif duplicate_evidence >= 1 or vendor_evidence >= 2:
            score += 1.0
            feedback_parts.append("Duplicate/vendor analysis: partial - one aspect covered")
        elif duplicate_evidence >= 1 or vendor_evidence >= 1:
            score += 0.5
            feedback_parts.append("Duplicate/vendor analysis: minimal coverage")
        else:
            feedback_parts.append("Duplicate/vendor analysis: not detected")

        # ===================================================================
        # CHECK 4: Amount pattern analysis (1.5 pts)
        # Round numbers, clustering, threshold analysis, statistical measures
        # ===================================================================
        amount_terms = ["round number", "round amount", "even amount",
                       "whole number", "exact amount",
                       "cluster", "clustering", "distribution",
                       "threshold", "approval limit", "authorization",
                       "just below", "just under", "split",
                       "structuring", "smurfing",
                       "mean", "median", "average", "standard deviation",
                       "std dev", "outlier", "z-score", "z score",
                       "percentile", "quartile", "iqr",
                       "skew", "kurtosis", "histogram",
                       "statistical", "descriptive stat"]
        amount_evidence = sum(1 for term in amount_terms if term in all_text)

        if amount_evidence >= 4:
            score += 1.5
            feedback_parts.append("Amount pattern analysis: comprehensive")
        elif amount_evidence >= 3:
            score += 1.0
            feedback_parts.append("Amount pattern analysis: adequate")
        elif amount_evidence >= 1:
            score += 0.5
            feedback_parts.append("Amount pattern analysis: minimal")
        else:
            feedback_parts.append("Amount pattern analysis: not detected")

        # ===================================================================
        # CHECK 5: Temporal analysis (1.5 pts)
        # Date patterns, trends, seasonality, weekend/holiday
        # ===================================================================
        temporal_terms = ["weekend", "saturday", "sunday",
                         "holiday", "end of month", "end-of-month",
                         "month-end", "quarter end", "quarter-end",
                         "year end", "year-end", "fiscal",
                         "seasonal", "seasonality", "trend",
                         "time series", "monthly", "quarterly",
                         "day of week", "day-of-week",
                         "temporal", "date pattern", "date analysis",
                         "time pattern", "payment timing",
                         "spike", "surge", "unusual date",
                         "frequency by month", "by month", "by quarter"]
        temporal_evidence = sum(1 for term in temporal_terms if term in all_text)

        if temporal_evidence >= 3:
            score += 1.5
            feedback_parts.append("Temporal analysis: thorough")
        elif temporal_evidence >= 2:
            score += 1.0
            feedback_parts.append("Temporal analysis: adequate")
        elif temporal_evidence >= 1:
            score += 0.5
            feedback_parts.append("Temporal analysis: minimal")
        else:
            feedback_parts.append("Temporal analysis: not detected")

        # ===================================================================
        # CHECK 6: Summary findings and risk assessment (2.0 pts)
        # Flagged transactions, risk ratings, recommendations
        # ===================================================================
        finding_terms = ["finding", "conclusion", "summary", "overview",
                        "executive summary", "key finding", "result"]
        finding_evidence = sum(1 for term in finding_terms if term in all_text)

        risk_terms = ["risk", "risk rating", "risk score", "risk level",
                     "high risk", "medium risk", "low risk",
                     "red flag", "flag", "flagged", "suspicious",
                     "anomal", "irregular", "concern"]
        risk_evidence = sum(1 for term in risk_terms if term in all_text)

        recommendation_terms = ["recommend", "recommendation", "action",
                               "follow-up", "follow up", "investigation",
                               "further review", "next step",
                               "remediation", "corrective", "mitigation"]
        recommendation_evidence = sum(1 for term in recommendation_terms if term in all_text)

        sub_score_6 = 0.0
        if finding_evidence >= 2:
            sub_score_6 += 0.5
        elif finding_evidence >= 1:
            sub_score_6 += 0.25

        if risk_evidence >= 3:
            sub_score_6 += 1.0
        elif risk_evidence >= 2:
            sub_score_6 += 0.7
        elif risk_evidence >= 1:
            sub_score_6 += 0.3

        if recommendation_evidence >= 2:
            sub_score_6 += 0.5
        elif recommendation_evidence >= 1:
            sub_score_6 += 0.25

        score += sub_score_6
        if sub_score_6 >= 1.5:
            feedback_parts.append("Summary/risk assessment: comprehensive with findings, risk ratings, and recommendations")
        elif sub_score_6 >= 1.0:
            feedback_parts.append("Summary/risk assessment: adequate - some elements present")
        elif sub_score_6 >= 0.5:
            feedback_parts.append("Summary/risk assessment: partial - limited findings or risk assessment")
        else:
            feedback_parts.append("Summary/risk assessment: not detected")

        # ===================================================================
        # Final assessment
        # ===================================================================
        passed = score >= 5.0
        normalized_score = score / 10.0

        feedback = " | ".join(feedback_parts)
        logger.info(f"Forensic audit verification - Score: {score}/10.0, Passed: {passed}")

        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
