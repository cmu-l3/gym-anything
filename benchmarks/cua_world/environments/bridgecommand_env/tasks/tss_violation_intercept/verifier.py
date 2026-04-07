#!/usr/bin/env python3
"""
Verifier for TSS Violation Intercept task.

Verifies:
1. Scenario creation (directory and 3 INI files).
2. Own ship configuration (Patrol vessel, correct heading for SW lane).
3. Traffic configuration (At least 1 Rogue going NE, 1 Compliant going SW).
4. Briefing document content (mentions Rule 10).
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tss_violation_intercept(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    rogue_heading_range = metadata.get('rogue_heading_range', [20, 70])
    compliant_heading_range = metadata.get('compliant_heading_range', [200, 250])

    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Scenario Existence & Anti-Gaming (20 pts)
    if result.get('scenario_exists', False) and result.get('files_created_during_task', False):
        score += 20
        feedback_parts.append("Scenario created successfully")
    elif result.get('scenario_exists', False):
        score += 5
        feedback_parts.append("Scenario exists but timestamps are old (anti-gaming fail)")
    else:
        feedback_parts.append("Scenario directory not created")
        return {"passed": False, "score": 0, "feedback": "Scenario not created"}

    # 2. Own Ship Configuration (15 pts)
    ownship = result.get('ownship', {})
    own_name = ownship.get('ShipName', '')
    own_heading = float(ownship.get('InitialBearing', -1))
    
    if "patrol" in own_name.lower() or "cg" in own_name.lower():
        score += 5
        feedback_parts.append("Ownship name correct")
    else:
        feedback_parts.append(f"Ownship name '{own_name}' does not indicate patrol vessel")

    # Check Ownship Heading (Should be SW ~225)
    if compliant_heading_range[0] <= own_heading <= compliant_heading_range[1]:
        score += 10
        feedback_parts.append(f"Ownship heading {own_heading} correct (SW)")
    else:
        feedback_parts.append(f"Ownship heading {own_heading} incorrect (expected SW ~225)")

    # 3. Traffic Configuration (50 pts)
    traffic = result.get('traffic', [])
    
    rogue_found = False
    compliant_found = False
    head_on_geometry = False
    
    for v in traffic:
        try:
            # Check legs first for heading, falling back to initial bearing
            # BC INI parsing might put leg info in 'Legs' or 'Bearing(x,y)'
            # Our simple parser captured indexed keys. 
            # Ideally we check the first leg bearing if available, else vague check.
            
            # Simple check using 'InitialBearing' if provided, or inferring from logic
            # Note: Bridge Command 'othership.ini' usually uses Leg(N,M)=Bearing,Speed,Dist
            # The simple parser puts these in the dict.
            # Let's try to extract ANY bearing.
            
            bearings = []
            # Look for keys like "Leg(1,1)" or just scan values that look like legs
            # Actually, the parser puts "Leg" or "Bearing" keys if present.
            # Let's rely on the parser output structure.
            
            # If the user followed standard INI format "Leg(1,1)=225,10,5"
            # Our parser might have flattened it or kept it. 
            # Let's assume the user set "Type" and we check the legs logic conceptually
            # or rely on simple string parsing if the user set explicit params.
            
            # ROBUST CHECK:
            # We look for a vessel moving roughly NE (Rogue) and one moving SW (Compliant)
            
            # Extract heading from Leg 1
            # Keys like 'Leg(1,1)' might be in the dictionary
            # The parser put specific keys in. Let's look for 'Bearing' in keys or parse 'Leg'
            
            v_heading = -1
            
            # Iterate keys to find first leg definition
            for k, val in v.items():
                if k.startswith("Leg"):
                    # Format: bearing, speed, distance
                    try:
                        v_heading = float(val.split(',')[0])
                        break
                    except:
                        pass
            
            if v_heading == -1:
                 # Fallback if they used different format
                 continue

            # Check if Rogue (NE)
            if rogue_heading_range[0] <= v_heading <= rogue_heading_range[1]:
                rogue_found = True
                
            # Check if Compliant (SW)
            if compliant_heading_range[0] <= v_heading <= compliant_heading_range[1]:
                compliant_found = True
                
        except Exception as e:
            continue

    if rogue_found:
        score += 30
        feedback_parts.append("Rogue vessel (NE heading) found")
    else:
        feedback_parts.append("No rogue vessel (NE heading) found")

    if compliant_found:
        score += 10
        feedback_parts.append("Compliant vessel (SW heading) found")
    else:
        feedback_parts.append("No compliant vessel found")
        
    # Bonus: Geometric conflict (Rogue heading approx reciprocal to Ownship)
    if rogue_found and (compliant_heading_range[0] <= own_heading <= compliant_heading_range[1]):
        score += 10
        feedback_parts.append("Head-on intercept geometry valid")

    # 4. Briefing Document (15 pts)
    briefing_content = result.get('briefing_content', '').lower()
    if result.get('briefing_exists'):
        if "rule 10" in briefing_content:
            score += 15
            feedback_parts.append("Briefing cites Rule 10")
        elif "separation" in briefing_content:
            score += 10
            feedback_parts.append("Briefing mentions separation scheme but missed Rule 10")
        else:
            score += 5
            feedback_parts.append("Briefing exists but lacks specific regulatory citations")
    else:
        feedback_parts.append("Briefing document missing")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }