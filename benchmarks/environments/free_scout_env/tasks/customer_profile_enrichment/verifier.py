#!/usr/bin/env python3
"""Verifier for customer_profile_enrichment task.

Scoring (100 points):
- Marisa Obrien company = "Pinnacle Systems": 12 pts
- Marisa Obrien phone updated: 8 pts
- Marisa Obrien job title = "Senior Systems Engineer": 10 pts
- Nicolas Wilson company = "Horizon Analytics": 12 pts
- Nicolas Wilson phone updated: 8 pts
- David Okafor created with correct email + company: 15 pts
- Marisa's 3 conversations tagged "vip-client" (partial credit): 20 pts
- New conversation for David Okafor in Technical Support: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_customer_profile_enrichment(traj, env_info, task_info):
    """Verify customer profile enrichment task completion."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_c1_company = metadata.get('customer1_company', 'Pinnacle Systems')
    expected_c1_job = metadata.get('customer1_job_title', 'Senior Systems Engineer')
    expected_c2_company = metadata.get('customer2_company', 'Horizon Analytics')
    expected_new_company = metadata.get('new_customer_company', 'TechFirm Solutions')
    expected_vip_tag = metadata.get('vip_tag', 'vip-client')
    expected_conv_count = int(metadata.get('customer1_conv_count', 3))
    expected_conv_subject_kw = 'enterprise account onboarding'

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

    # Criterion 1: Marisa Obrien company updated (12 pts)
    try:
        marisa_company = result.get('marisa_company', '').strip()
        if expected_c1_company.lower() in marisa_company.lower():
            score += 12
            feedback_parts.append(f"Marisa company set to '{marisa_company}' (12/12)")
        elif marisa_company:
            score += 4
            feedback_parts.append(f"Marisa company set to '{marisa_company}' (partial, expected '{expected_c1_company}') (4/12)")
        else:
            feedback_parts.append(f"Marisa company not updated (0/12)")
    except Exception as e:
        feedback_parts.append(f"Marisa company check error: {e}")

    # Criterion 2: Marisa Obrien phone updated (8 pts)
    try:
        marisa_phone = result.get('marisa_phone', '').strip()
        if marisa_phone and len(marisa_phone) >= 7:
            score += 8
            feedback_parts.append(f"Marisa phone set to '{marisa_phone}' (8/8)")
        else:
            feedback_parts.append(f"Marisa phone not updated (0/8)")
    except Exception as e:
        feedback_parts.append(f"Marisa phone check error: {e}")

    # Criterion 3: Marisa Obrien job title updated (10 pts)
    try:
        marisa_job = result.get('marisa_job_title', '').strip()
        if expected_c1_job.lower() in marisa_job.lower() or 'engineer' in marisa_job.lower():
            score += 10
            feedback_parts.append(f"Marisa job title set to '{marisa_job}' (10/10)")
        elif marisa_job:
            score += 4
            feedback_parts.append(f"Marisa job title set to '{marisa_job}' (partial, expected '{expected_c1_job}') (4/10)")
        else:
            feedback_parts.append(f"Marisa job title not updated (0/10)")
    except Exception as e:
        feedback_parts.append(f"Marisa job title check error: {e}")

    # Criterion 4: Nicolas Wilson company updated (12 pts)
    try:
        nicolas_company = result.get('nicolas_company', '').strip()
        if expected_c2_company.lower() in nicolas_company.lower():
            score += 12
            feedback_parts.append(f"Nicolas company set to '{nicolas_company}' (12/12)")
        elif nicolas_company:
            score += 4
            feedback_parts.append(f"Nicolas company set to '{nicolas_company}' (partial, expected '{expected_c2_company}') (4/12)")
        else:
            feedback_parts.append(f"Nicolas company not updated (0/12)")
    except Exception as e:
        feedback_parts.append(f"Nicolas company check error: {e}")

    # Criterion 5: Nicolas Wilson phone updated (8 pts)
    try:
        nicolas_phone = result.get('nicolas_phone', '').strip()
        if nicolas_phone and len(nicolas_phone) >= 7:
            score += 8
            feedback_parts.append(f"Nicolas phone set to '{nicolas_phone}' (8/8)")
        else:
            feedback_parts.append(f"Nicolas phone not updated (0/8)")
    except Exception as e:
        feedback_parts.append(f"Nicolas phone check error: {e}")

    # Criterion 6: David Okafor created with correct company (15 pts)
    try:
        david_found = result.get('david_found', False)
        david_company = result.get('david_company', '').strip()
        if david_found and expected_new_company.lower() in david_company.lower():
            score += 15
            feedback_parts.append(f"David Okafor created with company '{david_company}' (15/15)")
        elif david_found:
            score += 8
            feedback_parts.append(f"David Okafor created but company '{david_company}' doesn't match (8/15)")
        else:
            feedback_parts.append(f"David Okafor NOT created (0/15)")
    except Exception as e:
        feedback_parts.append(f"David Okafor check error: {e}")

    # Criterion 7: Marisa's conversations tagged "vip-client" (20 pts, partial)
    try:
        marisa_tagged = int(result.get('marisa_tagged_count', 0))
        if marisa_tagged >= expected_conv_count:
            score += 20
            feedback_parts.append(f"All {marisa_tagged} of Marisa's conversations tagged '{expected_vip_tag}' (20/20)")
        elif marisa_tagged == 2:
            score += 14
            feedback_parts.append(f"2/{expected_conv_count} of Marisa's conversations tagged '{expected_vip_tag}' (14/20)")
        elif marisa_tagged == 1:
            score += 7
            feedback_parts.append(f"1/{expected_conv_count} of Marisa's conversations tagged '{expected_vip_tag}' (7/20)")
        else:
            feedback_parts.append(f"None of Marisa's conversations tagged '{expected_vip_tag}' (0/20)")
    except Exception as e:
        feedback_parts.append(f"VIP tag check error: {e}")

    # Criterion 8: New conversation for David Okafor in Technical Support (15 pts)
    try:
        david_conv_found = result.get('david_conv_found', False)
        david_conv_correct_mailbox = result.get('david_conv_mailbox_correct', False)
        david_conv_subject = result.get('david_conv_subject', '').lower()
        if david_conv_found and david_conv_correct_mailbox and expected_conv_subject_kw in david_conv_subject:
            score += 15
            feedback_parts.append(f"David Okafor conversation created in Technical Support (15/15)")
        elif david_conv_found and david_conv_correct_mailbox:
            score += 10
            feedback_parts.append(f"Conversation created in Technical Support but subject may differ (10/15)")
        elif david_conv_found:
            score += 5
            feedback_parts.append(f"Conversation found but in wrong mailbox (5/15)")
        else:
            feedback_parts.append(f"No new conversation created for David Okafor (0/15)")
    except Exception as e:
        feedback_parts.append(f"David conversation check error: {e}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
