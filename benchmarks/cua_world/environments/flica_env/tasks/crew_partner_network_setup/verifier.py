#!/usr/bin/env python3
"""
Verifier for crew_partner_network_setup task.

United Airlines Captain at ORD sets up Flight Crew View:
- Display name "Capt. Rodriguez | ORD" set: 25 pts
- Position set to Captain: 25 pts
- Home airport ORD configured: 15 pts
- Base airport ORD configured: 10 pts
- Friend fo.james@united.aero added: 9 pts
- Friend fa.chen@united.aero added: 8 pts
- Friend fa.garcia@united.aero added: 8 pts

Pass threshold: 60 points
"""
import json, tempfile, os, logging
logger = logging.getLogger(__name__)

def verify_crew_partner_network_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    task_name = "crew_partner_network_setup"
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env(f'/sdcard/{task_name}_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            os.unlink(tmp.name)
        score = 0
        parts = []
        if result.get('display_name_found'):
            score += 25; parts.append("Display name 'Capt. Rodriguez | ORD' set (25/25)")
        else:
            parts.append("Display name not set (0/25)")
        if result.get('position_found'):
            score += 25; parts.append("Position set to Captain (25/25)")
        else:
            parts.append("Position not set to Captain (0/25)")
        if result.get('home_airport_found'):
            score += 15; parts.append("Home airport ORD configured (15/15)")
        else:
            parts.append("Home airport ORD not configured (0/15)")
        if result.get('base_airport_found'):
            score += 10; parts.append("Base airport ORD configured (10/10)")
        else:
            parts.append("Base airport ORD not configured (0/10)")
        if result.get('friend1_found'):
            score += 9; parts.append("fo.james@united.aero added (9/9)")
        else:
            parts.append("fo.james@united.aero not found (0/9)")
        if result.get('friend2_found'):
            score += 8; parts.append("fa.chen@united.aero added (8/8)")
        else:
            parts.append("fa.chen@united.aero not found (0/8)")
        if result.get('friend3_found'):
            score += 8; parts.append("fa.garcia@united.aero added (8/8)")
        else:
            parts.append("fa.garcia@united.aero not found (0/8)")
        passed = score >= 60
        return {"passed": passed, "score": score, "feedback": " | ".join(parts)}
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
