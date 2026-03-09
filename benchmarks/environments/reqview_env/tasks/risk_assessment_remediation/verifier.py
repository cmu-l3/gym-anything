#!/usr/bin/env python3
"""Verifier for risk_assessment_remediation task.

Checks that the agent:
1. Restored non-zero severity/detectability/probability scores on CAUSE entries (range-based)
2. Set responsibility and target date on ACT entries
3. Created a mitigation traceability link from SRS-160 to RISKS-44

Scoring (100 points):
- RISKS-40 scores restored (all 3 non-zero, in 1-10 range): 20 points
- RISKS-44 scores restored (all 3 non-zero, in 1-10 range): 20 points
- RISKS-26 responsibility and targetDate set: 15 points
- RISKS-45 responsibility and targetDate set: 15 points
- SRS-160 has mitigation link to RISKS-44: 30 points

Pass threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RISKS_PATH = "/home/ga/Documents/ReqView/risk_assessment_project/documents/RISKS.json"
SRS_PATH = "/home/ga/Documents/ReqView/risk_assessment_project/documents/SRS.json"


def _find_by_id(items, target_id):
    """Recursively search for an item by ID."""
    for item in items:
        if str(item.get('id')) == str(target_id):
            return item
        if 'children' in item:
            result = _find_by_id(item['children'], target_id)
            if result:
                return result
    return None


def _check_score_valid(value):
    """Check if a risk score is a valid non-zero integer in 1-10 range."""
    try:
        v = int(value)
        return 1 <= v <= 10
    except (TypeError, ValueError):
        return False


def verify_risk_assessment_remediation(traj, env_info, task_info):
    """Verify risk assessment scores and links were restored."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback_parts = []
    details = {}

    # Read RISKS.json
    tmp_risks = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RISKS_PATH, tmp_risks.name)
        with open(tmp_risks.name) as f:
            risks = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read RISKS.json: {e}"}
    finally:
        if os.path.exists(tmp_risks.name):
            os.unlink(tmp_risks.name)

    # Check 1: RISKS-40 scores restored (20 points)
    r40 = _find_by_id(risks.get('data', []), '40')
    if r40:
        sev = r40.get('severity', 0)
        det = r40.get('detectability', 0)
        prob = r40.get('probability', 0)
        all_valid = all(_check_score_valid(v) for v in [sev, det, prob])
        details['RISKS-40'] = {'severity': sev, 'detectability': det, 'probability': prob}
        if all_valid:
            score += 20
            feedback_parts.append(f"RISKS-40 scores restored (S={sev}, D={det}, P={prob})")
        else:
            feedback_parts.append(
                f"RISKS-40 scores invalid (S={sev}, D={det}, P={prob}) — "
                f"all must be 1-10"
            )
    else:
        feedback_parts.append("RISKS-40 not found")

    # Check 2: RISKS-44 scores restored (20 points)
    r44 = _find_by_id(risks.get('data', []), '44')
    if r44:
        sev = r44.get('severity', 0)
        det = r44.get('detectability', 0)
        prob = r44.get('probability', 0)
        all_valid = all(_check_score_valid(v) for v in [sev, det, prob])
        details['RISKS-44'] = {'severity': sev, 'detectability': det, 'probability': prob}
        if all_valid:
            score += 20
            feedback_parts.append(f"RISKS-44 scores restored (S={sev}, D={det}, P={prob})")
        else:
            feedback_parts.append(
                f"RISKS-44 scores invalid (S={sev}, D={det}, P={prob}) — "
                f"all must be 1-10"
            )
    else:
        feedback_parts.append("RISKS-44 not found")

    # Check 3: RISKS-26 responsibility and targetDate (15 points)
    r26 = _find_by_id(risks.get('data', []), '26')
    if r26:
        resp = str(r26.get('responsibility', '')).strip()
        tdate = str(r26.get('targetDate', '')).strip()
        details['RISKS-26'] = {'responsibility': resp, 'targetDate': tdate}
        if resp and tdate:
            score += 15
            feedback_parts.append(
                f"RISKS-26 assignment set (resp='{resp}', date='{tdate}')"
            )
        elif resp:
            score += 8
            feedback_parts.append(f"RISKS-26 responsibility set but targetDate missing")
        elif tdate:
            score += 8
            feedback_parts.append(f"RISKS-26 targetDate set but responsibility missing")
        else:
            feedback_parts.append("RISKS-26 still has empty responsibility and targetDate")
    else:
        feedback_parts.append("RISKS-26 not found")

    # Check 4: RISKS-45 responsibility and targetDate (15 points)
    r45 = _find_by_id(risks.get('data', []), '45')
    if r45:
        resp = str(r45.get('responsibility', '')).strip()
        tdate = str(r45.get('targetDate', '')).strip()
        details['RISKS-45'] = {'responsibility': resp, 'targetDate': tdate}
        if resp and tdate:
            score += 15
            feedback_parts.append(
                f"RISKS-45 assignment set (resp='{resp}', date='{tdate}')"
            )
        elif resp:
            score += 8
            feedback_parts.append(f"RISKS-45 responsibility set but targetDate missing")
        elif tdate:
            score += 8
            feedback_parts.append(f"RISKS-45 targetDate set but responsibility missing")
        else:
            feedback_parts.append("RISKS-45 still has empty responsibility and targetDate")
    else:
        feedback_parts.append("RISKS-45 not found")

    # Check 5: SRS-160 mitigation link to RISKS-44 (30 points)
    tmp_srs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(SRS_PATH, tmp_srs.name)
        with open(tmp_srs.name) as f:
            srs = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Failed to read SRS.json: {e}")
        srs = {'data': []}
    finally:
        if os.path.exists(tmp_srs.name):
            os.unlink(tmp_srs.name)

    s160 = _find_by_id(srs.get('data', []), '160')
    if s160:
        links = s160.get('links', {})
        mit = links.get('mitigation', [])
        details['SRS-160_mitigation'] = mit
        if 'RISKS-44' in mit:
            score += 30
            feedback_parts.append("SRS-160 has mitigation link to RISKS-44")
        else:
            feedback_parts.append(
                f"SRS-160 missing mitigation link to RISKS-44 (current: {mit})"
            )
    else:
        feedback_parts.append("SRS-160 not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
