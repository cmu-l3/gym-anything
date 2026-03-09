#!/usr/bin/env python3
"""Verifier for apt_threat_intel_profiles task.

Intelligence Analyst task: Build OSINT threat intelligence profiles for
Sandworm (APT44) and Lazarus Group (APT38) using public sources.

Scoring (100 points total, pass threshold 60):
- Criterion 1: Firefox history shows MITRE ATT&CK visits (15 pts)
- Criterion 2: Firefox history shows government advisory source visits (10 pts)
- Criterion 3: 'APT Research' bookmark folder exists (10 pts)
- Criterion 4: Sandworm sub-folder with ≥3 bookmarks (15 pts)
- Criterion 5: Lazarus sub-folder with ≥3 bookmarks (15 pts)
- Criterion 6: Report file exists and was created after task start (15 pts)
- Criterion 7: Report content quality - group names + T-codes + attribution (20 pts)
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_apt_threat_intel_profiles(traj, env_info, task_info):
    """Verify APT threat intelligence profile task completion."""

    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/apt_threat_intel_profiles_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # GATE: If no evidence of work at all (no relevant history, no bookmark folder, no report),
    # return score=0 immediately to prevent always-true criteria from giving points
    no_evidence = (
        result.get('mitre_visits', 0) == 0
        and result.get('gov_visits', 0) == 0
        and not result.get('apt_folder_exists', False)
        and not result.get('report_exists', False)
    )
    if no_evidence:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No evidence of work: no relevant sites visited, no bookmarks created, no report written"
        }

    # Criterion 1: MITRE ATT&CK history (15 pts)
    mitre_visits = result.get('mitre_visits', 0)
    if mitre_visits >= 4:
        score += 15
        subscores['mitre_history'] = 15
        feedback_parts.append(f"MITRE ATT&CK visited {mitre_visits} times (15/15)")
    elif mitre_visits >= 1:
        pts = 8
        score += pts
        subscores['mitre_history'] = pts
        feedback_parts.append(f"MITRE ATT&CK visited {mitre_visits} time(s) — partial ({pts}/15)")
    else:
        subscores['mitre_history'] = 0
        feedback_parts.append("MITRE ATT&CK not visited (0/15)")

    # Criterion 2: Government/authoritative advisory source history (10 pts)
    gov_visits = result.get('gov_visits', 0)
    if gov_visits >= 2:
        score += 10
        subscores['gov_history'] = 10
        feedback_parts.append(f"Gov advisory sources visited {gov_visits} times (10/10)")
    elif gov_visits == 1:
        score += 5
        subscores['gov_history'] = 5
        feedback_parts.append(f"Gov advisory source visited once — partial (5/10)")
    else:
        subscores['gov_history'] = 0
        feedback_parts.append("No government advisory sources visited (0/10)")

    # Criterion 3: 'APT Research' bookmark folder exists (10 pts)
    if result.get('apt_folder_exists', False):
        score += 10
        subscores['apt_folder'] = 10
        feedback_parts.append("'APT Research' bookmark folder exists (10/10)")
    else:
        subscores['apt_folder'] = 0
        feedback_parts.append("'APT Research' bookmark folder NOT found (0/10)")

    # Criterion 4: Sandworm sub-folder with ≥3 bookmarks (15 pts)
    sandworm_sub = result.get('sandworm_subfolder', False)
    sandworm_bm = result.get('sandworm_bookmarks', 0)
    if sandworm_sub and sandworm_bm >= 3:
        score += 15
        subscores['sandworm_folder'] = 15
        feedback_parts.append(f"Sandworm sub-folder with {sandworm_bm} bookmarks (15/15)")
    elif sandworm_sub and sandworm_bm >= 1:
        pts = 8
        score += pts
        subscores['sandworm_folder'] = pts
        feedback_parts.append(f"Sandworm sub-folder exists but only {sandworm_bm} bookmark(s) (need ≥3) ({pts}/15)")
    elif result.get('total_apt_bookmarks', 0) >= 3:
        # Credit if bookmarks exist in APT folder but not in sub-folders
        pts = 5
        score += pts
        subscores['sandworm_folder'] = pts
        feedback_parts.append(f"APT bookmarks found but no Sandworm sub-folder ({pts}/15)")
    else:
        subscores['sandworm_folder'] = 0
        feedback_parts.append("No Sandworm sub-folder or bookmarks (0/15)")

    # Criterion 5: Lazarus sub-folder with ≥3 bookmarks (15 pts)
    lazarus_sub = result.get('lazarus_subfolder', False)
    lazarus_bm = result.get('lazarus_bookmarks', 0)
    if lazarus_sub and lazarus_bm >= 3:
        score += 15
        subscores['lazarus_folder'] = 15
        feedback_parts.append(f"Lazarus sub-folder with {lazarus_bm} bookmarks (15/15)")
    elif lazarus_sub and lazarus_bm >= 1:
        pts = 8
        score += pts
        subscores['lazarus_folder'] = pts
        feedback_parts.append(f"Lazarus sub-folder exists but only {lazarus_bm} bookmark(s) (need ≥3) ({pts}/15)")
    else:
        subscores['lazarus_folder'] = 0
        feedback_parts.append("No Lazarus Group sub-folder (0/15)")

    # Criterion 6: Report file created after task start (15 pts)
    if result.get('report_exists', False) and result.get('report_fresh', False):
        report_size = result.get('report_size', 0)
        if report_size >= 500:
            score += 15
            subscores['report_file'] = 15
            feedback_parts.append(f"Report file exists, new, and substantial ({report_size} bytes) (15/15)")
        else:
            pts = 8
            score += pts
            subscores['report_file'] = pts
            feedback_parts.append(f"Report file exists but very short ({report_size} bytes) ({pts}/15)")
    elif result.get('report_exists', False) and not result.get('report_fresh', False):
        subscores['report_file'] = 0
        feedback_parts.append("Report file exists but predates task start (0/15)")
    else:
        subscores['report_file'] = 0
        feedback_parts.append("Report file ~/Desktop/threat_intel_report.txt not found (0/15)")

    # Criterion 7: Report content quality (20 pts)
    # 5 pts: mentions Sandworm
    # 5 pts: mentions Lazarus
    # 5 pts: contains MITRE T-codes (T1xxx format)
    # 5 pts: contains attribution/nation-state language
    content_score = 0
    if result.get('report_has_sandworm', False):
        content_score += 5
    if result.get('report_has_lazarus', False):
        content_score += 5
    if result.get('report_has_tcodes', False):
        content_score += 5
    if result.get('report_has_attribution', False):
        content_score += 5
    score += content_score
    subscores['report_content'] = content_score
    content_details = []
    if result.get('report_has_sandworm', False):
        content_details.append("Sandworm ✓")
    if result.get('report_has_lazarus', False):
        content_details.append("Lazarus ✓")
    if result.get('report_has_tcodes', False):
        content_details.append("MITRE T-codes ✓")
    if result.get('report_has_attribution', False):
        content_details.append("Attribution ✓")
    if content_details:
        feedback_parts.append(f"Report content: {', '.join(content_details)} ({content_score}/20)")
    else:
        feedback_parts.append("Report content missing required elements (0/20)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
