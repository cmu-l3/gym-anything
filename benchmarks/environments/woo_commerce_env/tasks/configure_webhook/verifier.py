#!/usr/bin/env python3
"""
Verifier for Configure Webhook task in WooCommerce.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (100 points max, 70 threshold) — from export script JSON:
  1. Webhook exists (15 pts)
  2. Created during task time window (Anti-gaming) (Required for points)
  3. Name matches exactly (15 pts)
  4. Status is 'active' (15 pts)
  5. Topic is 'order.created' (20 pts)
  6. Delivery URL matches exactly (20 pts)
  7. Secret matches exactly (15 pts)

VLM checks (Supplementary/Debug):
  - confirm navigation to "Advanced > Webhooks"
  - confirm form filling

Pass threshold: 70 points AND webhook found AND created during task.
"""

import json
import tempfile
import os
import logging
from urllib.parse import urlparse

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ================================================================
# VLM HELPERS
# ================================================================

def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring a webhook in WooCommerce.

The images are sampled chronologically.

For successful webhook configuration, the agent should:
1. Navigate to WooCommerce > Settings
2. Click on the "Advanced" tab
3. Click on "Webhooks"
4. Click "Add webhook"
5. Fill in details (Name, Topic, Delivery URL, Secret)
6. Save the webhook

Assess:
1. SETTINGS_ACCESSED: Did the agent reach WooCommerce Settings?
2. WEBHOOKS_TAB_VISIBLE: Was the Webhooks management screen visible?
3. FORM_INTERACTION: Did the agent fill out a webhook form?

Respond in JSON format:
{
    "settings_accessed": true/false,
    "webhooks_tab_visible": true/false,
    "form_interaction": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

def verify_configure_webhook(traj, env_info, task_info):
    """
    Verify that the webhook was configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Fulfillment Dispatch - New Orders")
    expected_status = metadata.get('expected_status', "active")
    expected_topic = metadata.get('expected_topic', "order.created")
    expected_url = metadata.get('expected_delivery_url', "https://hooks.fulfillment-partner.example.com/wc/orders")
    expected_secret = metadata.get('expected_secret', "fh8K2mNpQx7vR4wT")

    feedback_parts = []
    score = 0
    max_score = 100

    # Load result
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_webhook_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {str(e)}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}

    webhook = result.get('webhook', {})
    webhook_found = result.get('webhook_found', False)
    task_start = result.get('task_start', 0)
    created_ts = webhook.get('created_timestamp', 0)

    # Criteria 1: Webhook Exists (15 pts)
    if not webhook_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No matching webhook found.",
            "details": result
        }
    score += 15
    feedback_parts.append("Webhook created")

    # Criteria 2: Anti-Gaming (Timestamp check)
    # Allow a small buffer (e.g., 5 seconds) for clock skew
    if created_ts < (task_start - 5):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Webhook appears to have been created BEFORE task started. Anti-gaming check failed."
        }
    
    # Criteria 3: Name Matches (15 pts)
    # Check case-insensitive
    wh_name = webhook.get('name', '')
    if wh_name.strip().lower() == expected_name.strip().lower():
        score += 15
        feedback_parts.append("Name matches")
    else:
        feedback_parts.append(f"Name mismatch (found: '{wh_name}')")

    # Criteria 4: Status Matches (15 pts)
    wh_status = webhook.get('status', '')
    if wh_status == expected_status:
        score += 15
        feedback_parts.append("Status active")
    else:
        feedback_parts.append(f"Status mismatch (found: '{wh_status}')")

    # Criteria 5: Topic Matches (20 pts)
    wh_topic = webhook.get('topic', '')
    if wh_topic == expected_topic:
        score += 20
        feedback_parts.append("Topic correct")
    else:
        feedback_parts.append(f"Topic mismatch (found: '{wh_topic}')")

    # Criteria 6: URL Matches (20 pts)
    # Normalize URLs for comparison (remove trailing slashes)
    wh_url = webhook.get('delivery_url', '').rstrip('/')
    exp_url = expected_url.rstrip('/')
    if wh_url == exp_url:
        score += 20
        feedback_parts.append("URL correct")
    else:
        feedback_parts.append(f"URL mismatch (found: '{wh_url}')")

    # Criteria 7: Secret Matches (15 pts)
    wh_secret = webhook.get('secret', '')
    if wh_secret == expected_secret:
        score += 15
        feedback_parts.append("Secret correct")
    else:
        feedback_parts.append(f"Secret mismatch (found: '{wh_secret}')")

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "webhook_found": webhook_found,
            "created_during_task": True,
            "fields_matched": score
        }
    }