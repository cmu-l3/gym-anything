#!/usr/bin/env python3
"""
Verifier for service_desk_ticket_resolution task.

The agent must:
1. Locate (or create) and close 3 specific tickets.
2. Add specific resolution comments to those 3 tickets.
3. Leave 2 specific tickets open.

Checks:
- Sarah Johnson VPN ticket closed (15 pts) + comment added (5 pts)
- Robert Taylor monitor ticket closed (15 pts) + comment added (5 pts)
- Emily Williams AC ticket closed (15 pts) + comment added (5 pts)
- Negative constraint: Michael Chen payroll ticket NOT closed (20 pts)
- Negative constraint: David Miller desk ticket NOT closed (20 pts)

Primary verification is programmatic via database queries.
Secondary VLM check can be used if DB queries fail due to schema differences,
but DB is heavily prioritized.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_ticket(ticket_data, expected_comment_keywords, is_negative_constraint=False):
    """
    Evaluates a single ticket's status and comments.
    Returns (status_pts, comment_pts, status_feedback, comment_feedback)
    """
    if not ticket_data:
        if is_negative_constraint:
            return 20, 0, "Ticket not found (counts as not closed)", ""
        return 0, 0, "Ticket not found in system", ""
        
    status = ticket_data.get('status', '').lower()
    comments = ticket_data.get('comments', '').lower()
    
    if is_negative_constraint:
        # For negative constraints, we want the ticket to NOT be closed.
        if 'closed' in status:
            return 0, 0, "FAIL: Ticket was incorrectly closed", ""
        else:
            return 20, 0, "PASS: Ticket remained open/untouched", ""
            
    # For positive constraints
    status_pts = 15 if 'closed' in status else 0
    status_fb = "Status is Closed" if status_pts else f"Status is not Closed (found: {status})"
    
    comment_pts = 0
    comment_fb = "Resolution comment missing or incorrect"
    
    # Check if at least one key phrase from the expected comment is present
    for kw in expected_comment_keywords:
        if kw.lower() in comments:
            comment_pts = 5
            comment_fb = f"Resolution comment found (matched '{kw}')"
            break
            
    return status_pts, comment_pts, status_fb, comment_fb

def verify_service_desk_ticket_resolution(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        else:
            logger.warning("Result JSON is empty or missing.")
    except Exception as e:
        logger.error(f"Error reading task result: {e}")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    tickets = result.get('tickets', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Sarah Johnson VPN ticket
    s_pts, c_pts, s_fb, c_fb = check_ticket(
        tickets.get('vpn'), 
        ['reset user ad password', 'synced rsa token', 'external ip']
    )
    score += (s_pts + c_pts)
    feedback_parts.append(f"VPN Ticket: {s_fb}, {c_fb} ({s_pts+c_pts}/20)")
    
    # 2. Robert Taylor monitor ticket
    s_pts, c_pts, s_fb, c_fb = check_ticket(
        tickets.get('monitor'), 
        ['dell u2720q', 'displayport', 'extended desktop']
    )
    score += (s_pts + c_pts)
    feedback_parts.append(f"Monitor Ticket: {s_fb}, {c_fb} ({s_pts+c_pts}/20)")
    
    # 3. Emily Williams AC ticket
    s_pts, c_pts, s_fb, c_fb = check_ticket(
        tickets.get('ac'), 
        ['damper', 'actuator', '72f baseline', 'thermostat']
    )
    score += (s_pts + c_pts)
    feedback_parts.append(f"AC Ticket: {s_fb}, {c_fb} ({s_pts+c_pts}/20)")
    
    # 4. Negative Constraint: Michael Chen payroll
    nc1_pts, _, nc1_fb, _ = check_ticket(tickets.get('payroll'), [], is_negative_constraint=True)
    score += nc1_pts
    feedback_parts.append(f"Payroll Ticket: {nc1_fb} ({nc1_pts}/20)")
    
    # 5. Negative Constraint: David Miller desk
    nc2_pts, _, nc2_fb, _ = check_ticket(tickets.get('desk'), [], is_negative_constraint=True)
    score += nc2_pts
    feedback_parts.append(f"Desk Ticket: {nc2_fb} ({nc2_pts}/20)")
    
    # VLM Fallback if DB queries returned absolutely nothing
    # (e.g. if schema was completely different and setup failed to insert)
    db_failed = all(not t for t in tickets.values())
    if db_failed and 'query_vlm' in env_info:
        logger.info("DB verification failed to find tickets, attempting VLM fallback")
        query_vlm = env_info['query_vlm']
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots from a user interacting with the Sentrifugo Service Desk module.
        Task goal: Close 3 specific tickets (VPN, monitor, AC) and leave 2 open (payroll, desk).
        
        Based on the trajectory, did the user:
        1. Navigate to the Service Desk?
        2. Successfully close the tickets for VPN access, secondary monitor, and AC?
        3. Enter resolution comments for those tickets?
        4. Leave the payroll and standing desk tickets open?
        
        Respond with a JSON object:
        {
            "service_desk_accessed": true/false,
            "tickets_closed_count": <number 0-3>,
            "comments_entered": true/false,
            "pending_tickets_untouched": true/false
        }
        """
        
        vlm_res = query_vlm(images=frames + [final_frame], prompt=prompt)
        if vlm_res.get('success'):
            try:
                parsed = json.loads(vlm_res['response'].strip().strip('