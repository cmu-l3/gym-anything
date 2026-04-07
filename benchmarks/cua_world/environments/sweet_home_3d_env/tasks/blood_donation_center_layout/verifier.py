#!/usr/bin/env python3
"""
Verifier for blood_donation_center_layout task.
"""

import json

def verify_blood_donation_center_layout(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if copy_from_env is None:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        result_path = copy_from_env("/tmp/blood_donation_center_layout_result.json")
        with open(result_path) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve result JSON: {e}"}

    score = 0
    feedback_parts = []

    furniture_count = result.get("furniture_count", 0)
    if furniture_count < 15:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong-target gate: only {furniture_count} furniture item(s) found. At least 15 items required to qualify for scoring."
        }

    # C1 (20 pts): Walls >= 4, doors >= 3, named rooms >= 5
    new_walls = result.get("new_walls", 0)
    new_doors = result.get("new_doors", 0)
    named_rooms = result.get("named_rooms", 0)
    
    c1_score = 0
    c1_parts = []
    if new_walls >= 4:
        c1_score += 8
        c1_parts.append(f"{new_walls} new walls")
    elif new_walls >= 2:
        c1_score += 4
        c1_parts.append(f"{new_walls} walls")
    
    if new_doors >= 3:
        c1_score += 6
        c1_parts.append(f"{new_doors} new doors")
    elif new_doors >= 1:
        c1_score += 3
        c1_parts.append(f"{new_doors} door(s)")
        
    if named_rooms >= 5:
        c1_score += 6
        c1_parts.append(f"{named_rooms} named rooms")
    elif named_rooms >= 3:
        c1_score += 3
        c1_parts.append(f"{named_rooms} named rooms")
        
    score += c1_score
    feedback_parts.append(f"C1 (Space planning): {', '.join(c1_parts) if c1_parts else 'no walls/doors/rooms'} [+{c1_score}/20]")

    # C2 (20 pts): Donor seats >= 6
    donor_seats = result.get("donor_seats_count", 0)
    if donor_seats >= 6:
        score += 20
        feedback_parts.append(f"C2 (Donation floor): {donor_seats} donor seats [+{20}/20]")
    elif donor_seats >= 3:
        score += 10
        feedback_parts.append(f"C2 (Donation floor): {donor_seats} donor seats (need 6) [+{10}/20]")
    else:
        feedback_parts.append(f"C2 (Donation floor): {donor_seats} donor seats (need 6) [+0/20]")

    # C3 (20 pts): Reception & Screening (Desks >= 3, Chairs >= 12)
    desks = result.get("desk_count", 0)
    chairs = result.get("chair_count", 0)
    if desks >= 3 and chairs >= 12:
        score += 20
        feedback_parts.append(f"C3 (Reception/Screening): {desks} desks, {chairs} chairs [+{20}/20]")
    elif desks >= 2 and chairs >= 6:
        score += 10
        feedback_parts.append(f"C3 (Reception/Screening): {desks} desks, {chairs} chairs [+{10}/20]")
    else:
        feedback_parts.append(f"C3 (Reception/Screening): {desks} desks, {chairs} chairs [+0/20]")

    # C4 (20 pts): Canteen & Processing (Tables >= 2, Appliances >= 2, Sinks >= 2, Storage >= 2)
    tables = result.get("table_count", 0)
    appliances = result.get("appliance_count", 0)
    sinks = result.get("sink_count", 0)
    storage = result.get("storage_count", 0)
    
    c4_score = 0
    if tables >= 2: c4_score += 5
    elif tables >= 1: c4_score += 2
    
    if appliances >= 2: c4_score += 5
    elif appliances >= 1: c4_score += 2
    
    if sinks >= 2: c4_score += 5
    elif sinks >= 1: c4_score += 2
    
    if storage >= 2: c4_score += 5
    elif storage >= 1: c4_score += 2
    
    score += c4_score
    feedback_parts.append(f"C4 (Canteen/Processing): {tables} tables, {appliances} appliances, {sinks} sinks, {storage} storage [+{c4_score}/20]")

    # C5 (20 pts): Dimensions & Polish
    dimensions = result.get("new_dimensions", 0)
    file_changed = result.get("file_changed", False)
    
    c5_score = 0
    if dimensions >= 2:
        c5_score += 10
    elif dimensions >= 1:
        c5_score += 5
        
    if file_changed:
        c5_score += 5
    if furniture_count >= 45:
        c5_score += 5
        
    score += c5_score
    feedback_parts.append(f"C5 (Polish): {dimensions} dimension lines, file changed={file_changed}, total items={furniture_count} [+{c5_score}/20]")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }