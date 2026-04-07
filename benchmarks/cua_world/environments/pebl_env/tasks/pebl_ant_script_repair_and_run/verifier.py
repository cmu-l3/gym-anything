"""
Verifier for pebl_ant_script_repair_and_run task.

Scoring (100 pts total):
  1. gSOA corrected to 400 in the .pbl file                        (20 pts)
  2. gCueTypes contains all 4 required cue types incl. double_cue  (25 pts)
  3. gFlankerTypes contains 'neutral' (all 3 flanker types)        (25 pts)
  4. gTestBlocks corrected to 3 in the .pbl file                   (15 pts)
  5. Bug report file exists and mentions all 4 bugs                 (15 pts)

Pass threshold: 60 pts
"""

import os
import re
import tempfile

PASS_THRESHOLD = 60

REQUIRED_CUE_TYPES = {"no_cue", "center_cue", "double_cue", "spatial_cue"}
REQUIRED_FLANKER_TYPES = {"congruent", "incongruent", "neutral"}


def _read_file_from_env(copy_from_env, remote_path):
    """Copy a file from the VM and return its text content."""
    with tempfile.NamedTemporaryFile(suffix='.txt', delete=False) as tmp:
        tmp_path = tmp.name
    try:
        copy_from_env(remote_path, tmp_path)
        with open(tmp_path, encoding='utf-8', errors='replace') as f:
            return f.read()
    except (FileNotFoundError, OSError):
        return None
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass


def verify_pebl_ant_script_repair_and_run(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # Read the .pbl script
    pbl_content = _read_file_from_env(copy_from_env, '/home/ga/pebl/tasks/ant/ant_task.pbl')
    if pbl_content is None:
        feedback_parts.append('[0] ANT script /home/ga/pebl/tasks/ant/ant_task.pbl not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}

    feedback_parts.append('[ok] ANT script found.')

    # --- Criterion 1: gSOA corrected to 400 ---
    # Look for 'define gSOA' line; value should be 400 (not 4000)
    soa_match = re.search(r'define\s+gSOA\s*\{[^}]*\}', pbl_content, re.IGNORECASE)
    soa_ok = False
    if soa_match:
        soa_text = soa_match.group(0)
        nums = re.findall(r'\d+', soa_text)
        if nums:
            soa_val = int(nums[0])
            if soa_val == 400:
                soa_ok = True
            elif soa_val == 4000:
                feedback_parts.append('[0] gSOA is still 4000 (not corrected to 400 ms).')
            else:
                # Accept values in range 300-600ms as reasonable
                if 300 <= soa_val <= 600:
                    soa_ok = True
                    feedback_parts.append(f'[~] gSOA = {soa_val} (expected 400; accepting range 300-600ms).')

    if soa_ok:
        score += 20
        feedback_parts.append('[+20] gSOA corrected to 400 ms (Bug 1 fixed).')
    elif not any('gSOA' in p for p in feedback_parts):
        feedback_parts.append('[0] gSOA definition not found or value not corrected.')

    # --- Criterion 2: gCueTypes contains all 4 required types including double_cue ---
    cue_match = re.search(r'define\s+gCueTypes\s*\{([^}]*)\}', pbl_content, re.IGNORECASE)
    cue_ok = False
    if cue_match:
        cue_text = cue_match.group(1)
        found_cues = set(re.findall(r'"(\w+)"', cue_text))
        missing_cues = REQUIRED_CUE_TYPES - found_cues
        if not missing_cues:
            cue_ok = True
        elif len(missing_cues) == 1 and 'double_cue' not in found_cues:
            feedback_parts.append('[0] gCueTypes still missing "double_cue" (Bug 2 not fixed).')
        else:
            feedback_parts.append(f'[0] gCueTypes missing: {missing_cues}.')

    if cue_ok:
        score += 25
        feedback_parts.append('[+25] gCueTypes contains all 4 cue types incl. double_cue (Bug 2 fixed).')
    elif not any('gCueTypes' in p for p in feedback_parts):
        feedback_parts.append('[0] gCueTypes definition not found.')

    # --- Criterion 3: gFlankerTypes contains 'neutral' ---
    flanker_match = re.search(r'define\s+gFlankerTypes\s*\{([^}]*)\}', pbl_content, re.IGNORECASE)
    flanker_ok = False
    if flanker_match:
        flanker_text = flanker_match.group(1)
        found_flankers = set(re.findall(r'"(\w+)"', flanker_text))
        missing_flankers = REQUIRED_FLANKER_TYPES - found_flankers
        if not missing_flankers:
            flanker_ok = True
        elif 'neutral' not in found_flankers:
            feedback_parts.append('[0] gFlankerTypes still missing "neutral" (Bug 3 not fixed).')
        else:
            feedback_parts.append(f'[0] gFlankerTypes missing: {missing_flankers}.')

    if flanker_ok:
        score += 25
        feedback_parts.append('[+25] gFlankerTypes contains all 3 flanker types incl. neutral (Bug 3 fixed).')
    elif not any('gFlankerTypes' in p for p in feedback_parts):
        feedback_parts.append('[0] gFlankerTypes definition not found.')

    # --- Criterion 4: gTestBlocks corrected to 3 ---
    blocks_match = re.search(r'define\s+gTestBlocks\s*\{[^}]*\}', pbl_content, re.IGNORECASE)
    blocks_ok = False
    if blocks_match:
        blocks_text = blocks_match.group(0)
        nums = re.findall(r'\d+', blocks_text)
        if nums:
            blocks_val = int(nums[0])
            if blocks_val == 3:
                blocks_ok = True
            elif blocks_val == 1:
                feedback_parts.append('[0] gTestBlocks is still 1 (not corrected to 3).')
            else:
                feedback_parts.append(f'[0] gTestBlocks = {blocks_val} (expected 3).')

    if blocks_ok:
        score += 15
        feedback_parts.append('[+15] gTestBlocks corrected to 3 (Bug 4 fixed).')
    elif not any('gTestBlocks' in p for p in feedback_parts):
        feedback_parts.append('[0] gTestBlocks definition not found.')

    # --- Criterion 5: Bug report exists and mentions all 4 bugs ---
    bug_report = _read_file_from_env(copy_from_env, '/home/ga/pebl/tasks/ant/bug_report.txt')
    report_score = 0
    if bug_report is not None:
        bug_report_lower = bug_report.lower()
        # Check each bug is mentioned
        bug_mentions = 0
        # Bug 1: SOA
        if any(kw in bug_report_lower for kw in ['soa', '4000', 'stimulus onset', 'onset asynchrony']):
            bug_mentions += 1
        # Bug 2: double_cue
        if any(kw in bug_report_lower for kw in ['double_cue', 'double cue', 'cue type', 'cuetype']):
            bug_mentions += 1
        # Bug 3: neutral
        if any(kw in bug_report_lower for kw in ['neutral', 'flanker type', 'flankertype']):
            bug_mentions += 1
        # Bug 4: test blocks
        if any(kw in bug_report_lower for kw in ['testblocks', 'test blocks', 'block', 'gtest']):
            bug_mentions += 1

        if bug_mentions >= 4:
            report_score = 15
            feedback_parts.append('[+15] Bug report found and mentions all 4 bugs.')
        elif bug_mentions >= 2:
            report_score = 8
            feedback_parts.append(f'[+8] Bug report found but only mentions {bug_mentions}/4 bugs (partial).')
        else:
            feedback_parts.append(f'[+0] Bug report found but mentions only {bug_mentions}/4 bugs.')
    else:
        feedback_parts.append('[0] Bug report ~/pebl/tasks/ant/bug_report.txt not found.')

    score += report_score

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }
