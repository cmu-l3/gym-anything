#!/usr/bin/env python3
"""Verifier for end_of_quarter_it_reconciliation task.

Scoring breakdown (100 points, pass threshold 65):

Phase 1 — Employee Departures (30 pts):
  C1:  Departing employees' hardware checked in (10 pts)
       - RECON-L001 checked in (4 pts)
       - RECON-MON-A checked in (3 pts)
       - RECON-L002 checked in (3 pts)
  C2:  Checked-in assets set to Ready to Deploy (5 pts)
  C3:  Both departing users deactivated (8 pts)
  C4:  Both departing users' M365 seats removed (7 pts)

Phase 2 — New Hire Provisioning (25 pts):
  C5:  Both new users created with correct attributes (10 pts)
  C6:  Each new hire has a laptop checked out (8 pts)
  C7:  Both new hires have M365 seats (7 pts)

Phase 3 — Warranty Compliance Audit (33 pts):
  C8:  Expired-warranty deployed laptops set to Out for Repair (15 pts)
  C9:  Correct audit note on expired-warranty laptops (5 pts)
  C10: Active-warranty laptops NOT modified (8 pts)
  C11: Non-laptop distractors and non-deployed expired laptop NOT flagged (5 pts)

Phase 4 — Organizational Update (12 pts):
  C12: Department renamed to Growth & Marketing (5 pts)
  C13: Location Building C - Floor 3 created (4 pts)
  C14: ppatel location updated (3 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/end_of_quarter_it_reconciliation_result.json"


def verify_end_of_quarter_it_reconciliation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    p1 = result.get("phase1_departures", {})
    p2 = result.get("phase2_new_hires", {})
    p3 = result.get("phase3_warranty_audit", {})
    p4 = result.get("phase4_org_update", {})

    # =================================================================
    # Phase 1: Employee Departures (30 pts)
    # =================================================================
    assets_p1 = p1.get("assets", {})

    # C1: Hardware checked in (10 pts)
    c1 = 0
    l001 = assets_p1.get("RECON_L001", {})
    mona = assets_p1.get("RECON_MON_A", {})
    l002 = assets_p1.get("RECON_L002", {})

    if l001.get("is_checked_in"):
        c1 += 4
        feedback.append("C1a: RECON-L001 (alee laptop) checked in (+4)")
    else:
        feedback.append("C1a: RECON-L001 still checked out (+0)")

    if mona.get("is_checked_in"):
        c1 += 3
        feedback.append("C1b: RECON-MON-A (alee monitor) checked in (+3)")
    else:
        feedback.append("C1b: RECON-MON-A still checked out (+0)")

    if l002.get("is_checked_in"):
        c1 += 3
        feedback.append("C1c: RECON-L002 (bkumar laptop) checked in (+3)")
    else:
        feedback.append("C1c: RECON-L002 still checked out (+0)")
    score += c1

    # C2: Checked-in assets have Ready to Deploy status (5 pts)
    c2 = 0
    for label, asset_data in [("L001", l001), ("MON-A", mona), ("L002", l002)]:
        if asset_data.get("is_checked_in") and asset_data.get("status_name") == "Ready to Deploy":
            c2 += 1
    if c2 == 3:
        c2 = 5
        feedback.append("C2: All checked-in assets set to Ready to Deploy (+5)")
    elif c2 > 0:
        c2_pts = int(c2 * 5 / 3)
        feedback.append(f"C2: {c2}/3 checked-in assets set to Ready to Deploy (+{c2_pts})")
        c2 = c2_pts
    else:
        feedback.append("C2: No checked-in assets set to Ready to Deploy (+0)")
    score += c2

    # C3: Users deactivated (8 pts)
    c3 = 0
    if p1.get("alee_deactivated"):
        c3 += 4
        feedback.append("C3a: alee deactivated (+4)")
    else:
        feedback.append("C3a: alee still active (+0)")

    if p1.get("bkumar_deactivated"):
        c3 += 4
        feedback.append("C3b: bkumar deactivated (+4)")
    else:
        feedback.append("C3b: bkumar still active (+0)")
    score += c3

    # C4: M365 seats removed (7 pts)
    c4 = 0
    if p1.get("alee_m365_seat_removed"):
        c4 += 3
        feedback.append("C4a: alee M365 seat removed (+3)")
    else:
        feedback.append("C4a: alee still has M365 seat (+0)")

    if p1.get("bkumar_m365_seat_removed"):
        c4 += 4
        feedback.append("C4b: bkumar M365 seat removed (+4)")
    else:
        feedback.append("C4b: bkumar still has M365 seat (+0)")
    score += c4

    # =================================================================
    # Phase 2: New Hire Provisioning (25 pts)
    # =================================================================
    mrivera = p2.get("mrivera", {})
    ytanaka = p2.get("ytanaka", {})

    # C5: Users created with correct attributes (10 pts)
    c5 = 0
    if mrivera.get("found"):
        c5 += 2
        if mrivera.get("department") == "Engineering":
            c5 += 1
        if mrivera.get("location") and "Building A" in mrivera.get("location", ""):
            c5 += 1
        if mrivera.get("email") == "mrivera@example.com":
            c5 += 1
        feedback.append(f"C5a: mrivera created (dept={mrivera.get('department')}, loc={mrivera.get('location')}) (+{min(c5, 5)})")
    else:
        feedback.append("C5a: mrivera not found (+0)")

    c5b = 0
    if ytanaka.get("found"):
        c5b += 2
        if ytanaka.get("department") == "Sales":
            c5b += 1
        if ytanaka.get("location") and "New York" in ytanaka.get("location", ""):
            c5b += 1
        if ytanaka.get("email") == "ytanaka@example.com":
            c5b += 1
        feedback.append(f"C5b: ytanaka created (dept={ytanaka.get('department')}, loc={ytanaka.get('location')}) (+{min(c5b, 5)})")
    else:
        feedback.append("C5b: ytanaka not found (+0)")
    score += min(c5, 5) + min(c5b, 5)

    # C6: Laptops checked out to new hires (8 pts)
    c6 = 0
    if mrivera.get("has_laptop"):
        c6 += 4
        feedback.append("C6a: mrivera has laptop checked out (+4)")
    else:
        feedback.append("C6a: mrivera has no laptop (+0)")

    if ytanaka.get("has_laptop"):
        c6 += 4
        feedback.append("C6b: ytanaka has laptop checked out (+4)")
    else:
        feedback.append("C6b: ytanaka has no laptop (+0)")
    score += c6

    # C7: M365 seats assigned (7 pts)
    c7 = 0
    if mrivera.get("has_m365_seat"):
        c7 += 3
        feedback.append("C7a: mrivera has M365 seat (+3)")
    else:
        feedback.append("C7a: mrivera has no M365 seat (+0)")

    if ytanaka.get("has_m365_seat"):
        c7 += 4
        feedback.append("C7b: ytanaka has M365 seat (+4)")
    else:
        feedback.append("C7b: ytanaka has no M365 seat (+0)")
    score += c7

    # =================================================================
    # Phase 3: Warranty Compliance Audit (33 pts)
    # =================================================================

    # C8: Expired-warranty laptops set to Out for Repair (15 pts)
    c8 = 0
    l003 = p3.get("RECON_L003", {})
    l004 = p3.get("RECON_L004", {})

    if l003.get("status_name") == "Out for Repair":
        c8 += 8
        feedback.append("C8a: RECON-L003 status set to Out for Repair (+8)")
    else:
        feedback.append(f"C8a: RECON-L003 status is '{l003.get('status_name', 'unknown')}', expected 'Out for Repair' (+0)")

    if l004.get("status_name") == "Out for Repair":
        c8 += 7
        feedback.append("C8b: RECON-L004 status set to Out for Repair (+7)")
    else:
        feedback.append(f"C8b: RECON-L004 status is '{l004.get('status_name', 'unknown')}', expected 'Out for Repair' (+0)")
    score += c8

    # C9: Audit note (5 pts)
    c9 = 0
    if p3.get("RECON_L003_has_audit_note"):
        c9 += 3
        feedback.append("C9a: RECON-L003 has audit note (+3)")
    else:
        feedback.append("C9a: RECON-L003 missing audit note (+0)")

    if p3.get("RECON_L004_has_audit_note"):
        c9 += 2
        feedback.append("C9b: RECON-L004 has audit note (+2)")
    else:
        feedback.append("C9b: RECON-L004 missing audit note (+0)")
    score += c9

    # C10: Active-warranty laptops unchanged (8 pts)
    c10 = 0
    l005 = p3.get("RECON_L005", {})
    l006 = p3.get("RECON_L006", {})

    if l005.get("status_name") != "Out for Repair" and not l005.get("is_checked_in", True):
        c10 += 4
        feedback.append("C10a: RECON-L005 (active warranty) unchanged (+4)")
    else:
        feedback.append(f"C10a: RECON-L005 was incorrectly modified (status={l005.get('status_name')}) (+0)")

    if l006.get("status_name") != "Out for Repair" and not l006.get("is_checked_in", True):
        c10 += 4
        feedback.append("C10b: RECON-L006 (active warranty) unchanged (+4)")
    else:
        feedback.append(f"C10b: RECON-L006 was incorrectly modified (status={l006.get('status_name')}) (+0)")
    score += c10

    # C11: Distractors not flagged (5 pts)
    c11 = 0
    d001 = p3.get("RECON_D001", {})
    monb = p3.get("RECON_MON_B", {})

    if d001.get("status_name") != "Out for Repair":
        c11 += 2
        feedback.append("C11a: RECON-D001 (desktop distractor) not flagged (+2)")
    else:
        feedback.append("C11a: RECON-D001 (desktop) was incorrectly flagged (+0)")

    if monb.get("status_name") != "Out for Repair":
        c11 += 1
        feedback.append("C11b: RECON-MON-B (monitor distractor) not flagged (+1)")
    else:
        feedback.append("C11b: RECON-MON-B (monitor) was incorrectly flagged (+0)")

    if p3.get("RECON_L002_not_flagged", True):
        c11 += 2
        feedback.append("C11c: RECON-L002 (checked-in expired laptop) not flagged (+2)")
    else:
        feedback.append("C11c: RECON-L002 was incorrectly flagged as expired (it was already checked in) (+0)")
    score += c11

    # =================================================================
    # Phase 4: Organizational Update (12 pts)
    # =================================================================

    # C12: Department renamed (5 pts)
    if p4.get("department_renamed"):
        score += 5
        feedback.append("C12: Marketing renamed to Growth & Marketing (+5)")
    else:
        feedback.append("C12: Marketing department not renamed (+0)")

    # C13: Location created (4 pts)
    if p4.get("location_created"):
        score += 4
        feedback.append("C13: Building C - Floor 3 location created (+4)")
    else:
        feedback.append("C13: Building C - Floor 3 location not found (+0)")

    # C14: ppatel location updated (3 pts)
    if p4.get("ppatel_location_updated"):
        score += 3
        feedback.append("C14: ppatel location updated to Building C - Floor 3 (+3)")
    else:
        feedback.append(f"C14: ppatel location is '{p4.get('ppatel_current_location', 'unknown')}', expected 'Building C - Floor 3' (+0)")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }
