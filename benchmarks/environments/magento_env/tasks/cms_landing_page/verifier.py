#!/usr/bin/env python3
"""Verifier for CMS Landing Page task in Magento.

Task: Create a CMS static block 'autumn-collection-featured' with HTML content,
then a CMS page 'autumn-collection-2024' with proper SEO metadata and a
{{block}} directive referencing the static block.

Scored on 6 criteria (100 pts). Pass threshold: 60 pts.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cms_landing_page(traj, env_info, task_info):
    """
    Verify CMS static block and landing page creation.

    Criteria:
    1. Static block 'autumn-collection-featured' exists and is active (20 pts)
    2. Static block has substantive HTML content (heading + list) (15 pts)
    3. CMS page 'autumn-collection-2024' exists and is active (20 pts)
    4. Page has correct SEO meta title containing 'Autumn Collection 2024' (15 pts)
    5. Page has meta description referencing the autumn collection (10 pts)
    6. Page content includes {{block}} directive referencing the static block (20 pts)

    Pass threshold: 60 pts
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/cms_landing_page_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    subscores = {}

    # ── Criterion 1: Static block exists and is active (20 pts) ──────────────
    block_found = result.get('block_found', False)
    block_identifier = result.get('block_identifier', '').strip().lower()
    block_is_active_str = str(result.get('block_is_active', '0')).strip()
    block_is_active = block_is_active_str in ('1', 'true', 'True')

    block_ok = block_found and block_identifier == 'autumn-collection-featured' and block_is_active
    if block_ok:
        score += 20
        feedback_parts.append("Static block 'autumn-collection-featured' exists and is active (20 pts)")
    elif block_found and block_identifier == 'autumn-collection-featured':
        score += 12
        feedback_parts.append("Static block found but is DISABLED — set status to Enabled (12 pts)")
    elif block_found:
        score += 5
        feedback_parts.append(
            f"A block was found but identifier is '{block_identifier}', expected 'autumn-collection-featured'"
        )
    else:
        feedback_parts.append(
            "Static block 'autumn-collection-featured' NOT found. "
            "Go to Content > Elements > Blocks and create it."
        )
    subscores['block_exists_active'] = block_ok

    # ── Criterion 2: Block has HTML content with heading and list (15 pts) ───
    block_content_len = int(result.get('block_content_length', 0))
    block_has_heading = result.get('block_has_heading', False)
    block_has_list = result.get('block_has_list', False)
    block_has_html = result.get('block_has_html', False)

    if block_has_heading and block_has_list and block_content_len > 50:
        score += 15
        feedback_parts.append("Block has HTML content with heading and list (15 pts)")
    elif block_has_html and block_content_len > 30:
        score += 8
        feedback_parts.append(
            f"Block has some HTML but missing required elements: "
            f"heading={'yes' if block_has_heading else 'NO'}, "
            f"list={'yes' if block_has_list else 'NO'} (8 pts partial)"
        )
    elif block_content_len > 10:
        score += 3
        feedback_parts.append("Block has content but no HTML markup (3 pts partial)")
    else:
        feedback_parts.append(
            "Block content is empty or too short. Add h2 heading, paragraph, and a list of product categories."
        )
    subscores['block_has_html_content'] = (block_has_heading and block_has_list)

    # ── GATE: CMS page must exist ─────────────────────────────────────────────
    page_found = result.get('page_found', False)
    page_identifier = result.get('page_identifier', '').strip().lower()

    if not page_found or page_identifier != 'autumn-collection-2024':
        feedback_parts.append(
            "GATE FAIL: CMS page 'autumn-collection-2024' NOT found. "
            "Go to Content > Pages and create it."
        )
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                **subscores,
                "page_exists_active": False,
                "page_meta_title": False,
                "page_meta_desc": False,
                "page_block_directive": False
            }
        }

    # ── Criterion 3: CMS page exists and is active (20 pts) ──────────────────
    page_is_active_str = str(result.get('page_is_active', '0')).strip()
    page_is_active = page_is_active_str in ('1', 'true', 'True')

    page_ok = page_found and page_is_active
    if page_ok:
        score += 20
        feedback_parts.append("CMS page 'autumn-collection-2024' exists and is active (20 pts)")
    else:
        score += 10
        feedback_parts.append("CMS page exists but is DISABLED — set status to Enabled (10 pts)")
    subscores['page_exists_active'] = page_ok

    # ── Criterion 4: Page meta title correct (15 pts) ─────────────────────────
    meta_title_ok = result.get('page_meta_title_ok', False)
    page_meta_title = result.get('page_meta_title', '')

    if meta_title_ok:
        score += 15
        feedback_parts.append(f"Meta title correct: '{page_meta_title}' (15 pts)")
    elif page_meta_title:
        score += 5
        feedback_parts.append(
            f"Meta title is set ('{page_meta_title}') but must contain 'Autumn Collection 2024' (5 pts partial)"
        )
    else:
        feedback_parts.append(
            "Meta title is empty. Set to 'Autumn Collection 2024 | NestWell Home'."
        )
    subscores['page_meta_title'] = meta_title_ok

    # ── Criterion 5: Page has meta description (10 pts) ──────────────────────
    meta_desc_ok = result.get('page_meta_desc_ok', False)
    page_meta_desc = result.get('page_meta_description', '')

    if meta_desc_ok:
        score += 10
        feedback_parts.append("Meta description references the autumn collection (10 pts)")
    elif page_meta_desc:
        score += 4
        feedback_parts.append(
            f"Meta description is set but should mention 'Autumn 2024' or 'autumn collection' (4 pts partial)"
        )
    else:
        feedback_parts.append("Meta description is empty. Add a description mentioning the autumn collection.")
    subscores['page_meta_desc'] = meta_desc_ok

    # ── Criterion 6: Page content references the static block (20 pts) ────────
    has_directive = result.get('page_has_block_directive', False)
    refs_correct_block = result.get('page_references_correct_block', False)

    if has_directive and refs_correct_block:
        score += 20
        feedback_parts.append(
            "Page content contains {{block id=\"autumn-collection-featured\"}} directive (20 pts)"
        )
    elif has_directive:
        score += 10
        feedback_parts.append(
            "Page has a {{block}} directive but does not reference 'autumn-collection-featured' "
            "(check the block id attribute) (10 pts partial)"
        )
    elif refs_correct_block:
        score += 10
        feedback_parts.append(
            "Page references 'autumn-collection-featured' in content but not with {{block}} syntax (10 pts partial)"
        )
    else:
        feedback_parts.append(
            "Page content does NOT contain a {{block}} directive. "
            "Add {{block id=\"autumn-collection-featured\"}} to the page content."
        )
    subscores['page_block_directive'] = (has_directive and refs_correct_block)

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
