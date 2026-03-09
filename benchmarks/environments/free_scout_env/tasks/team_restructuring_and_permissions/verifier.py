#!/usr/bin/env python3
"""Verifier for team_restructuring_and_permissions task.

Scoring (100 points):
- VIP Support mailbox created: 15 pts
- Alex removed from Billing + added to VIP Support: 15 pts
- Maria added to Technical Support AND VIP Support: 15 pts
- Saved reply "VIP Priority Response" created: 15 pts
- VIP-tagged conversations moved to VIP Support (partial credit): 25 pts
- VIP Support conversations assigned to Alex Chen: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_team_restructuring_and_permissions(traj, env_info, task_info):
    """Verify team restructuring and permissions task completion."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_mailbox_name = metadata.get('new_mailbox_name', 'VIP Support')
    expected_saved_reply_name = metadata.get('saved_reply_name', 'VIP Priority Response')
    expected_vip_conv_count = int(metadata.get('vip_conv_count', 4))

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

    # Criterion 1: VIP Support mailbox created (15 pts)
    try:
        vip_mailbox_found = result.get('vip_mailbox_found', False)
        vip_mailbox_name = result.get('vip_mailbox_name', '').strip()
        if vip_mailbox_found and expected_mailbox_name.lower() in vip_mailbox_name.lower():
            score += 15
            feedback_parts.append(f"VIP Support mailbox '{vip_mailbox_name}' created (15/15)")
        elif vip_mailbox_found:
            score += 8
            feedback_parts.append(f"Mailbox created but unexpected name '{vip_mailbox_name}' (8/15)")
        else:
            feedback_parts.append("VIP Support mailbox NOT created (0/15)")
    except Exception as e:
        feedback_parts.append(f"VIP mailbox check error: {e}")

    # Criterion 2: Alex removed from Billing + added to VIP Support (15 pts)
    try:
        alex_billing = result.get('alex_billing_access', True)  # default True so failure is shown
        alex_vip = result.get('alex_vip_access', False)
        if not alex_billing and alex_vip:
            score += 15
            feedback_parts.append("Alex: removed from Billing Support, added to VIP Support (15/15)")
        elif not alex_billing and not alex_vip:
            score += 5
            feedback_parts.append("Alex: removed from Billing but NOT added to VIP Support (5/15)")
        elif alex_billing and alex_vip:
            score += 5
            feedback_parts.append("Alex: added to VIP but NOT removed from Billing Support (5/15)")
        else:
            feedback_parts.append("Alex: no permission changes detected (0/15)")
    except Exception as e:
        feedback_parts.append(f"Alex permissions check error: {e}")

    # Criterion 3: Maria added to Technical + VIP Support (15 pts)
    try:
        maria_tech = result.get('maria_tech_access', False)
        maria_vip = result.get('maria_vip_access', False)
        if maria_tech and maria_vip:
            score += 15
            feedback_parts.append("Maria: added to Technical Support AND VIP Support (15/15)")
        elif maria_tech and not maria_vip:
            score += 8
            feedback_parts.append("Maria: added to Technical but NOT VIP Support (8/15)")
        elif not maria_tech and maria_vip:
            score += 8
            feedback_parts.append("Maria: added to VIP but NOT Technical Support (8/15)")
        else:
            feedback_parts.append("Maria: no new mailbox access granted (0/15)")
    except Exception as e:
        feedback_parts.append(f"Maria permissions check error: {e}")

    # Criterion 4: Saved reply "VIP Priority Response" created (15 pts)
    try:
        sr_found = result.get('saved_reply_found', False)
        sr_name = result.get('saved_reply_name', '').strip()
        sr_text = result.get('saved_reply_text_preview', '').lower()
        if sr_found and expected_saved_reply_name.lower() in sr_name.lower():
            if 'vip' in sr_text or 'priority' in sr_text or 'business hour' in sr_text or 'senior' in sr_text:
                score += 15
                feedback_parts.append(f"Saved reply '{sr_name}' created with appropriate VIP content (15/15)")
            else:
                score += 10
                feedback_parts.append(f"Saved reply '{sr_name}' created but body may lack required content (10/15)")
        elif sr_found:
            score += 8
            feedback_parts.append(f"A saved reply exists ('{sr_name}') but name doesn't match '{expected_saved_reply_name}' (8/15)")
        else:
            feedback_parts.append(f"Saved reply '{expected_saved_reply_name}' NOT created (0/15)")
    except Exception as e:
        feedback_parts.append(f"Saved reply check error: {e}")

    # Criterion 5: VIP-tagged conversations moved to VIP Support mailbox (25 pts, partial)
    try:
        vip_moved = int(result.get('vip_convs_moved_count', 0))
        if vip_moved >= expected_vip_conv_count:
            score += 25
            feedback_parts.append(f"All {vip_moved} VIP-tagged conversations moved to VIP Support (25/25)")
        elif vip_moved == 3:
            score += 18
            feedback_parts.append(f"3/{expected_vip_conv_count} VIP conversations moved to VIP Support (18/25)")
        elif vip_moved == 2:
            score += 12
            feedback_parts.append(f"2/{expected_vip_conv_count} VIP conversations moved to VIP Support (12/25)")
        elif vip_moved == 1:
            score += 6
            feedback_parts.append(f"1/{expected_vip_conv_count} VIP conversation moved to VIP Support (6/25)")
        else:
            feedback_parts.append(f"No VIP-tagged conversations moved to VIP Support (0/25)")
    except Exception as e:
        feedback_parts.append(f"VIP conversation move check error: {e}")

    # Criterion 6: VIP Support conversations assigned to Alex Chen (15 pts)
    try:
        vip_total = int(result.get('vip_mailbox_total_convs', 0))
        vip_assigned_to_alex = int(result.get('vip_assigned_to_alex', 0))
        vip_moved = int(result.get('vip_convs_moved_count', 0))
        # Full credit if all conversations in VIP mailbox are assigned to Alex
        if vip_total > 0 and vip_assigned_to_alex >= vip_total:
            score += 15
            feedback_parts.append(f"All {vip_assigned_to_alex} VIP Support conversations assigned to Alex Chen (15/15)")
        elif vip_moved > 0 and vip_assigned_to_alex >= vip_moved:
            score += 15
            feedback_parts.append(f"All moved VIP conversations ({vip_assigned_to_alex}) assigned to Alex Chen (15/15)")
        elif vip_assigned_to_alex >= 3:
            score += 10
            feedback_parts.append(f"{vip_assigned_to_alex} VIP Support conversations assigned to Alex (10/15)")
        elif vip_assigned_to_alex >= 1:
            score += 5
            feedback_parts.append(f"{vip_assigned_to_alex} VIP Support conversation(s) assigned to Alex (5/15)")
        else:
            feedback_parts.append("No VIP Support conversations assigned to Alex Chen (0/15)")
    except Exception as e:
        feedback_parts.append(f"Alex assignment check error: {e}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
