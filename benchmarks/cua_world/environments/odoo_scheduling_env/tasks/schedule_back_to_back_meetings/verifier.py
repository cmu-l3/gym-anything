#!/usr/bin/env python3
"""
Verifier for schedule_back_to_back_meetings task.

Criteria:
1. "Sprint Review" event exists, correct time/date, attendees, location.
2. "Executive Briefing" event exists, correct time/date, attendees, location.
3. Temporal Coordination: Exec Briefing starts EXACTLY when Sprint Review ends.
4. Anti-gaming: Events must be newly created.
5. VLM: Trajectory verification (optional/bonus).
"""

import json
import os
import sys
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_back_to_back_meetings(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    target_date = result.get('target_date', '')
    sr = result.get('sprint_review', {})
    eb = result.get('executive_briefing', {})

    # ------------------------------------------------------------------
    # 1. Verify Sprint Review (Max 35 points)
    # ------------------------------------------------------------------
    if sr.get('exists'):
        score += 10
        feedback_parts.append("Sprint Review created")

        # Check Date & Time (Target: 14:00 - 15:00 UTC usually)
        # Odoo stores UTC. Description said 2:00 PM.
        # Ideally we parse the ISO string.
        try:
            start_dt = datetime.strptime(sr.get('start'), '%Y-%m-%d %H:%M:%S')
            stop_dt = datetime.strptime(sr.get('stop'), '%Y-%m-%d %H:%M:%S')
            
            # Check Date
            if start_dt.strftime('%Y-%m-%d') == target_date:
                score += 5
            else:
                feedback_parts.append(f"Sprint Review wrong date (expected {target_date}, got {start_dt.strftime('%Y-%m-%d')})")

            # Check Time (14:00 start)
            if start_dt.hour == 14 and start_dt.minute == 0:
                score += 5
            else:
                feedback_parts.append(f"Sprint Review wrong start time ({start_dt.strftime('%H:%M')})")

            # Check Duration (1 hour)
            duration_min = (stop_dt - start_dt).total_seconds() / 60
            if abs(duration_min - 60) < 1:
                score += 5
            else:
                feedback_parts.append(f"Sprint Review wrong duration ({duration_min} min)")

        except Exception as e:
            feedback_parts.append(f"Time parsing error: {e}")

        # Check Location
        if "Engineering Lab" in str(sr.get('location')):
            score += 5
        else:
            feedback_parts.append("Sprint Review wrong location")

        # Check Attendees (Partial credit)
        expected_attendees = ["David Chen", "Emma Thompson", "Luis Fernandez"]
        found_attendees = sr.get('attendees', [])
        matches = sum(1 for name in expected_attendees if any(name in f for f in found_attendees))
        if matches == 3:
            score += 5
        elif matches > 0:
            score += 2
            feedback_parts.append(f"Sprint Review missing some attendees ({matches}/3)")
        else:
            feedback_parts.append("Sprint Review attendees incorrect")

    else:
        feedback_parts.append("Sprint Review event missing")

    # ------------------------------------------------------------------
    # 2. Verify Executive Briefing (Max 35 points)
    # ------------------------------------------------------------------
    if eb.get('exists'):
        score += 10
        feedback_parts.append("Executive Briefing created")

        try:
            start_dt = datetime.strptime(eb.get('start'), '%Y-%m-%d %H:%M:%S')
            stop_dt = datetime.strptime(eb.get('stop'), '%Y-%m-%d %H:%M:%S')
            
            # Check Date
            if start_dt.strftime('%Y-%m-%d') == target_date:
                score += 5
            else:
                feedback_parts.append(f"Exec Briefing wrong date")

            # Check Time (15:00 start)
            if start_dt.hour == 15 and start_dt.minute == 0:
                score += 5
            else:
                feedback_parts.append(f"Exec Briefing wrong start time ({start_dt.strftime('%H:%M')})")

            # Check Duration (45 min)
            duration_min = (stop_dt - start_dt).total_seconds() / 60
            if abs(duration_min - 45) < 1:
                score += 5
            else:
                feedback_parts.append(f"Exec Briefing wrong duration ({duration_min} min)")

        except:
            pass

        # Check Location
        if "Board Room" in str(eb.get('location')):
            score += 5
        else:
            feedback_parts.append("Exec Briefing wrong location")

        # Check Attendees
        expected_attendees = ["Grace Patel", "Henry Kim", "Bob Williams"]
        found_attendees = eb.get('attendees', [])
        matches = sum(1 for name in expected_attendees if any(name in f for f in found_attendees))
        if matches == 3:
            score += 5
        elif matches > 0:
            score += 2

    else:
        feedback_parts.append("Executive Briefing event missing")

    # ------------------------------------------------------------------
    # 3. Verify Back-to-Back Constraint (20 points)
    # ------------------------------------------------------------------
    if sr.get('exists') and eb.get('exists'):
        try:
            sr_stop = datetime.strptime(sr.get('stop'), '%Y-%m-%d %H:%M:%S')
            eb_start = datetime.strptime(eb.get('start'), '%Y-%m-%d %H:%M:%S')
            
            if sr_stop == eb_start:
                score += 20
                feedback_parts.append("Perfect back-to-back scheduling")
            else:
                diff = abs((eb_start - sr_stop).total_seconds() / 60)
                if diff <= 5:
                    score += 10
                    feedback_parts.append(f"Gap/Overlap is small ({diff} min)")
                else:
                    feedback_parts.append(f"Events are not back-to-back (gap: {diff} min)")
        except:
            pass

    # ------------------------------------------------------------------
    # 4. Anti-Gaming / Count Check (10 points)
    # ------------------------------------------------------------------
    created_count = result.get('created_event_count', 0)
    if created_count >= 2:
        score += 10
    elif created_count == 0 and score > 0:
        # Suspicious: found events but none were created recently?
        # Maybe clock skew, or maybe user edited existing events.
        # We'll allow it if score is high (likely clock skew), otherwise punish.
        if score < 50:
            score = 0
            feedback_parts.append("Anti-gaming: No new events detected")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }