#!/usr/bin/env python3
"""Verifier for Soft Launch Configuration task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_storefront_soft_launch_config(traj, env_info, task_info):
    """
    Verify that the store was configured for soft launch.

    Criteria:
    1. CMS Page 'coming-soon' exists (20 pts)
    2. Page is Enabled (10 pts)
    3. Page Content contains "<h1>We are launching soon!</h1>" (20 pts)
    4. Default Web URL (Homepage) is set to 'coming-soon' (30 pts)
    5. Demo Store Notice is enabled (value = 1) (20 pts)

    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_content_snippet = metadata.get('expected_content_snippet', '<h1>We are launching soon!</h1>')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/soft_launch_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Parse result data
        page_found = result.get('page_found', False)
        page_active_str = str(result.get('page_active', '0')).strip()
        page_active = page_active_str == '1'
        page_content = result.get('page_content', '')
        
        homepage_config = str(result.get('homepage_config', '')).strip()
        demo_notice_config = str(result.get('demo_notice_config', '')).strip()

        logger.info(f"Verification Data: PageFound={page_found}, Active={page_active}, HomeConfig={homepage_config}, DemoConfig={demo_notice_config}")

        # Criterion 1: CMS Page 'coming-soon' exists (20 pts)
        if page_found:
            score += 20
            feedback_parts.append("CMS Page 'coming-soon' created (20 pts)")
        else:
            feedback_parts.append("CMS Page 'coming-soon' NOT found")

        # Criterion 2: Page is Enabled (10 pts)
        if page_found and page_active:
            score += 10
            feedback_parts.append("Page status is Enabled (10 pts)")
        elif page_found:
            feedback_parts.append("Page exists but is Disabled (0 pts)")

        # Criterion 3: Page Content Correct (20 pts)
        # Normalize content for comparison (remove extra spaces/newlines)
        content_snippet_clean = expected_content_snippet.replace(" ", "").lower()
        page_content_clean = page_content.replace(" ", "").lower()
        
        if page_found and content_snippet_clean in page_content_clean:
            score += 20
            feedback_parts.append("Page content matches requirements (20 pts)")
        elif page_found:
            feedback_parts.append(f"Page content incorrect. Expected to contain '{expected_content_snippet}'")

        # Criterion 4: Homepage Configured (30 pts)
        if homepage_config == 'coming-soon':
            score += 30
            feedback_parts.append("Default Homepage correctly set to 'coming-soon' (30 pts)")
        else:
            feedback_parts.append(f"Homepage config incorrect. Expected 'coming-soon', got '{homepage_config}'")

        # Criterion 5: Demo Store Notice Enabled (20 pts)
        if demo_notice_config == '1':
            score += 20
            feedback_parts.append("Demo Store Notice enabled (20 pts)")
        else:
            feedback_parts.append(f"Demo Store Notice incorrect. Expected '1', got '{demo_notice_config}'")

        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}