#!/usr/bin/env python3
"""
Verifier for create_order_report_view task.

Checks:
1. View configuration exists in Drupal (10 pts)
2. View is enabled (status=True) (5 pts)
3. Base table is 'commerce_order_field_data' (10 pts)
4. Display is a Page with path '/admin/commerce/order-report' (15 pts)
5. Format is 'table' (5 pts)
6. Fields: Includes order_id, total_price, state, created (20 pts)
7. Filters: Includes State and Created, and they are EXPOSED (20 pts)
8. Sort: Created date DESC (10 pts)
9. Pagination: 25 items (5 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_order_report_view(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Load main result
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        view_exists = result.get('view_exists', False)
        
        if not view_exists:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "View 'order_report' (or 'commerce_order_report') was not found in Drupal configuration."
            }

        # Load view config
        temp_config = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        config = {}
        try:
            copy_from_env("/tmp/view_config.json", temp_config.name)
            with open(temp_config.name, 'r') as f:
                # The drush output might be a dict with the config name as key, or just the config object
                # Drush config:get --format=json usually returns {"key": {config...}}
                raw_config = json.load(f)
                # Handle structure: {"views.view.order_report": {...}}
                if raw_config and isinstance(raw_config, dict):
                    key = next(iter(raw_config))
                    config = raw_config[key]
                else:
                    config = raw_config
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"View exists but failed to parse config: {e}"}
        finally:
            os.unlink(temp_config.name)

        score = 0
        feedback = []

        # 1. View Exists (10 pts) - Already checked above
        score += 10
        feedback.append("View created")

        # 2. View Enabled (5 pts)
        if config.get('status') is True:
            score += 5
            feedback.append("View is enabled")
        else:
            feedback.append("View is disabled")

        # 3. Base Table (10 pts)
        base_table = config.get('base_table', '')
        if base_table == 'commerce_order_field_data':
            score += 10
            feedback.append("Correct base table (Commerce Order)")
        elif base_table == 'commerce_order': # Sometimes just this
            score += 10
            feedback.append("Correct base table (Commerce Order)")
        else:
            feedback.append(f"Incorrect base table: {base_table}")

        # Helper to find the page display
        display = config.get('display', {})
        default_display = display.get('default', {}).get('display_options', {})
        
        # Find the page display (usually page_1)
        page_display = None
        for key, val in display.items():
            if val.get('display_plugin') == 'page':
                page_display = val.get('display_options', {})
                break
        
        if not page_display:
            feedback.append("No Page display found")
        else:
            # 4. Path Check (15 pts)
            path = page_display.get('path', '')
            if path == 'admin/commerce/order-report' or path == '/admin/commerce/order-report':
                score += 15
                feedback.append("Path is correct")
            else:
                feedback.append(f"Incorrect path: {path}")

            # 5. Format Check (5 pts)
            # Format can be set on page or default
            style_plugin = page_display.get('style', {}).get('type') or default_display.get('style', {}).get('type')
            if style_plugin == 'table':
                score += 5
                feedback.append("Format is Table")
            else:
                feedback.append(f"Incorrect format: {style_plugin}")

            # 6. Fields Check (20 pts)
            # Fields are usually in default display, but can be overridden in page
            fields = page_display.get('fields') or default_display.get('fields') or {}
            
            required_fields = ['order_id', 'total_price', 'state', 'created']
            found_fields = 0
            missing = []
            
            # Normalize field names from config keys
            # Keys usually look like 'order_id', 'total_price__number', etc.
            field_keys = list(fields.keys())
            
            # Logic: Check loosely for presence
            has_id = any('order_id' in k for k in field_keys)
            has_price = any('total_price' in k for k in field_keys)
            has_state = any('state' in k for k in field_keys)
            has_created = any('created' in k for k in field_keys)
            
            if has_id: found_fields += 1
            if has_price: found_fields += 1
            if has_state: found_fields += 1
            if has_created: found_fields += 1
            
            # Need at least 5 fields total (any 5) and specifically the required ones
            if len(field_keys) >= 5 and found_fields == 4:
                score += 20
                feedback.append("Required fields present")
            elif found_fields == 4:
                score += 15
                feedback.append("Required fields present but fewer than 5 columns")
            else:
                score += (found_fields * 3)
                feedback.append(f"Missing some required fields (Found {found_fields}/4)")

            # 7. Filters Check (20 pts)
            filters = page_display.get('filters') or default_display.get('filters') or {}
            
            has_state_filter = False
            has_created_filter = False
            state_exposed = False
            created_exposed = False
            
            for key, f in filters.items():
                if 'state' in key or f.get('field') == 'state':
                    has_state_filter = True
                    if f.get('exposed'): state_exposed = True
                if 'created' in key or f.get('field') == 'created':
                    has_created_filter = True
                    if f.get('exposed'): created_exposed = True
            
            if has_state_filter and state_exposed: score += 10
            if has_created_filter and created_exposed: score += 10
            
            if has_state_filter and not state_exposed: feedback.append("State filter present but not exposed")
            if has_created_filter and not created_exposed: feedback.append("Created filter present but not exposed")
            if not has_state_filter: feedback.append("Missing State filter")
            if not has_created_filter: feedback.append("Missing Created filter")
            if state_exposed and created_exposed: feedback.append("Filters correctly configured")

            # 8. Sort Check (10 pts)
            sorts = page_display.get('sorts') or default_display.get('sorts') or {}
            # Config is an ordered dict usually, look at the first sort
            # Or iterate values
            sort_correct = False
            for key, s in sorts.items():
                if 'created' in key or s.get('field') == 'created':
                    if s.get('order') == 'DESC':
                        sort_correct = True
                    break
            
            if sort_correct:
                score += 10
                feedback.append("Sort order correct (Created DESC)")
            else:
                feedback.append("Sort order incorrect")

            # 9. Pagination Check (5 pts)
            pager = page_display.get('pager') or default_display.get('pager') or {}
            items_per_page = pager.get('options', {}).get('items_per_page')
            
            if items_per_page == 25 or items_per_page == '25':
                score += 5
                feedback.append("Pagination correct (25)")
            else:
                feedback.append(f"Pagination incorrect ({items_per_page})")
            
            # 10. Access Check (Bonus/Implicit in total score calc, I'll allocate 0 pts but verify)
            access = page_display.get('access') or default_display.get('access') or {}
            access_type = access.get('type')
            if access_type in ['perm', 'role']:
                feedback.append("Access restriction configured")
            else:
                feedback.append(f"Access restriction missing (type: {access_type})")

        passed = score >= 60 and page_display is not None
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}