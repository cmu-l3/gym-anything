#!/usr/bin/env python3
"""Verifier for flood_damage_insurance_claim task."""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/flood_damage_result.json"

def verify_flood_damage_insurance_claim(traj, env_info, task_info):
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
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    assets = result.get("assets", {})
    report = result.get("report_file", {})

    repairable = ["FD01", "FD02", "FD05"]
    writeoff = ["FD03", "FD04", "FD06"]

    # --- Do-nothing gate ---
    any_asset_changed = False
    for tag in repairable + writeoff:
        ast = assets.get(tag, {})
        if ast.get("status_name") != "Ready to Deploy" or "IC-2025-0342" in ast.get("notes", ""):
            any_asset_changed = True
            break
            
    if not any_asset_changed and not report.get("exists"):
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No assets changed and no report created."}

    # --- C1: Repairable statuses (15 pts) ---
    c1_correct = 0
    for tag in repairable:
        ast = assets.get(tag, {})
        if ast.get("status_name") == "Out for Repair":
            c1_correct += 1
        else:
            feedback.append(f"C1: {tag} status is '{ast.get('status_name')}', expected 'Out for Repair'")
    
    if c1_correct == 3:
        score += 15
        feedback.append("C1: All 3 repairable assets set to 'Out for Repair' (+15)")
    else:
        pts = c1_correct * 5
        score += pts
        feedback.append(f"C1: {c1_correct}/3 repairable assets correctly updated (+{pts})")

    # --- C2: Write-off statuses (15 pts) ---
    c2_correct = 0
    for tag in writeoff:
        ast = assets.get(tag, {})
        if ast.get("status_name") in ["Lost/Stolen", "Archived"]:
            c2_correct += 1
        else:
            feedback.append(f"C2: {tag} status is '{ast.get('status_name')}', expected 'Lost/Stolen' or 'Archived'")
            
    if c2_correct == 3:
        score += 15
        feedback.append("C2: All 3 write-off assets set to 'Lost/Stolen' (+15)")
    else:
        pts = c2_correct * 5
        score += pts
        feedback.append(f"C2: {c2_correct}/3 write-off assets correctly updated (+{pts})")

    # --- C3: Notes (20 pts) ---
    c3_correct = 0
    for tag in repairable + writeoff:
        notes = assets.get(tag, {}).get("notes", "")
        if "IC-2025-0342" in notes:
            c3_correct += 1
        else:
            feedback.append(f"C3: {tag} notes missing claim number")
            
    if c3_correct == 6:
        score += 20
        feedback.append("C3: All 6 assets have insurance claim note (+20)")
    else:
        pts = int(20 * (c3_correct / 6))
        score += pts
        feedback.append(f"C3: {c3_correct}/6 assets have correct notes (+{pts})")

    # --- C4: Report file exists (5 pts) ---
    content = ""
    if report.get("exists"):
        score += 5
        feedback.append("C4: Report file exists (+5)")
        content = report.get("content", "")
    else:
        feedback.append("C4: Report file missing (+0)")

    # --- C5: Report contains all asset tags (10 pts) ---
    if content:
        found_tags = sum(1 for tag in repairable + writeoff if f"ASSET-{tag}" in content)
        if found_tags == 6:
            score += 10
            feedback.append("C5: Report contains all 6 asset tags (+10)")
        else:
            pts = int(10 * (found_tags / 6))
            score += pts
            feedback.append(f"C5: Report contains {found_tags}/6 asset tags (+{pts})")
    else:
        feedback.append("C5: Cannot check tags, report empty (+0)")

    # --- C6: Report total value correct (15 pts) ---
    if content:
        clean_content = content.replace(",", "")
        if re.search(r'14[.,]?850', clean_content):
            score += 15
            feedback.append("C6: Report contains correct total $14,850 (+15)")
        else:
            feedback.append("C6: Report missing total $14,850 (+0)")
    else:
        feedback.append("C6: Cannot check total, report empty (+0)")

    # --- C7: Report breakdown correct (10 pts) ---
    if content:
        clean_content = content.replace(",", "")
        brk_score = 0
        if re.search(r'11[.,]?700', clean_content):
            brk_score += 5
            feedback.append("C7a: Report contains write-off subtotal $11,700 (+5)")
        else:
            feedback.append("C7a: Report missing write-off subtotal (+0)")
            
        if re.search(r'3[.,]?150', clean_content):
            brk_score += 5
            feedback.append("C7b: Report contains repairable subtotal $3,150 (+5)")
        else:
            feedback.append("C7b: Report missing repairable subtotal (+0)")
            
        score += brk_score
    else:
        feedback.append("C7: Cannot check breakdown, report empty (+0)")

    # --- C8: No collateral damage (10 pts) ---
    fd07 = assets.get("FD07", {})
    if fd07.get("status_name") == "Ready to Deploy" and not fd07.get("notes"):
        score += 10
        feedback.append("C8: Distractor asset ASSET-FD07 untouched (+10)")
    else:
        feedback.append("C8: Distractor asset ASSET-FD07 was wrongly modified (+0)")

    # Pass threshold
    passed = score >= 60 and c1_correct >= 2 and c2_correct >= 2

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }