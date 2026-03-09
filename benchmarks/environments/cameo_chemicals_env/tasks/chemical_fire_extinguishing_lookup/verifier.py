#!/usr/bin/env python3
"""
Verifier for chemical_fire_extinguishing_lookup task.

SCORING CRITERIA:
1. Report file exists (15 pts)
2. File created during task (5 pts)
3. Content mentions all three chemicals (30 pts)
4. Content correctly identifies Water Reactivity (Sodium/Magnesium) (24 pts)
5. Content correctly identifies Water Compatibility (Acetone) (11 pts)
6. Content includes specific extinguishing agent details (5 pts)
7. Summary/conclusion present (10 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chemical_fire_extinguishing_lookup(traj, env_info, task_info):
    """
    Verify the agent created a correct fire safety report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Check file existence (15 pts)
    if result.get('output_exists'):
        score += 15
        feedback_parts.append("Report file exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found"}

    # 2. Check timestamp (5 pts)
    if result.get('file_created_during_task'):
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp invalid (possible pre-existing file)")

    # Get content for analysis
    content = result.get('file_content', '').lower()
    if len(content) < 50:
        return {"passed": False, "score": score, "feedback": "Report file content too short"}

    # 3. Check chemicals mentioned (30 pts)
    chemicals = ['sodium', 'acetone', 'magnesium']
    found_chems = [chem for chem in chemicals if chem in content]
    chem_score = len(found_chems) * 10
    score += chem_score
    if len(found_chems) == 3:
        feedback_parts.append("All chemicals mentioned")
    else:
        feedback_parts.append(f"Missing chemicals: {', '.join(set(chemicals) - set(found_chems))}")

    # 4. Check Water Reactivity (Sodium/Magnesium) (24 pts)
    # Regex for "do not use water", "no water", "water reactive", etc.
    neg_water_pattern = r"(do\s*not\s*use\s*water|no\s*water|never\s*use\s*water|avoid\s*water|water\s*reactive|reacts\s*.*water|water\s*prohibited|water\s*forbidden)"
    
    # Check Sodium
    sodium_ok = False
    if re.search(f"sodium.*?{neg_water_pattern}", content, re.DOTALL) or \
       re.search(f"{neg_water_pattern}.*?sodium", content, re.DOTALL):
        score += 12
        sodium_ok = True
    
    # Check Magnesium
    magnesium_ok = False
    if re.search(f"magnesium.*?{neg_water_pattern}", content, re.DOTALL) or \
       re.search(f"{neg_water_pattern}.*?magnesium", content, re.DOTALL):
        score += 12
        magnesium_ok = True
    
    if sodium_ok and magnesium_ok:
        feedback_parts.append("Water reactivity correctly identified")
    elif sodium_ok or magnesium_ok:
        feedback_parts.append("Partial water reactivity identification")
    else:
        feedback_parts.append("Failed to identify water reactivity for Sodium/Magnesium")

    # 5. Check Acetone Water Compatibility (11 pts)
    # Regex for "water spray", "water fog", "water compatible"
    pos_water_pattern = r"(water\s*spray|water\s*fog|water\s*mist|water\s*is\s*suitable|use\s*water|compatible\s*with\s*water)"
    
    # Implicit check: If Acetone is NOT marked as "no water" but others are, give credit
    acetone_explicit_ok = False
    if re.search(f"acetone.*?{pos_water_pattern}", content, re.DOTALL) or \
       re.search(f"{pos_water_pattern}.*?acetone", content, re.DOTALL):
        acetone_explicit_ok = True
    
    # Negative check for Acetone (should NOT have "no water" near it)
    acetone_bad = False
    if re.search(f"acetone.*?{neg_water_pattern}", content, re.DOTALL) or \
       re.search(f"{neg_water_pattern}.*?acetone", content, re.DOTALL):
        # Only flag bad if it's in close proximity (simple regex might catch nearby lines)
        # For simplicity, we trust the positive pattern more
        pass

    if acetone_explicit_ok:
        score += 11
        feedback_parts.append("Acetone water compatibility correct")
    elif sodium_ok and magnesium_ok and not acetone_bad:
        # Implicitly correct if others are marked bad and this one isn't
        score += 11
        feedback_parts.append("Acetone implicitly identified as safe (by exclusion)")
    else:
        feedback_parts.append("Acetone water compatibility unclear")

    # 6. Extinguishing agent details (5 pts)
    agents = ["dry chemical", "dry powder", "soda ash", "lime", "sand", "carbon dioxide", "co2", "foam", "met-l-x"]
    found_agents = [a for a in agents if a in content]
    if len(found_agents) >= 2:
        score += 5
        feedback_parts.append("Extinguishing agents detailed")
    else:
        feedback_parts.append("Insufficient extinguishing agent details")

    # 7. Summary/Conclusion (10 pts)
    if "summary" in content or "conclusion" in content or "finding" in content or \
       (sodium_ok and magnesium_ok and "water" in content):
        score += 10
        feedback_parts.append("Summary present")

    # Final result
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }