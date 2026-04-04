#!/usr/bin/env python3
"""
Verifier for Loyalty Tier Classification Task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_loyalty_tier_classification(traj, env_info, task_info):
    """
    Verifies the loyalty tier task based on database state and report file.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    score = 0
    feedback = []
    
    db_state = result.get("db_state", {})
    report = result.get("report", {})
    
    # ---------------------------------------------------------
    # 1. Schema Verification (20 points)
    # ---------------------------------------------------------
    
    # Class LoyaltyTiers exists (10 pts)
    if db_state.get("class_LoyaltyTiers_exists"):
        score += 10
        feedback.append("LoyaltyTiers class created.")
    else:
        feedback.append("LoyaltyTiers class missing.")

    # Edge class BelongsToTier exists (5 pts)
    if db_state.get("class_BelongsToTier_exists"):
        score += 5
        feedback.append("BelongsToTier edge class created.")
    else:
        feedback.append("BelongsToTier edge class missing.")

    # Profiles has LoyaltyTier property (5 pts)
    if "LoyaltyTier" in db_state.get("profiles_properties", []):
        score += 5
        feedback.append("Profiles.LoyaltyTier property added.")
    else:
        feedback.append("Profiles.LoyaltyTier property missing.")

    # ---------------------------------------------------------
    # 2. Data Definitions Verification (5 points)
    # ---------------------------------------------------------
    
    # Check if 4 tiers exist with correct names and reasonable min spend
    tiers = db_state.get("tiers_data", [])
    tier_names = set(t.get("TierName") for t in tiers)
    expected_tiers = {"Platinum", "Gold", "Silver", "Bronze"}
    
    if len(tiers) == 4 and tier_names == expected_tiers:
        # Check properties are populated
        if all("MinSpend" in t and "Benefits" in t for t in tiers):
            score += 5
            feedback.append("Loyalty tier definitions are correct.")
        else:
            feedback.append("Loyalty tier definitions missing properties.")
    else:
        feedback.append(f"Loyalty tier definitions incorrect. Found: {tier_names}")

    # ---------------------------------------------------------
    # 3. Classification Logic Verification (65 points)
    # ---------------------------------------------------------
    
    profiles = db_state.get("profiles", [])
    total_profiles = len(profiles)
    correct_prop_count = 0
    correct_edge_count = 0
    platinum_members = [] # For report checking
    
    if total_profiles == 0:
        return {"passed": False, "score": score, "feedback": " ".join(feedback) + " No profiles found in DB."}

    for p in profiles:
        spend = p.get("calculated_spend", 0)
        
        # Ground Truth Logic
        if spend >= 3000:
            expected = "Platinum"
            platinum_members.append(p.get("Name"))
            platinum_members.append(p.get("Surname"))
        elif spend >= 1500:
            expected = "Gold"
        elif spend >= 500:
            expected = "Silver"
        else:
            expected = "Bronze"
            
        # Check Property
        actual_prop = p.get("actual_tier_prop")
        if actual_prop == expected:
            correct_prop_count += 1
            
        # Check Edge
        actual_edge = p.get("linked_tier_edge")
        if actual_edge == expected:
            correct_edge_count += 1

    # Scoring for Property classification (max 30)
    prop_score = (correct_prop_count / total_profiles) * 30
    score += prop_score
    
    # Scoring for Edge classification (max 35)
    edge_score = (correct_edge_count / total_profiles) * 35
    score += edge_score
    
    if prop_score > 25:
        feedback.append(f"Profile properties correctly classified ({correct_prop_count}/{total_profiles}).")
    else:
        feedback.append(f"Profile properties classification accuracy low ({correct_prop_count}/{total_profiles}).")

    if edge_score > 30:
        feedback.append(f"Edges correctly linked ({correct_edge_count}/{total_profiles}).")
    else:
        feedback.append(f"Edge linking accuracy low ({correct_edge_count}/{total_profiles}).")

    # ---------------------------------------------------------
    # 4. Report Verification (10 points)
    # ---------------------------------------------------------
    
    if report.get("exists") and report.get("created_during_task"):
        content = report.get("content", "").lower()
        score += 5
        feedback.append("Report file created.")
        
        # Check for keywords
        found_plat = any(m.lower() in content for m in platinum_members if m)
        found_counts = "count" in content or "total" in content
        
        if found_plat and found_counts:
            score += 5
            feedback.append("Report content verified.")
        else:
            feedback.append("Report missing required info (platinum members or counts).")
    elif not report.get("exists"):
        feedback.append("Report file not found.")
    else:
        feedback.append("Report file exists but timestamp is old.")

    # ---------------------------------------------------------
    # Final Result
    # ---------------------------------------------------------
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }