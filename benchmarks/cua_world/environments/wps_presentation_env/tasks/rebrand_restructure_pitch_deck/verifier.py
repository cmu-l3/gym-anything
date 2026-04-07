"""
Verifier for rebrand_restructure_pitch_deck task.

Task: Management consultant must rebrand a 25-slide consulting pitch deck:
  1. Find & Replace "Apex Consulting Partners" → "Meridian Strategy Group"
  2. Correct 3 revenue figures in the Case Study data table
  3. Move 4 "Our Team" slides to immediately after the title slide
  4. Insert new "At a Glance" slide at position 2 with key metrics table
  5. Add confidentiality footer on all slides except title
  6. Save as new file without modifying original

Scoring (100 pts total):
- 10 pts: Output file exists at expected path
-  5 pts: Original file unchanged (25 slides)
- 10 pts: No "Apex Consulting Partners" in any slide text
-  5 pts: "Meridian Strategy Group" appears in 3+ slides
-  5 pts: Email updated to contact@meridianstrategy.com
- 15 pts: 3 table cell corrections correct (5 pts each)
- 15 pts: "Our Team" slides in positions 3-6
- 10 pts: "At a Glance" slide exists at position 2 with table
- 10 pts: At a Glance table contains correct metrics data
- 10 pts: Footer present on non-title slides
-  5 pts: Slide count is 26

Pass threshold: 65 pts
"""

import json
import os

RESULT_FILE = '/tmp/rebrand_restructure_result.json'

# Expected correct table values after agent fixes them
EXPECTED_TABLE_CORRECTIONS = {
    "Client Revenue (Post),Q2 2024": "$15.6M",
    "Revenue Uplift,Q1 2024": "$1.8M",
    "Revenue Uplift,Q3 2024": "$3.3M",
}

# Spot-check values for the At a Glance table
AT_A_GLANCE_CHECKS = {
    "Fortune 500 Clients,2023": "47",
    "Total Revenue,2024 YTD": "$285M",
    "Employee NPS Score,2023": "72",
}


def verify_rebrand_restructure_pitch_deck(trajectory, env_info, task_info):
    local_tmp = '/tmp/_rebrand_restructure_result_local.json'
    try:
        env_info['copy_from_env'](RESULT_FILE, local_tmp)
    except Exception as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Could not retrieve result file: {e}. Export script may not have run.',
        }

    try:
        with open(local_tmp, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Could not parse result JSON: {e}',
        }

    if result.get('error') and not result.get('output_exists'):
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Export error: {result["error"]}',
        }

    score = 0
    feedback_parts = []

    # Anti-gaming: output must be created after task start
    try:
        with open('/tmp/rebrand_restructure_start_ts', 'r') as f:
            task_start = int(f.read().strip())
        output_mtime = result.get('output_mtime', 0)
        if output_mtime and output_mtime <= task_start:
            return {
                'passed': False,
                'score': 0,
                'feedback': 'Output file existed before the task started.',
            }
    except Exception:
        pass

    # 1. Output file exists (10 pts)
    if result.get('output_exists'):
        score += 10
        n = result.get('output_slide_count', 0)
        feedback_parts.append(f'Output file exists ({n} slides) (+10)')
    else:
        feedback_parts.append('Output file not found (0 pts)')
        return {
            'passed': False,
            'score': 0,
            'feedback': '\n'.join(['Score: 0/100'] + feedback_parts),
        }

    # 2. Original file unchanged (5 pts)
    if result.get('original_unchanged'):
        score += 5
        feedback_parts.append('Original file unchanged (+5)')
    else:
        feedback_parts.append('Original file was modified or missing (0 pts)')

    # 3. No old company name remaining (10 pts)
    old_name_remaining = result.get('old_name_occurrences', [])
    if not old_name_remaining:
        score += 10
        feedback_parts.append('All "Apex Consulting Partners" instances removed (+10)')
    else:
        feedback_parts.append(
            f'{len(old_name_remaining)} slides still contain "Apex Consulting Partners" (0 pts)'
        )

    # 4. New company name present (5 pts)
    new_name_count = result.get('new_name_count', 0)
    if new_name_count >= 3:
        score += 5
        feedback_parts.append(f'"Meridian Strategy Group" found in {new_name_count} slides (+5)')
    else:
        feedback_parts.append(
            f'"Meridian Strategy Group" found in only {new_name_count} slides, expected 3+ (0 pts)'
        )

    # 5. Email updated (5 pts)
    if result.get('new_email_found') and not result.get('old_email_found'):
        score += 5
        feedback_parts.append('Email updated to contact@meridianstrategy.com (+5)')
    elif result.get('new_email_found'):
        score += 3
        feedback_parts.append('New email found but old email also still present (+3)')
    else:
        feedback_parts.append('Email not updated (0 pts)')

    # 6. Table corrections (5 pts each, 15 pts total)
    table_cells = result.get('case_study_table_cells', {})
    table_pts = 0
    for cell_key, expected_val in EXPECTED_TABLE_CORRECTIONS.items():
        actual = table_cells.get(cell_key, '')
        if expected_val.replace('$', '').replace('M', '') in actual.replace('$', '').replace('M', ''):
            table_pts += 5
    score += table_pts
    if table_pts == 15:
        feedback_parts.append('All 3 table corrections correct (+15)')
    else:
        feedback_parts.append(f'{table_pts // 5}/3 table corrections correct (+{table_pts})')

    # 7. Our Team slides in positions 3-6 (15 pts)
    our_team = result.get('our_team_positions', [])
    our_team_pos = sorted([t['pos'] for t in our_team])
    if our_team_pos == [3, 4, 5, 6]:
        score += 15
        feedback_parts.append('Our Team slides correctly at positions 3-6 (+15)')
    elif len(our_team) == 4 and all(p <= 10 for p in our_team_pos):
        score += 8
        feedback_parts.append(
            f'Our Team slides moved to front but not exact positions 3-6: {our_team_pos} (+8)'
        )
    elif len(our_team) == 4:
        feedback_parts.append(
            f'Our Team slides at positions {our_team_pos}, expected 3-6 (0 pts)'
        )
    else:
        feedback_parts.append(
            f'Found {len(our_team)} Our Team slides, expected 4 (0 pts)'
        )

    # 8. At a Glance slide at position 2 (10 pts)
    if result.get('at_a_glance_found') and result.get('at_a_glance_pos') == 2:
        score += 10
        feedback_parts.append('"At a Glance" slide at position 2 (+10)')
    elif result.get('at_a_glance_found'):
        score += 5
        pos = result.get('at_a_glance_pos')
        feedback_parts.append(f'"At a Glance" slide found at position {pos}, expected 2 (+5)')
    else:
        feedback_parts.append('"At a Glance" slide not found (0 pts)')

    # 9. At a Glance table content (10 pts)
    glance_cells = result.get('at_a_glance_table_cells', {})
    if result.get('at_a_glance_has_table') and glance_cells:
        glance_pts = 0
        for cell_key, expected_val in AT_A_GLANCE_CHECKS.items():
            actual = glance_cells.get(cell_key, '')
            if expected_val in actual:
                glance_pts += 3
        glance_pts = min(10, glance_pts + (1 if len(glance_cells) >= 8 else 0))
        score += glance_pts
        feedback_parts.append(f'At a Glance table content check (+{glance_pts})')
    else:
        feedback_parts.append('At a Glance table missing or empty (0 pts)')

    # 10. Footer present on non-title slides (10 pts)
    # Use full match count (includes "Meridian Strategy Group 2024") when available
    footer_full = result.get('footer_full_match_count', 0)
    footer_count = result.get('footer_slide_count', 0)
    footer_total = result.get('footer_total_checked', 0)
    best_footer = footer_full if footer_full > 0 else footer_count
    if footer_total > 0 and best_footer >= footer_total * 0.8:
        score += 10
        feedback_parts.append(
            f'Footer found on {best_footer}/{footer_total} non-title slides (+10)'
        )
    elif best_footer > 0:
        partial = min(10, int(10 * best_footer / max(footer_total, 1)))
        score += partial
        feedback_parts.append(
            f'Footer found on {best_footer}/{footer_total} slides (+{partial})'
        )
    else:
        feedback_parts.append('No footer found on any slide (0 pts)')

    # 11. Slide count = 26 (5 pts)
    slide_count = result.get('output_slide_count', 0)
    if slide_count == 26:
        score += 5
        feedback_parts.append('Slide count is 26 as expected (+5)')
    elif 24 <= slide_count <= 28:
        score += 2
        feedback_parts.append(f'Slide count is {slide_count}, expected 26 (+2)')
    else:
        feedback_parts.append(f'Slide count is {slide_count}, expected 26 (0 pts)')

    passed = score >= 65

    return {
        'passed': passed,
        'score': score,
        'feedback': '\n'.join([
            f'Score: {score}/100  (pass threshold: 65)',
            f'Output: {slide_count} slides',
            '',
        ] + feedback_parts),
    }
