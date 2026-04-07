"""
Verifier for pebl_visual_search_task_design task.

Scoring (100 pts total):
  1. PEBL script exists at the correct path                               (10 pts)
  2. Fixation duration 500 ms in script                                   (15 pts)
  3. Display max duration 3000 ms in script                               (15 pts)
  4. ITI of 800 ms in script                                              (10 pts)
  5. All 3 set sizes (4, 8, 16) present in script                        (15 pts)
  6. Both search types (feature, conjunction) present in script           (15 pts)
  7. Response keys z and / present in script                              (10 pts)
  8. Design rationale document exists and references spec                  (10 pts)

Pass threshold: 60 pts

Note: The verifier checks for required parameter values using regex patterns.
It is intentionally lenient about exact variable names, allowing agents to
use their own naming conventions as long as the required values appear in
the script in plausible contexts.
"""

import os
import re
import tempfile

PASS_THRESHOLD = 60

REQUIRED_SET_SIZES = {4, 8, 16}
SEARCH_TYPE_KEYWORDS = ['feature', 'conjunction']
FIXATION_MS = 500
DISPLAY_MAX_MS = 3000
ITI_MS = 800


def _read_file_from_env(copy_from_env, remote_path):
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


def _has_number(text, number, context_radius=80):
    """Check if a number appears in the text in a plausible assignment/list context."""
    pattern = rf'\b{number}\b'
    matches = list(re.finditer(pattern, text))
    if not matches:
        return False
    for m in matches:
        start = max(0, m.start() - context_radius)
        end = min(len(text), m.end() + context_radius)
        ctx = text[start:end].lower()
        # Skip if in a comment-only context that's clearly not a parameter
        if re.search(r'#.*' + str(number) + r'.*\n', ctx):
            return True  # Comments count if number is there
        return True
    return False


def verify_pebl_visual_search_task_design(trajectory, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    score = 0
    feedback_parts = []

    # Read the PEBL script
    pbl_content = _read_file_from_env(
        copy_from_env, '/home/ga/pebl/tasks/visual_search/visual_search_task.pbl'
    )

    # --- Criterion 1: Script exists ---
    if pbl_content is None:
        feedback_parts.append('[0] PEBL script /home/ga/pebl/tasks/visual_search/visual_search_task.pbl not found.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}

    if len(pbl_content.strip()) < 50:
        feedback_parts.append('[0] PEBL script exists but appears to be empty or trivially short.')
        return {'passed': False, 'score': 0, 'feedback': ' '.join(feedback_parts)}

    score += 10
    feedback_parts.append('[+10] PEBL script found.')

    pbl_lower = pbl_content.lower()

    # --- Criterion 2: Fixation duration 500ms ---
    # Look for 500 appearing near fixation/fix/wait/delay keywords
    fixation_ok = False
    if re.search(r'500', pbl_content):
        # Check if 500 appears near fixation-related words
        ctx_pattern = re.compile(r'(fix|fixat|iti|wait|delay|cross|blank)[^\n]{0,120}500|500[^\n]{0,120}(fix|fixat|iti|wait|delay|cross)', re.IGNORECASE)
        if ctx_pattern.search(pbl_content):
            fixation_ok = True
        # Also accept if 500 is a defined constant (e.g., gFixDuration <- 500)
        elif re.search(r'(gFix|fix_dur|fixation_dur|fix_time)[^\n]{0,30}500', pbl_content, re.IGNORECASE):
            fixation_ok = True
        # Accept raw Wait(500) or similar
        elif re.search(r'wait\s*\(\s*500\s*\)', pbl_content, re.IGNORECASE):
            fixation_ok = True
        elif re.search(r'define\s+\w*(fix|fixat)\w*\s*\{[^}]*500[^}]*\}', pbl_content, re.IGNORECASE):
            fixation_ok = True

    if fixation_ok:
        score += 15
        feedback_parts.append('[+15] Fixation duration 500ms found in script.')
    else:
        # Check for any mention of 500ms
        if '500' in pbl_content:
            score += 8
            feedback_parts.append('[+8] Value 500 found in script (may be fixation duration; context unclear).')
        else:
            feedback_parts.append('[0] Fixation duration 500ms not found in script.')

    # --- Criterion 3: Display max duration 3000ms ---
    display_ok = False
    if re.search(r'3000', pbl_content):
        ctx_pattern = re.compile(
            r'(display|target|stimulus|search|array|stim|timeout|max)[^\n]{0,120}3000|'
            r'3000[^\n]{0,120}(display|target|stimulus|search|array|stim|timeout|max)',
            re.IGNORECASE
        )
        if ctx_pattern.search(pbl_content):
            display_ok = True
        elif re.search(r'(gTarget|target_dur|stim_dur|display_dur|max_rt)[^\n]{0,30}3000', pbl_content, re.IGNORECASE):
            display_ok = True
        elif re.search(r'waitforkey\w*[^)]*3000', pbl_content, re.IGNORECASE):
            display_ok = True
        elif re.search(r'define\s+\w*(target|display|stim|dur)\w*\s*\{[^}]*3000[^}]*\}', pbl_content, re.IGNORECASE):
            display_ok = True

    if display_ok:
        score += 15
        feedback_parts.append('[+15] Display max duration 3000ms found in script.')
    else:
        if '3000' in pbl_content:
            score += 8
            feedback_parts.append('[+8] Value 3000 found in script (may be display duration; context unclear).')
        else:
            feedback_parts.append('[0] Display max duration 3000ms not found in script.')

    # --- Criterion 4: ITI 800ms ---
    iti_ok = False
    if re.search(r'800', pbl_content):
        ctx_pattern = re.compile(
            r'(iti|inter.trial|inter_trial|blank|interval|intertrial)[^\n]{0,120}800|'
            r'800[^\n]{0,120}(iti|inter.trial|inter_trial|blank|interval)',
            re.IGNORECASE
        )
        if ctx_pattern.search(pbl_content):
            iti_ok = True
        elif re.search(r'(gITI|iti_dur|inter_trial)[^\n]{0,30}800', pbl_content, re.IGNORECASE):
            iti_ok = True
        elif re.search(r'define\s+\w*iti\w*\s*\{[^}]*800[^}]*\}', pbl_content, re.IGNORECASE):
            iti_ok = True

    if iti_ok:
        score += 10
        feedback_parts.append('[+10] ITI 800ms found in script.')
    else:
        if '800' in pbl_content:
            score += 5
            feedback_parts.append('[+5] Value 800 found in script (may be ITI; context unclear).')
        else:
            feedback_parts.append('[0] ITI 800ms not found in script.')

    # --- Criterion 5: All 3 set sizes (4, 8, 16) ---
    set_sizes_found = set()
    for ss in REQUIRED_SET_SIZES:
        if re.search(rf'\b{ss}\b', pbl_content):
            set_sizes_found.add(ss)

    if set_sizes_found == REQUIRED_SET_SIZES:
        score += 15
        feedback_parts.append(f'[+15] All 3 set sizes {sorted(REQUIRED_SET_SIZES)} found in script.')
    elif len(set_sizes_found) == 2:
        partial = 8
        score += partial
        feedback_parts.append(f'[+{partial}] {len(set_sizes_found)}/3 set sizes found: {sorted(set_sizes_found)}.')
    elif len(set_sizes_found) == 1:
        partial = 4
        score += partial
        feedback_parts.append(f'[+{partial}] Only 1/3 set sizes found.')
    else:
        feedback_parts.append(f'[0] Set sizes {sorted(REQUIRED_SET_SIZES)} not found in script.')

    # --- Criterion 6: Both search types (feature, conjunction) ---
    search_types_found = []
    for st in SEARCH_TYPE_KEYWORDS:
        if st in pbl_lower:
            search_types_found.append(st)

    if len(search_types_found) == 2:
        score += 15
        feedback_parts.append('[+15] Both search types (feature, conjunction) found in script.')
    elif len(search_types_found) == 1:
        partial = 8
        score += partial
        feedback_parts.append(f'[+{partial}] Only 1/2 search types found: {search_types_found}.')
    else:
        # Check for alternative terms
        if any(kw in pbl_lower for kw in ['pop.out', 'popout', 'singleton']):
            score += 5
            feedback_parts.append('[+5] Feature-search-related terms found (pop-out/singleton) but "feature"/"conjunction" not explicit.')
        else:
            feedback_parts.append('[0] Neither "feature" nor "conjunction" search types found in script.')

    # --- Criterion 7: Response keys z and / ---
    # "z/" together in a string means both z and / are response keys (PEBL WaitForKeyPress pattern)
    has_both_as_pair = ('z/' in pbl_content or '"z/"' in pbl_content or "'z/'" in pbl_content)
    has_z_key = bool(has_both_as_pair or
                     re.search(r'"z"', pbl_content, re.IGNORECASE) or
                     re.search(r"'z'", pbl_content, re.IGNORECASE) or
                     re.search(r'\bz\b.*key\b|\bkey\b.*\bz\b', pbl_content, re.IGNORECASE))
    has_slash_key = bool(has_both_as_pair or
                         re.search(r'"/"', pbl_content) or
                         re.search(r"'/'", pbl_content) or
                         '"/", "z"' in pbl_content or
                         '"z", "/"' in pbl_content)

    if has_z_key and has_slash_key:
        score += 10
        feedback_parts.append('[+10] Response keys z and / both found in script.')
    elif has_z_key or has_slash_key:
        partial = 5
        score += partial
        feedback_parts.append(f'[+{partial}] Only one of response keys z / found in script.')
    else:
        feedback_parts.append('[0] Response keys z and / not found in script.')

    # --- Criterion 8: Design rationale document exists ---
    rationale = _read_file_from_env(
        copy_from_env, '/home/ga/pebl/tasks/visual_search/design_rationale.txt'
    )
    if rationale is not None and len(rationale.strip()) > 50:
        rationale_lower = rationale.lower()
        # Check if it references the spec or the paradigm
        has_ref = any(kw in rationale_lower for kw in [
            'treisman', 'feature integration', 'visual search', 'spec', 'specification',
            'feature search', 'conjunction search', 'set size'
        ])
        if has_ref:
            score += 10
            feedback_parts.append('[+10] Design rationale found and references the paradigm/specification.')
        else:
            score += 5
            feedback_parts.append('[+5] Design rationale found but does not clearly reference specification (partial).')
    else:
        feedback_parts.append('[0] Design rationale ~/pebl/tasks/visual_search/design_rationale.txt not found or empty.')

    passed = score >= PASS_THRESHOLD
    return {
        'passed': passed,
        'score': score,
        'feedback': ' '.join(feedback_parts)
    }
