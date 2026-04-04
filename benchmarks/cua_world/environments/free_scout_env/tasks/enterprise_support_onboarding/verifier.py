#!/usr/bin/env python3
"""Verifier for enterprise_support_onboarding task.

Scoring (100 points):
- Enterprise Support mailbox created: 15 pts
- James Kowalski created (role=User): 10 pts
- Priya Sharma created (role=User): 10 pts
- James has access to Technical Support AND Enterprise Support: 15 pts
- Saved reply "Enterprise Acknowledgment" created: 15 pts
- All 5 Technical Support conversations tagged "technical": 20 pts
- All 3 Billing conversations assigned to Sarah Mitchell: 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_enterprise_support_onboarding(traj, env_info, task_info):
    """Verify enterprise support onboarding task completion."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_saved_reply_name = metadata.get('saved_reply_name', 'Enterprise Acknowledgment')
    expected_tech_conv_count = int(metadata.get('technical_conv_count', 5))
    expected_billing_conv_count = int(metadata.get('billing_conv_count', 3))

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

    # Criterion 1: Enterprise Support mailbox created (15 pts)
    try:
        enterprise_found = result.get('enterprise_mailbox_found', False)
        enterprise_name = result.get('enterprise_mailbox_name', '').strip()
        if enterprise_found and 'enterprise' in enterprise_name.lower():
            score += 15
            feedback_parts.append(f"Enterprise Support mailbox created: '{enterprise_name}' (15/15)")
        elif enterprise_found:
            score += 8
            feedback_parts.append(f"Mailbox created but name unexpected: '{enterprise_name}' (8/15)")
        else:
            feedback_parts.append("Enterprise Support mailbox NOT created (0/15)")
    except Exception as e:
        feedback_parts.append(f"Enterprise mailbox check error: {e}")

    # Criterion 2: James Kowalski created with User role (10 pts)
    try:
        james_found = result.get('james_found', False)
        james_role = int(result.get('james_role', 0))
        if james_found and james_role == 2:
            score += 10
            feedback_parts.append("James Kowalski created with User role (10/10)")
        elif james_found:
            score += 5
            feedback_parts.append(f"James Kowalski created but wrong role={james_role} (5/10)")
        else:
            feedback_parts.append("James Kowalski NOT created (0/10)")
    except Exception as e:
        feedback_parts.append(f"James Kowalski check error: {e}")

    # Criterion 3: Priya Sharma created with User role (10 pts)
    try:
        priya_found = result.get('priya_found', False)
        priya_role = int(result.get('priya_role', 0))
        if priya_found and priya_role == 2:
            score += 10
            feedback_parts.append("Priya Sharma created with User role (10/10)")
        elif priya_found:
            score += 5
            feedback_parts.append(f"Priya Sharma created but wrong role={priya_role} (5/10)")
        else:
            feedback_parts.append("Priya Sharma NOT created (0/10)")
    except Exception as e:
        feedback_parts.append(f"Priya Sharma check error: {e}")

    # Criterion 4: James has access to BOTH Technical Support and Enterprise Support (15 pts)
    try:
        james_tech = result.get('james_tech_access', False)
        james_ent = result.get('james_enterprise_access', False)
        if james_tech and james_ent:
            score += 15
            feedback_parts.append("James has access to both Technical Support and Enterprise Support (15/15)")
        elif james_ent:
            score += 7
            feedback_parts.append("James has Enterprise access but NOT Technical Support access (7/15)")
        elif james_tech:
            score += 5
            feedback_parts.append("James has Technical Support access but NOT Enterprise access (5/15)")
        else:
            feedback_parts.append("James has no mailbox access configured (0/15)")
    except Exception as e:
        feedback_parts.append(f"James access check error: {e}")

    # Criterion 5: Saved reply "Enterprise Acknowledgment" created (15 pts)
    try:
        sr_found = result.get('saved_reply_found', False)
        sr_name = result.get('saved_reply_name', '').strip()
        sr_text = result.get('saved_reply_text_preview', '').lower()
        if sr_found and expected_saved_reply_name.lower() in sr_name.lower():
            if 'enterprise' in sr_text or 'business hour' in sr_text or 'dedicated' in sr_text:
                score += 15
                feedback_parts.append(f"Saved reply '{sr_name}' created with appropriate content (15/15)")
            else:
                score += 10
                feedback_parts.append(f"Saved reply '{sr_name}' created but body may be missing required content (10/15)")
        elif sr_found:
            score += 8
            feedback_parts.append(f"A saved reply exists ('{sr_name}') but name doesn't match 'Enterprise Acknowledgment' (8/15)")
        else:
            feedback_parts.append("Saved reply 'Enterprise Acknowledgment' NOT created (0/15)")
    except Exception as e:
        feedback_parts.append(f"Saved reply check error: {e}")

    # Criterion 6: Technical Support conversations tagged "technical" (20 pts — partial credit)
    try:
        tech_tagged = int(result.get('tech_tagged_count', 0))
        if tech_tagged >= expected_tech_conv_count:
            score += 20
            feedback_parts.append(f"All {tech_tagged} Technical Support conversations tagged 'technical' (20/20)")
        elif tech_tagged >= 3:
            pts = 12
            score += pts
            feedback_parts.append(f"{tech_tagged}/{expected_tech_conv_count} Technical conversations tagged 'technical' ({pts}/20)")
        elif tech_tagged >= 1:
            pts = 6
            score += pts
            feedback_parts.append(f"{tech_tagged}/{expected_tech_conv_count} Technical conversations tagged 'technical' ({pts}/20)")
        else:
            feedback_parts.append(f"No Technical conversations tagged 'technical' (0/20)")
    except Exception as e:
        feedback_parts.append(f"Tag check error: {e}")

    # Criterion 7: Billing conversations assigned to Sarah Mitchell (15 pts — partial credit)
    try:
        billing_assigned = int(result.get('billing_assigned_to_sarah', 0))
        if billing_assigned >= expected_billing_conv_count:
            score += 15
            feedback_parts.append(f"All {billing_assigned} Billing conversations assigned to Sarah Mitchell (15/15)")
        elif billing_assigned >= 2:
            pts = 10
            score += pts
            feedback_parts.append(f"{billing_assigned}/{expected_billing_conv_count} Billing conversations assigned to Sarah ({pts}/15)")
        elif billing_assigned >= 1:
            pts = 5
            score += pts
            feedback_parts.append(f"{billing_assigned}/{expected_billing_conv_count} Billing conversations assigned to Sarah ({pts}/15)")
        else:
            feedback_parts.append(f"No Billing conversations assigned to Sarah Mitchell (0/15)")
    except Exception as e:
        feedback_parts.append(f"Assignment check error: {e}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
