#!/usr/bin/env python3
"""
Verifier for q4_compliance_data_fix task.

Setup seeds three categories of issues:
  1. 4 employees with invalid BRA_ID=99 (non-existent branch):
     - EMP 108 (Reid Ryan) -> correct: London (101)
     - EMP 120 (Jessica Owens) -> correct: London (101)
     - EMP 135 (Daisy Brooks) -> correct: Norwich (102)
     - EMP 148 (Jack West) -> correct: London (101)
  2. 2 employees with swapped departments:
     - EMP 113 (Miller Russell): set to IT (102), should be Accounts (106)
     - EMP 137 (Ryan Murphy): set to Accounts (106), should be IT (102)
  3. 5 new hires in q4_new_hires.csv to import:
     - EMP 5001 Christy Johny -> LONDON, Accounts
     - EMP 5002 Paul Aby -> LONDON, Marketing
     - EMP 5003 Rincy Devassy -> NORWICH, IT
     - EMP 5004 Majeesh Madhavan -> NORWICH, Production
     - EMP 5005 Alex Anto -> DUBLIN, Administration

Scoring (100 points total):
  - 4 branch fixes:               20 pts (5 pts each)
  - 2 department fixes:           20 pts (10 pts each)
  - 5 new hires imported:         40 pts (8 pts each)
  - New hires correct branch:     10 pts (2 pts each)
  - New hires correct department: 10 pts (2 pts each)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_q4_compliance_data_fix(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("C:/temp/q4_compliance_result.json", tmp.name)
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except OSError:
                pass

        branches_invalid = result.get("branches_still_invalid", 4)
        emp_108_fixed    = result.get("emp_108_branch_fixed", False)
        emp_120_fixed    = result.get("emp_120_branch_fixed", False)
        emp_135_fixed    = result.get("emp_135_branch_fixed", False)
        emp_148_fixed    = result.get("emp_148_branch_fixed", False)
        emp_113_fixed    = result.get("emp_113_dept_fixed", False)
        emp_137_fixed    = result.get("emp_137_dept_fixed", False)
        new_hires        = result.get("new_hires_imported", 0)
        nh_correct_bra   = result.get("new_hires_correct_branch", 0)
        nh_correct_dept  = result.get("new_hires_correct_dept", 0)

        # Wrong-target gate: nothing done
        if branches_invalid >= 4 and not emp_113_fixed and not emp_137_fixed and new_hires == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No work detected — branch errors unfixed, dept swaps unchanged, no new hires imported.",
            }

        score = 0
        feedback_parts = []
        subscores = {}

        # Criterion 1: Branch fixes (20 pts, 5 each)
        branch_fixes = [emp_108_fixed, emp_120_fixed, emp_135_fixed, emp_148_fixed]
        branch_fixed_count = sum(1 for x in branch_fixes if x)
        branch_pts = branch_fixed_count * 5
        score += branch_pts
        subscores["branches_fixed"] = branch_fixed_count
        bra_details = (
            f"EMP 108→{'✓' if emp_108_fixed else '✗'}(101) "
            f"EMP 120→{'✓' if emp_120_fixed else '✗'}(101) "
            f"EMP 135→{'✓' if emp_135_fixed else '✗'}(102) "
            f"EMP 148→{'✓' if emp_148_fixed else '✗'}(101)"
        )
        if branch_fixed_count == 4:
            feedback_parts.append(f"All 4 branch errors fixed (+20 pts)")
        elif branch_fixed_count > 0:
            feedback_parts.append(f"{branch_fixed_count}/4 branch errors fixed (+{branch_pts} pts) [{bra_details}]")
        else:
            feedback_parts.append(f"No branch errors fixed (0 pts) [{bra_details}]")

        # Criterion 2: Department fixes (20 pts, 10 each)
        dept_113_pts = 10 if emp_113_fixed else 0
        dept_137_pts = 10 if emp_137_fixed else 0
        score += dept_113_pts + dept_137_pts
        subscores["emp_113_fixed"] = emp_113_fixed
        subscores["emp_137_fixed"] = emp_137_fixed
        dept_fixed = sum([1 for x in [emp_113_fixed, emp_137_fixed] if x])
        if dept_fixed == 2:
            feedback_parts.append(f"Both department swaps corrected (+20 pts)")
        elif dept_fixed == 1:
            details = "EMP 113→Accounts(106) " if emp_113_fixed else "EMP 137→IT(102) "
            feedback_parts.append(f"1/2 department swaps corrected ({details}) (+{dept_113_pts + dept_137_pts} pts)")
        else:
            afd_113 = result.get("emp_113_afd_id", "?")
            afd_137 = result.get("emp_137_afd_id", "?")
            feedback_parts.append(f"Department swaps not fixed: EMP 113 AFD={afd_113}(need 106), EMP 137 AFD={afd_137}(need 102) (0 pts)")

        # Criterion 3: New hires imported (40 pts, 8 each)
        nh_pts = min(new_hires, 5) * 8
        score += nh_pts
        subscores["new_hires_imported"] = new_hires
        if new_hires >= 5:
            feedback_parts.append(f"All 5 new hires imported (+40 pts)")
        elif new_hires > 0:
            feedback_parts.append(f"{new_hires}/5 new hires imported (+{nh_pts} pts)")
        else:
            feedback_parts.append("No new hires imported (0 pts)")

        # Criterion 4: New hires correct branch (10 pts, 2 each)
        bra_pts = min(nh_correct_bra, 5) * 2
        score += bra_pts
        subscores["new_hires_correct_branch"] = nh_correct_bra
        if nh_correct_bra >= 5:
            feedback_parts.append(f"All 5 new hires in correct branches (+10 pts)")
        elif nh_correct_bra > 0:
            feedback_parts.append(f"{nh_correct_bra}/5 new hires in correct branches (+{bra_pts} pts)")
        elif new_hires > 0:
            feedback_parts.append("New hires not in correct branches (0 pts)")

        # Criterion 5: New hires correct department (10 pts, 2 each)
        dept_pts = min(nh_correct_dept, 5) * 2
        score += dept_pts
        subscores["new_hires_correct_dept"] = nh_correct_dept
        if nh_correct_dept >= 5:
            feedback_parts.append(f"All 5 new hires in correct departments (+10 pts)")
        elif nh_correct_dept > 0:
            feedback_parts.append(f"{nh_correct_dept}/5 new hires in correct departments (+{dept_pts} pts)")
        elif new_hires > 0:
            feedback_parts.append("New hires not in correct departments (0 pts)")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria evaluated",
            "subscores": subscores,
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
