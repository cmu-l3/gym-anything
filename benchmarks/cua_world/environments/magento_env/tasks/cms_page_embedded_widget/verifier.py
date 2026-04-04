#!/usr/bin/env python3
"""Verifier for CMS Page Embedded Widget task in Magento.

Task: Create a CMS page 'New Arrivals Showcase' with specific text and an
EMBEDDED widget (not layout update) for New Products List (count 6).

Scored on 6 criteria (100 pts). Pass threshold: 60 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cms_page_embedded_widget(traj, env_info, task_info):
    """
    Verify CMS page creation and inline widget configuration.
    
    Criteria:
    1. Page 'new-arrivals-showcase' exists and is enabled (20 pts)
    2. Page Title matches 'New Arrivals Showcase' (10 pts)
    3. Content includes required heading text (10 pts)
    4. Content includes correct Widget Directive (NewWidget) (30 pts)
    5. Widget configured with products_count="6" (15 pts)
    6. Content includes required paragraph text (15 pts)
    
    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/cms_widget_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # ── Criterion 1: Page exists and is enabled (20 pts) ──────────────────────
    page_found = result.get('page_found', False)
    is_active_val = str(result.get('is_active', '0')).strip()
    is_active = is_active_val in ('1', 'true', 'True')
    
    if page_found and is_active:
        score += 20
        feedback_parts.append("Page exists and is enabled (20 pts)")
    elif page_found:
        score += 10
        feedback_parts.append("Page exists but is disabled (10 pts)")
    else:
        feedback_parts.append("Page 'new-arrivals-showcase' NOT found")
        # Fail early if page doesn't exist
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": result
        }

    # ── Criterion 2: Title Correct (10 pts) ──────────────────────────────────
    expected_title = "New Arrivals Showcase"
    actual_title = result.get('page_title', '').strip()
    if actual_title.lower() == expected_title.lower():
        score += 10
        feedback_parts.append("Title correct (10 pts)")
    else:
        feedback_parts.append(f"Title mismatch: expected '{expected_title}', got '{actual_title}'")

    # ── Criterion 3: Heading Text (10 pts) ───────────────────────────────────
    if result.get('has_heading', False):
        score += 10
        feedback_parts.append("Heading text found (10 pts)")
    else:
        feedback_parts.append("Required heading text 'Fresh Finds...' missing")

    # ── Criterion 4: Widget Directive (30 pts) ───────────────────────────────
    # This checks for {{widget type="Magento\Catalog\Block\Product\Widget\NewWidget" ...}}
    if result.get('has_widget_directive', False):
        score += 30
        feedback_parts.append("Widget directive correctly embedded (30 pts)")
    else:
        feedback_parts.append("Widget directive missing or incorrect type. Did you use 'Insert Widget'?")

    # ── Criterion 5: Product Count (15 pts) ──────────────────────────────────
    if result.get('has_correct_product_count', False):
        score += 15
        feedback_parts.append("Widget product count is 6 (15 pts)")
    else:
        feedback_parts.append("Widget product count incorrect (expected 6)")

    # ── Criterion 6: Paragraph Text (15 pts) ─────────────────────────────────
    if result.get('has_paragraph', False):
        score += 15
        feedback_parts.append("Paragraph text found (15 pts)")
    else:
        feedback_parts.append("Required paragraph text missing")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }