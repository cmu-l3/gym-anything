#!/usr/bin/env python3
"""
Verifier for warehouse_fulfillment_layout task.

Occupation: Logistics Operations Manager
Industry: E-commerce & Logistics

Features required: wall creation, room definition, furniture placement, label placement

Scoring (total 100 pts, pass threshold 70):
  C1 (25 pts): Storage racking -- >=10 shelves/bookcases/cabinets (partial >=5 -> 12 pts)
  C2 (20 pts): Workstations -- >=4 desks/tables + >=4 chairs (partial >=2 desks + >=2 chairs -> 10 pts)
  C3 (20 pts): Partition walls -- >=3 new walls + >=2 doors placed (partial >=1 wall + >=1 door -> 10 pts)
  C4 (20 pts): Zone identification -- >=4 rooms defined OR labels placed (partial >=2 -> 10 pts)
  C5 (15 pts): Support facilities + total + save -- >=1 toilet + >=1 appliance (5), >=30 total items (5), file changed (5)

Wrong-target gate: if total furniture < 8, return score=0.
Anti-Gaming: Trajectory VLM check ensures agent progressed through real UI workflows.
"""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_trajectory_via_vlm(traj, env_info):
    """
    Optional verification using VLM to ensure the agent actually interacted with Sweet Home 3D.
    Looks for trajectory frames showing the software UI and layout progression.
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=4)
        if not frames:
            return {"authentic": True, "reason": "No frames available"}

        prompt = """
        Review these screenshots from a computer agent session.
        The task was to use Sweet Home 3D to design a warehouse layout (placing walls, rooms, shelving, desks).
        
        Is there evidence that the agent actually interacted with the Sweet Home 3D application to create a 3D/2D layout?
        Look for:
        - Sweet Home 3D user interface (catalog on left, 2D plan on top, 3D view on bottom)
        - Progression of placing items, walls, or labels
        - Authentic CAD/design work happening.

        Respond in JSON:
        {
            "is_authentic_work": true/false,
            "reasoning": "brief explanation"
        }
        """
        
        vlm_result = query_vlm(prompt=prompt, images=frames)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            return {
                "authentic": parsed.get("is_authentic_work", True),
                "reason": parsed.get("reasoning", "")
            }
    except Exception as e:
        logger.warning(f"VLM verification failed or unavailable: {e}")
        
    return {"authentic": True, "reason": "VLM not executed"}


def verify_warehouse_fulfillment_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/warehouse_fulfillment_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 8:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Wrong-target gate: only {furniture_count} furniture item(s) found. "
                "At least 8 items required to qualify for scoring."
            )
        }

    # Extract parsed elements
    shelf_count = result.get("shelf_count", 0)
    desk_count = result.get("desk_count", 0)
    chair_count = result.get("chair_count", 0)
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    zone_ids = result.get("zone_identifiers", 0) # new_rooms + new_labels
    toilet_count = result.get("toilet_count", 0)
    appliance_count = result.get("appliance_count", 0)
    file_changed = result.get("file_changed", False)

    # ── C1 (25 pts): Storage racking ──────────────────────────────────────────
    if shelf_count >= 10:
        score += 25
        feedback_parts.append(f"PASS C1: Storage racking ({shelf_count} shelves/racks placed) [+25]")
    elif shelf_count >= 5:
        score += 12
        feedback_parts.append(f"PARTIAL C1: Partial storage racking ({shelf_count} shelves, need >=10) [+12]")
    else:
        feedback_parts.append(f"FAIL C1: Insufficient storage racking ({shelf_count} shelves, need >=10)")

    # ── C2 (20 pts): Workstations ─────────────────────────────────────────────
    if desk_count >= 4 and chair_count >= 4:
        score += 20
        feedback_parts.append(f"PASS C2: Workstations ({desk_count} desks, {chair_count} chairs) [+20]")
    elif desk_count >= 2 and chair_count >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C2: Partial workstations ({desk_count} desks, {chair_count} chairs) [+10]")
    else:
        feedback_parts.append(f"FAIL C2: Insufficient workstations (need >=4 desks + >=4 chairs)")

    # ── C3 (20 pts): Partition walls + doors ──────────────────────────────────
    if new_walls >= 3 and new_doors >= 2:
        score += 20
        feedback_parts.append(f"PASS C3: Partition walls and doors ({new_walls} new walls, {new_doors} doors) [+20]")
    elif new_walls >= 1 and new_doors >= 1:
        score += 10
        feedback_parts.append(f"PARTIAL C3: Partial walls/doors ({new_walls} new walls, {new_doors} doors) [+10]")
    elif new_walls >= 1 or new_doors >= 1:
        score += 5
        feedback_parts.append(f"PARTIAL C3: Minimal boundaries ({new_walls} walls, {new_doors} doors) [+5]")
    else:
        feedback_parts.append(f"FAIL C3: No partition walls/doors created for office/breakroom separation")

    # ── C4 (20 pts): Zone identification ──────────────────────────────────────
    if zone_ids >= 4:
        score += 20
        feedback_parts.append(f"PASS C4: Zone identification ({zone_ids} rooms defined or labels placed) [+20]")
    elif zone_ids >= 2:
        score += 10
        feedback_parts.append(f"PARTIAL C4: Partial zone identification ({zone_ids} identifiers, need >=4) [+10]")
    else:
        feedback_parts.append(f"FAIL C4: Missing zone labels or room definitions (need >=4)")

    # ── C5 (15 pts): Support facilities + total count + file changed ──────────
    c5_score = 0
    c5_parts = []
    
    if toilet_count >= 1 and appliance_count >= 1:
        c5_score += 5
        c5_parts.append(f"facilities OK ({toilet_count} toilets, {appliance_count} appliances)")
    
    if furniture_count >= 30:
        c5_score += 5
        c5_parts.append(f"count OK ({furniture_count} total items)")
        
    if file_changed:
        c5_score += 5
        c5_parts.append("file modified")
        
    score += c5_score
    
    if c5_score == 15:
        feedback_parts.append(f"PASS C5: {', '.join(c5_parts)} [+15]")
    elif c5_score > 0:
        feedback_parts.append(f"PARTIAL C5: {', '.join(c5_parts)} [+{c5_score}]")
    else:
        feedback_parts.append(f"FAIL C5: Need >=1 toilet/appliance, >=30 items, and file changed")

    # ── Anti-Gaming VLM Trajectory Check ──────────────────────────────────────
    vlm_result = verify_trajectory_via_vlm(traj, env_info)
    if not vlm_result.get("authentic", True):
        # Heavy penalty if VLM detects blatant spoofing / no actual UI interaction
        score = min(score, 20)
        feedback_parts.append(f"WARNING: VLM trajectory check flagged activity as unauthentic: {vlm_result.get('reason')}. Score capped.")
    
    passed = score >= 70
    summary = (
        f"Score: {score}/100 | Furniture: {furniture_count} items "
        f"(shelves={shelf_count}, desks={desk_count}, chairs={chair_count}, "
        f"walls={new_walls}, doors={new_doors}, zones={zone_ids})"
    )
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }