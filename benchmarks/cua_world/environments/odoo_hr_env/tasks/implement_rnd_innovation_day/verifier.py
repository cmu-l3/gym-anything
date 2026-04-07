#!/usr/bin/env python3
"""
Verifier for implement_rnd_innovation_day task.

Multi-criterion scoring (100 pts total, pass >= 70):

  Phase 1 - Leave Type Configuration (30 pts):
    C1  (8):  Leave type "R&D Innovation Day" exists
    C2 (10):  leave_validation_type = 'both' (dual approval)
    C3  (4):  requires_allocation = 'yes'
    C4  (8):  Mitchell Admin (uid=2) in responsible_ids

  Phase 2 - Accrual Plan (28 pts):
    C5  (6):  Accrual plan "R&D Innovation Accrual" exists
    C6  (6):  Plan has exactly 2 levels
    C7  (8):  Level 1: ~0.5 days/month, starts immediately
    C8  (8):  Level 2: ~1.0 day/month, starts after 12 months, cap 10 days

  Phase 3 - Allocation (18 pts):
    C9  (6):  Accrual allocation exists for Eli Lambert
    C10 (6):  Allocation linked to correct plan and leave type
    C11 (6):  Allocation is approved (state = validate or validate1)

  Phase 4 - Leave Request & Dual Approval (24 pts):
    C12 (6):  Leave request exists for Eli Lambert on 2026-07-15
    C13 (4):  Request is for "R&D Innovation Day" type
    C14 (14): Request FULLY approved: state = 'validate' (confirms both
              manager AND officer approval completed; 'validate1' = only first)
"""

import json
import os
import tempfile


def verify_implement_rnd_innovation_day(traj, env_info, task_info):
    """Verify the R&D Innovation Day leave benefit was fully implemented."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get("error"):
        return {"passed": False, "score": 0,
                "feedback": f"Error in result generation: {result['error']}"}

    score = 0
    feedback_parts = []

    # -------------------------------------------------------
    # Phase 1: Leave Type Configuration (30 pts)
    # -------------------------------------------------------
    lt = result.get("leave_type", {})

    if lt.get("found"):
        score += 8
        feedback_parts.append("Leave type found")

        if lt.get("leave_validation_type") == "both":
            score += 10
            feedback_parts.append("Dual approval configured")
        else:
            feedback_parts.append(f"Approval type is '{lt.get('leave_validation_type')}', expected 'both'")

        if lt.get("requires_allocation") == "yes":
            score += 4
            feedback_parts.append("Requires allocation = yes")
        else:
            feedback_parts.append(f"Requires allocation = '{lt.get('requires_allocation')}', expected 'yes'")

        responsible_ids = lt.get("responsible_ids", [])
        target_uid = task_info.get("metadata", {}).get("target_responsible_uid", 2)
        if target_uid in responsible_ids:
            score += 8
            feedback_parts.append("Mitchell Admin designated as officer")
        else:
            feedback_parts.append(f"Mitchell Admin (uid={target_uid}) not in responsible_ids {responsible_ids}")
    else:
        feedback_parts.append("Leave type 'R&D Innovation Day' NOT found")

    # -------------------------------------------------------
    # Phase 2: Accrual Plan (28 pts)
    # -------------------------------------------------------
    plan = result.get("accrual_plan", {})

    if plan.get("found"):
        score += 6
        feedback_parts.append("Accrual plan found")

        level_count = plan.get("level_count", 0)
        if level_count == 2:
            score += 6
            feedback_parts.append("Plan has 2 levels")
        else:
            feedback_parts.append(f"Plan has {level_count} level(s), expected 2")

        levels = plan.get("levels", [])
        if len(levels) >= 1:
            lvl1 = levels[0]
            rate1 = lvl1.get("added_value", 0)
            freq1 = lvl1.get("frequency", "")
            if abs(rate1 - 0.5) < 0.15 and freq1 == "monthly":
                score += 8
                feedback_parts.append(f"Level 1 correct: {rate1} days/month")
            else:
                feedback_parts.append(f"Level 1: rate={rate1} freq={freq1}, expected ~0.5 monthly")

        if len(levels) >= 2:
            lvl2 = levels[1]
            rate2 = lvl2.get("added_value", 0)
            freq2 = lvl2.get("frequency", "")
            start_count = lvl2.get("start_count", 0)
            start_type = lvl2.get("start_type", "")
            cap_on = lvl2.get("cap_accrued_time", False)
            max_leave = lvl2.get("maximum_leave", 0)

            level2_score = 0
            # Rate correct (~1.0 days/month)
            if abs(rate2 - 1.0) < 0.15 and freq2 == "monthly":
                level2_score += 3
            # Start condition (12 months or 1 year or 365 days)
            starts_after_12m = (
                (start_count == 12 and start_type == "month") or
                (start_count == 1 and start_type == "year") or
                (start_count == 365 and start_type == "day")
            )
            if starts_after_12m:
                level2_score += 3
            # Cap at 10 days
            if cap_on and abs(max_leave - 10.0) < 1.0:
                level2_score += 2

            score += level2_score
            if level2_score == 8:
                feedback_parts.append(f"Level 2 correct: {rate2} days/month, start after {start_count} {start_type}, cap {max_leave}")
            else:
                feedback_parts.append(f"Level 2 partial ({level2_score}/8): rate={rate2}, freq={freq2}, start={start_count} {start_type}, cap={cap_on}/{max_leave}")
    else:
        feedback_parts.append("Accrual plan 'R&D Innovation Accrual' NOT found")

    # -------------------------------------------------------
    # Phase 3: Allocation (18 pts)
    # -------------------------------------------------------
    alloc = result.get("allocation", {})

    if alloc.get("found"):
        score += 6
        feedback_parts.append("Accrual allocation found for Eli Lambert")

        # Check linked to correct plan and type
        alloc_plan_id = alloc.get("accrual_plan_id")
        expected_plan_id = plan.get("id")
        alloc_type_name = alloc.get("leave_type_name", "")

        plan_match = (expected_plan_id and alloc_plan_id == expected_plan_id)
        type_match = "innovation" in alloc_type_name.lower()

        if plan_match and type_match:
            score += 6
            feedback_parts.append("Allocation linked to correct plan and type")
        elif plan_match or type_match:
            score += 3
            feedback_parts.append(f"Allocation partially linked: plan_match={plan_match}, type_match={type_match}")
        else:
            feedback_parts.append(f"Allocation not linked correctly: plan_id={alloc_plan_id} (expected {expected_plan_id}), type='{alloc_type_name}'")

        if alloc.get("state") in ["validate", "validate1"]:
            score += 6
            feedback_parts.append(f"Allocation approved (state={alloc.get('state')})")
        else:
            feedback_parts.append(f"Allocation NOT approved (state={alloc.get('state')})")
    else:
        feedback_parts.append("No accrual allocation found for Eli Lambert")

    # -------------------------------------------------------
    # Phase 4: Leave Request & Dual Approval (24 pts)
    # -------------------------------------------------------
    req = result.get("leave_request", {})

    if req.get("found"):
        # Check date
        date_from = req.get("date_from", "")
        expected_date = task_info.get("metadata", {}).get("target_leave_request_date", "2026-07-15")
        if date_from == expected_date:
            score += 6
            feedback_parts.append(f"Leave request found for {date_from}")
        else:
            score += 3  # Partial: request exists but wrong date
            feedback_parts.append(f"Leave request date={date_from}, expected {expected_date}")

        # Check type
        req_type = req.get("leave_type_name", "")
        if "innovation" in req_type.lower():
            score += 4
            feedback_parts.append("Request is for R&D Innovation Day type")
        else:
            feedback_parts.append(f"Request type='{req_type}', expected 'R&D Innovation Day'")

        # Check FULL dual approval (the critical test)
        req_state = req.get("state", "")
        if req_state == "validate":
            # BOTH approvals completed
            score += 14
            feedback_parts.append("Leave request FULLY approved (both manager and officer)")
        elif req_state == "validate1":
            # Only first approval done - agent missed the second approval
            score += 5
            feedback_parts.append("Leave request only has FIRST approval (manager). Second approval (officer) NOT done.")
        elif req_state == "confirm":
            # Submitted but not approved at all
            score += 2
            feedback_parts.append("Leave request submitted but NOT approved at all")
        else:
            feedback_parts.append(f"Leave request state='{req_state}' (expected 'validate' for full dual approval)")
    else:
        feedback_parts.append("No leave request found for Eli Lambert")

    # -------------------------------------------------------
    # Final scoring
    # -------------------------------------------------------
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "leave_type": lt,
            "accrual_plan": {k: v for k, v in plan.items() if k != "levels"},
            "allocation_state": alloc.get("state"),
            "leave_request_state": req.get("state")
        }
    }
