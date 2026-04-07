#!/usr/bin/env python3
"""
Verifier for multi_vacancy_recruitment_close task.

Context: Apex Analytics Group Talent Acquisition Manager must update
candidate statuses in OrangeHRM Recruitment for Q2 2025 hiring close.

Candidates and expected outcomes:
  Marcus Webb   (Senior Data Analyst - Q2 2025) → Job Offered   (25 pts)
  Priya Sharma  (Senior Data Analyst - Q2 2025) → Rejected      (25 pts)
  Danielle Osei (Clinical Coordinator - Q2 2025) → Job Offered  (25 pts)
  Felix Braun   (Clinical Coordinator - Q2 2025) → Rejected     (25 pts)

Total: 100 pts, pass threshold: 65
Do-nothing: all 4 in Shortlisted → score 0.

Anti-Pattern 4 check (strategy enumeration):
  Mass-advance-all to "Job Offered": Marcus(25) + Priya(5 partial) + Danielle(25) + Felix(5 partial) = 60 < 65 ✓
  Correct behavior: 25+25+25+25 = 100 ✓

Status detection:
  - Job Offered: status_label contains 'offer' OR status_id == offer_status_id
  - Rejected: status_label contains 'reject' OR status_id == reject_status_id
  - Generous matching: any advancement beyond Shortlisted counts as partial (5 pts)
"""

import json
import os
import tempfile


def verify_multi_vacancy_recruitment_close(traj, env_info, task_info):
    result_path = task_info.get("metadata", {}).get(
        "result_file", "/tmp/multi_vacancy_recruitment_close_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_path, local_tmp)
        with open(local_tmp, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file '{result_path}': {e}",
        }
    finally:
        if os.path.exists(local_tmp):
            os.remove(local_tmp)

    score = 0
    feedback_parts = []

    offer_id = str(data.get("offer_status_id", "6"))
    reject_id = str(data.get("reject_status_id", "4"))

    def is_offered(status_str, label_str):
        status_str = str(status_str or "")
        label_str = str(label_str or "").lower()
        return status_str == offer_id or "offer" in label_str

    def is_rejected(status_str, label_str):
        status_str = str(status_str or "")
        label_str = str(label_str or "").lower()
        return status_str == reject_id or "reject" in label_str

    def is_shortlisted(status_str, label_str):
        label_str = str(label_str or "").lower()
        return "shortlist" in label_str

    # Marcus Webb — should be Job Offered
    marcus_status = str(data.get("marcus_status", ""))
    marcus_label = str(data.get("marcus_label", ""))
    if is_offered(marcus_status, marcus_label):
        score += 25
        feedback_parts.append(f"PASS Marcus Webb → Job Offered (status={marcus_status} '{marcus_label}') (+25)")
    elif not is_shortlisted(marcus_status, marcus_label) and marcus_status:
        score += 5
        feedback_parts.append(f"PARTIAL Marcus Webb advanced but not Offered (status={marcus_status} '{marcus_label}') (+5)")
    else:
        feedback_parts.append(f"FAIL Marcus Webb still Shortlisted or missing (status={marcus_status} '{marcus_label}') (+0)")

    # Priya Sharma — should be Rejected
    priya_status = str(data.get("priya_status", ""))
    priya_label = str(data.get("priya_label", ""))
    if is_rejected(priya_status, priya_label):
        score += 25
        feedback_parts.append(f"PASS Priya Sharma → Rejected (status={priya_status} '{priya_label}') (+25)")
    elif not is_shortlisted(priya_status, priya_label) and priya_status:
        score += 5
        feedback_parts.append(f"PARTIAL Priya Sharma status changed but not Rejected (status={priya_status}) (+5)")
    else:
        feedback_parts.append(f"FAIL Priya Sharma still Shortlisted or missing (status={priya_status} '{priya_label}') (+0)")

    # Danielle Osei — should be Job Offered
    danielle_status = str(data.get("danielle_status", ""))
    danielle_label = str(data.get("danielle_label", ""))
    if is_offered(danielle_status, danielle_label):
        score += 25
        feedback_parts.append(f"PASS Danielle Osei → Job Offered (status={danielle_status} '{danielle_label}') (+25)")
    elif not is_shortlisted(danielle_status, danielle_label) and danielle_status:
        score += 5
        feedback_parts.append(f"PARTIAL Danielle Osei advanced but not Offered (status={danielle_status}) (+5)")
    else:
        feedback_parts.append(f"FAIL Danielle Osei still Shortlisted or missing (status={danielle_status} '{danielle_label}') (+0)")

    # Felix Braun — should be Rejected
    felix_status = str(data.get("felix_status", ""))
    felix_label = str(data.get("felix_label", ""))
    if is_rejected(felix_status, felix_label):
        score += 25
        feedback_parts.append(f"PASS Felix Braun → Rejected (status={felix_status} '{felix_label}') (+25)")
    elif not is_shortlisted(felix_status, felix_label) and felix_status:
        score += 5
        feedback_parts.append(f"PARTIAL Felix Braun status changed but not Rejected (status={felix_status}) (+5)")
    else:
        feedback_parts.append(f"FAIL Felix Braun still Shortlisted or missing (status={felix_status} '{felix_label}') (+0)")

    score = min(score, 100)
    passed = score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
