#!/usr/bin/env python3
"""Verifier for support_operations_cleanup task.

Scoring (100 points):
- 2 misrouted Tech Support convs moved to Sales Inquiries (partial credit): 15 pts
- 1 misrouted Sales Inquiries conv moved to Customer Success: 10 pts
- Raj Patel's Sales Inquiries access removed: 10 pts
- Ben Harris's Customer Success access added: 10 pts
- Unassigned Tech Support convs assigned to Raj (partial credit): 15 pts
- Unassigned Customer Success convs assigned to Nina (partial credit): 10 pts
- Saved reply "Sales Inquiry Acknowledgment" created: 15 pts
- needs-follow-up tag on Sales convs without agent reply (partial credit): 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_support_operations_cleanup(traj, env_info, task_info):
    """Verify support operations cleanup task completion."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_saved_reply_name = metadata.get('saved_reply_name', 'Sales Inquiry Acknowledgment')
    expected_nfu_tag = metadata.get('needs_follow_up_tag', 'needs-follow-up')
    expected_tech_to_sales = int(metadata.get('misrouted_tech_to_sales_count', 2))

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

    # Criterion 1: 2 misrouted Tech conversations moved to Sales Inquiries (15 pts, partial)
    try:
        tech3_moved = result.get('tech3_in_sales', False)
        tech4_moved = result.get('tech4_in_sales', False)
        moves_done = int(tech3_moved) + int(tech4_moved)
        if moves_done == expected_tech_to_sales:
            score += 15
            feedback_parts.append("Both Tech→Sales misrouted conversations moved (15/15)")
        elif moves_done == 1:
            score += 8
            feedback_parts.append("1/2 Tech→Sales misrouted conversations moved (8/15)")
        else:
            feedback_parts.append("No Tech→Sales misrouted conversations moved (0/15)")
    except Exception as e:
        feedback_parts.append(f"Tech→Sales move check error: {e}")

    # Criterion 2: 1 misrouted Sales conversation moved to Customer Success (10 pts)
    try:
        sales3_moved = result.get('sales3_in_cs', False)
        if sales3_moved:
            score += 10
            feedback_parts.append("Invoice discrepancy conversation moved to Customer Success (10/10)")
        else:
            feedback_parts.append("Invoice discrepancy conversation NOT moved to Customer Success (0/10)")
    except Exception as e:
        feedback_parts.append(f"Sales→CS move check error: {e}")

    # Criterion 3: Raj's Sales Inquiries access removed (10 pts)
    try:
        raj_sales = result.get('raj_sales_access', True)
        raj_tech = result.get('raj_tech_access', False)
        if not raj_sales and raj_tech:
            score += 10
            feedback_parts.append("Raj: Sales access removed, Technical access retained (10/10)")
        elif not raj_sales and not raj_tech:
            score += 5
            feedback_parts.append("Raj: Sales access removed but Technical access also lost (5/10)")
        elif raj_sales:
            feedback_parts.append("Raj: Sales Inquiries access NOT removed (0/10)")
        else:
            feedback_parts.append("Raj: permission state unclear (0/10)")
    except Exception as e:
        feedback_parts.append(f"Raj permissions check error: {e}")

    # Criterion 4: Ben Harris's Customer Success access added (10 pts)
    try:
        ben_cs = result.get('ben_cs_access', False)
        ben_sales = result.get('ben_sales_access', False)
        if ben_cs and ben_sales:
            score += 10
            feedback_parts.append("Ben: Customer Success access added, Sales access retained (10/10)")
        elif ben_cs and not ben_sales:
            score += 7
            feedback_parts.append("Ben: Customer Success access added but Sales access lost (7/10)")
        elif not ben_cs:
            feedback_parts.append("Ben: Customer Success access NOT added (0/10)")
    except Exception as e:
        feedback_parts.append(f"Ben permissions check error: {e}")

    # Criterion 5: Unassigned Tech Support convs assigned to Raj (15 pts, partial)
    try:
        tech1_raj = result.get('tech1_assigned_to_raj', False)
        tech2_raj = result.get('tech2_assigned_to_raj', False)
        raj_assignments = int(tech1_raj) + int(tech2_raj)
        if raj_assignments == 2:
            score += 15
            feedback_parts.append("Both unassigned Tech Support conversations assigned to Raj (15/15)")
        elif raj_assignments == 1:
            score += 8
            feedback_parts.append("1/2 unassigned Tech Support conversations assigned to Raj (8/15)")
        else:
            feedback_parts.append("No unassigned Tech Support conversations assigned to Raj (0/15)")
    except Exception as e:
        feedback_parts.append(f"Raj assignment check error: {e}")

    # Criterion 6: Unassigned Customer Success convs assigned to Nina (10 pts, partial)
    try:
        cs1_nina = result.get('cs1_assigned_to_nina', False)
        cs2_nina = result.get('cs2_assigned_to_nina', False)
        nina_assignments = int(cs1_nina) + int(cs2_nina)
        if nina_assignments == 2:
            score += 10
            feedback_parts.append("Both unassigned Customer Success conversations assigned to Nina (10/10)")
        elif nina_assignments == 1:
            score += 5
            feedback_parts.append("1/2 unassigned Customer Success conversations assigned to Nina (5/10)")
        else:
            feedback_parts.append("No unassigned Customer Success conversations assigned to Nina (0/10)")
    except Exception as e:
        feedback_parts.append(f"Nina assignment check error: {e}")

    # Criterion 7: Saved reply "Sales Inquiry Acknowledgment" created (15 pts)
    try:
        sr_found = result.get('saved_reply_found', False)
        sr_name = result.get('saved_reply_name', '').strip()
        sr_text = result.get('saved_reply_text_preview', '').lower()
        if sr_found and expected_saved_reply_name.lower() in sr_name.lower():
            if 'sales' in sr_text or 'account executive' in sr_text or 'business day' in sr_text or 'inquiry' in sr_text:
                score += 15
                feedback_parts.append(f"Saved reply '{sr_name}' created with appropriate content (15/15)")
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

    # Criterion 8: needs-follow-up tag applied to Sales convs without agent reply (15 pts, partial)
    # Expected: 4 conversations in Sales mailbox tagged (2 original unresponded + 2 moved from Tech)
    # Partial credit: 2+ tagged = 8pts, 3 tagged = 12pts, 4+ tagged = 15pts
    try:
        nfu_found = result.get('nfu_tag_found', False)
        tagged_sales = int(result.get('tagged_sales_count', 0))
        sales_unresponded = int(result.get('sales_unresponded_count', 0))
        if nfu_found and tagged_sales >= 4:
            score += 15
            feedback_parts.append(f"All {tagged_sales} unresponded Sales conversations tagged '{expected_nfu_tag}' (15/15)")
        elif nfu_found and tagged_sales == 3:
            score += 12
            feedback_parts.append(f"3 unresponded Sales conversations tagged '{expected_nfu_tag}' (12/15)")
        elif nfu_found and tagged_sales >= 2:
            score += 8
            feedback_parts.append(f"{tagged_sales} unresponded Sales conversations tagged '{expected_nfu_tag}' (8/15)")
        elif nfu_found and tagged_sales == 1:
            score += 4
            feedback_parts.append(f"1 Sales conversation tagged '{expected_nfu_tag}' (4/15)")
        elif not nfu_found:
            feedback_parts.append(f"Tag '{expected_nfu_tag}' was not created (0/15)")
        else:
            feedback_parts.append(f"Tag '{expected_nfu_tag}' exists but no Sales conversations tagged (0/15)")
    except Exception as e:
        feedback_parts.append(f"needs-follow-up tag check error: {e}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
