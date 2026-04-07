#!/usr/bin/env python3
"""Verifier for predefined_kit_provisioning task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_predefined_kits(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    kits = result.get("kits", [])
    task_start = result.get("task_start", 0)
    initial_count = result.get("initial_kit_count", 0)
    current_count = result.get("current_kit_count", len(kits))

    # Helper function to find a kit by name
    def find_kit(target_name):
        for k in kits:
            if k["name"].strip().lower() == target_name.strip().lower():
                return k
        return None

    # Helper function to check item in category
    def check_item(kit, category, item_name, expected_qty):
        items = kit.get(category, [])
        for item in items:
            if item["name"].strip().lower() == item_name.strip().lower():
                if item["quantity"] == expected_qty:
                    return True, f"Found {expected_qty}x {item_name}"
                else:
                    return False, f"Found {item['quantity']}x {item_name} (Expected {expected_qty})"
        return False, f"Missing {item_name}"

    # Anti-gaming: Do nothing
    if current_count == initial_count:
        return {"passed": False, "score": 0, "feedback": "No new kits were created."}

    newly_created_count = 0
    for k in kits:
        if k.get("created_at", 0) >= task_start:
            newly_created_count += 1

    # ==============================================================
    # Kit 1: Standard Office Kit (28 points)
    # ==============================================================
    kit1 = find_kit("Standard Office Kit")
    if kit1:
        score += 5
        feedback.append("C1: Kit 'Standard Office Kit' exists (+5)")
        
        # Models (8 pts)
        m1_ok, m1_msg = check_item(kit1, "models", "Dell Latitude 5520", 1)
        m2_ok, m2_msg = check_item(kit1, "models", "Dell UltraSharp U2722D", 1)
        if m1_ok and m2_ok:
            score += 8
            feedback.append("C2: Kit 1 Models correct (+8)")
        else:
            feedback.append(f"C2: Kit 1 Models issue -> {m1_msg}, {m2_msg} (+0)")

        # Accessories (5 pts)
        a1_ok, a1_msg = check_item(kit1, "accessories", "Logitech C920 Webcam", 1)
        if a1_ok:
            score += 5
            feedback.append("C3: Kit 1 Accessories correct (+5)")
        else:
            feedback.append(f"C3: Kit 1 Accessories issue -> {a1_msg} (+0)")

        # Licenses (5 pts)
        l1_ok, l1_msg = check_item(kit1, "licenses", "Microsoft Office 365 Enterprise", 1)
        if l1_ok:
            score += 5
            feedback.append("C4: Kit 1 Licenses correct (+5)")
        else:
            feedback.append(f"C4: Kit 1 Licenses issue -> {l1_msg} (+0)")

        # Consumables (5 pts)
        c1_ok, c1_msg = check_item(kit1, "consumables", "HDMI Cables", 2)
        if c1_ok:
            score += 5
            feedback.append("C5: Kit 1 Consumables correct (+5)")
        else:
            feedback.append(f"C5: Kit 1 Consumables issue -> {c1_msg} (+0)")
    else:
        feedback.append("C1: Kit 'Standard Office Kit' missing (+0)")

    # ==============================================================
    # Kit 2: Developer Workstation Kit (29 points)
    # ==============================================================
    kit2 = find_kit("Developer Workstation Kit")
    if kit2:
        score += 5
        feedback.append("C6: Kit 'Developer Workstation Kit' exists (+5)")
        
        # Models (10 pts)
        m1_ok, m1_msg = check_item(kit2, "models", "HP EliteDesk 800 G6", 1)
        m2_ok, m2_msg = check_item(kit2, "models", "Dell UltraSharp U2722D", 2)
        if m1_ok and m2_ok:
            score += 10
            feedback.append("C7: Kit 2 Models correct (+10)")
        else:
            feedback.append(f"C7: Kit 2 Models issue -> {m1_msg}, {m2_msg} (+0)")

        # Accessories (7 pts)
        a1_ok, a1_msg = check_item(kit2, "accessories", "Dell USB-C Dock WD19", 1)
        a2_ok, a2_msg = check_item(kit2, "accessories", "Logitech MX Master 3", 1)
        if a1_ok and a2_ok:
            score += 7
            feedback.append("C8: Kit 2 Accessories correct (+7)")
        else:
            feedback.append(f"C8: Kit 2 Accessories issue -> {a1_msg}, {a2_msg} (+0)")

        # Licenses (7 pts)
        l1_ok, l1_msg = check_item(kit2, "licenses", "Microsoft Windows 11 Enterprise", 1)
        l2_ok, l2_msg = check_item(kit2, "licenses", "Adobe Creative Cloud", 1)
        if l1_ok and l2_ok:
            score += 7
            feedback.append("C9: Kit 2 Licenses correct (+7)")
        else:
            feedback.append(f"C9: Kit 2 Licenses issue -> {l1_msg}, {l2_msg} (+0)")
    else:
        feedback.append("C6: Kit 'Developer Workstation Kit' missing (+0)")

    # ==============================================================
    # Kit 3: Executive Mobile Kit (33 points)
    # ==============================================================
    kit3 = find_kit("Executive Mobile Kit")
    if kit3:
        score += 5
        feedback.append("C10: Kit 'Executive Mobile Kit' exists (+5)")
        
        # Models (5 pts)
        m1_ok, m1_msg = check_item(kit3, "models", "Apple MacBook Pro 16", 1)
        if m1_ok:
            score += 5
            feedback.append("C11: Kit 3 Models correct (+5)")
        else:
            feedback.append(f"C11: Kit 3 Models issue -> {m1_msg} (+0)")

        # Accessories (8 pts)
        a1_ok, a1_msg = check_item(kit3, "accessories", "CalDigit TS4 Thunderbolt", 1)
        a2_ok, a2_msg = check_item(kit3, "accessories", "Jabra Evolve2 75", 1)
        if a1_ok and a2_ok:
            score += 8
            feedback.append("C12: Kit 3 Accessories correct (+8)")
        else:
            feedback.append(f"C12: Kit 3 Accessories issue -> {a1_msg}, {a2_msg} (+0)")

        # Licenses (10 pts)
        l1_ok, l1_msg = check_item(kit3, "licenses", "Microsoft Office 365 Enterprise", 1)
        l2_ok, l2_msg = check_item(kit3, "licenses", "Zoom Workplace", 1)
        l3_ok, l3_msg = check_item(kit3, "licenses", "Slack Business+", 1)
        if l1_ok and l2_ok and l3_ok:
            score += 10
            feedback.append("C13: Kit 3 Licenses correct (+10)")
        else:
            feedback.append(f"C13: Kit 3 Licenses issue -> {l1_msg}, {l2_msg}, {l3_msg} (+0)")

        # Consumables (5 pts)
        c1_ok, c1_msg = check_item(kit3, "consumables", "USB-C Cables", 1)
        if c1_ok:
            score += 5
            feedback.append("C14: Kit 3 Consumables correct (+5)")
        else:
            feedback.append(f"C14: Kit 3 Consumables issue -> {c1_msg} (+0)")
    else:
        feedback.append("C10: Kit 'Executive Mobile Kit' missing (+0)")

    # ==============================================================
    # Global verification (10 points)
    # ==============================================================
    net_new_kits = current_count - initial_count
    if net_new_kits == 3:
        score += 5
        feedback.append("C15: Exactly 3 new kits created (+5)")
    else:
        feedback.append(f"C15: Found {net_new_kits} new kits, expected 3 (+0)")

    if newly_created_count >= 2:
        score += 5
        feedback.append("C16: Kits passed anti-gaming timestamp check (+5)")
    else:
        feedback.append("C16: Kits failed timestamp check (were they created before task?) (+0)")

    # Normalize score strictly to 100 just in case
    score = max(0, min(100, score))

    passed = score >= 60 and kit1 is not None and kit2 is not None

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }