# PsychoPy Environment (`psychopy_env`) - Evidence Documentation

## Test Date
2026-02-06 (clean test without cache)

## Environment Configuration
- **Base image**: `ubuntu-gnome-systemd_highres` (1920x1080)
- **Resources**: 4 CPU, 8GB RAM, net=true
- **PsychoPy version**: 2025.2.4 (beta)
- **wxPython version**: 4.2.4 gtk3 (phoenix) wxWidgets 3.2.8
- **NumPy version**: 2.2.6
- **SciPy version**: 1.14.1
- **Boot time**: ~171 seconds total (159s install + 11s task hooks)

## Verification Checklist

| Check | Status | Evidence |
|-------|--------|----------|
| Installation script completes | PASS | `install_log_snippet.txt` - ends with "=== PsychoPy installation complete ===" |
| Setup script completes | PASS | `setup_log_snippet.txt` - PsychoPy window detected, configs patched |
| PsychoPy Builder visible | PASS | `builder_with_experiment.png` - Builder with stroop_experiment loaded |
| PsychoPy Runner visible | PASS | `runner_view.png` - Runner panel visible |
| PsychoPy Coder visible | PASS | `coder_view.png` - Coder panel visible |
| No blocking dialogs | PASS | After appData.cfg fix, "Changes" dialog suppressed |
| Task setup runs | PASS | `task_setup_log.txt` - task setup completes, PsychoPy launched |
| Export script produces valid JSON | PASS | `verification_result.json` - all fields populated |
| "Do nothing" case scores 0 | PASS | All criteria fail, score=0, passed=false |

## Screenshots

### `builder_with_experiment.png`
PsychoPy Builder with loaded stroop_experiment.psyexp showing:
- "trial" routine with `text` (TextComponent) and `key_resp` (KeyboardComponent)
- Flow panel with `trial` routine wrapped in `trials` loop
- Components panel on right side
- Title bar: "stroop_experiment.psyexp - PsychoPy Builder (v2025.2.4beta)"

### `runner_view.png`
PsychoPy Runner panel for experiment execution.

### `coder_view.png`
PsychoPy Coder panel for Python script editing.

## Log Snippets

### Install Log (`install_log_snippet.txt`)
Key output from pre_start hook (1640 lines total):
- Successfully installed PsychoPy 2025.2.4 with all dependencies
- wxPython 4.2.4 installed from prebuilt wheel
- PsychoPy import aborts with dbus error during headless verification (expected - works fine with DISPLAY)
- NumPy 2.2.6, SciPy 1.14.1 confirmed

### Setup Log (`setup_log_snippet.txt`)
Key output from post_start hook:
- PsychoPy demos copied from package directory (fallback path used)
- PsychoPy window detected after 3 seconds
- Config patched: lastVersion set to 2025.2.4
- PsychoPy restarted with patched configs

### Task Setup Log (`task_setup_log.txt`)
Key output from pre_task hook:
- PsychoPy launched as ga user (via su - ga -c)
- Builder window focused and maximized
- Startup dialogs dismissed
- Task instructions displayed

## Verifier Score Breakdown (create_stroop_experiment, post-audit)
| Criterion | Points | Notes |
|-----------|--------|-------|
| File exists and valid PsychoPy XML | 10 | 3 pts partial for invalid XML |
| File modified during task | 10 | |
| Has 'trial' routine (exact name) | 10 | 5 pts partial for any routine |
| Text component with variable reference ($text) | 10 | 5 pts without variable ref |
| Keyboard component with corrAns reference | 10 | 5 pts without corrAns |
| Loop with conditions + nReps=2 | 10 | 7 pts for wrong nReps |
| Structural complexity (genuine PsychoPy file) | 10 | Requires 40+ params, 80+ lines |
| VLM: Builder usage | 0-15 | |
| VLM: Final state | 0-15 | |
| **Programmatic max** | **70** | |
| **Total max** | **100** | Capped at 100 |
| **Pass threshold** | **60** | |

## Anti-Gaming Measures (Audit Round 2, 2026-02-05)

### Nonce Integrity Gate
- `setup_task.sh` generates a random nonce via `generate_nonce()` → `/home/ga/.task_nonce`
- `export_result.sh` reads the nonce and includes it as `result_nonce` in the JSON
- `verifier.py` compares `result_nonce` with the file on disk → instant fail (score=0) on mismatch
- Prevents: manual JSON crafting/tampering

### Structural Complexity Gate
- PsychoPy Builder generates `.psyexp` files with 50-200+ `<Param>` elements and 100-400+ lines
- Hand-crafted gaming files typically have <20 params and <30 lines
- Verifiers check `param_count` and `line_count` with tiered scoring:
  - Full points: ≥40 params AND ≥80 lines
  - Partial (5 pts): ≥20 params AND ≥40 lines
  - Zero: Below threshold
- **Max programmatic score without structural complexity: 60** (exactly at threshold, needs VLM or complexity to pass reliably)

### Component Parameter Validation
- Text components: checks for variable references (`$text`, `$letterColor`)
- Keyboard components: checks for `correctAns`/`corrAns` reference
- Loop: checks exact `nReps` value
- Instructions: checks text and key scoped to instructions routine only

### Metadata Leak Removal
- All `task.json` metadata blocks stripped of verifier-leaking fields
- Only file paths retained (needed by verifier for `copy_from_env`)
- Medium-difficulty task descriptions reduced from step-by-step recipes to goal-oriented requirements

### Setup Script Hardening
- `wait_for_psychopy 30` replaces `sleep 10`
- `focus_builder` / `focus_coder` replaces generic `focus_psychopy`
- `dismiss_psychopy_dialogs` added after launch
- `mkdir -p` for target directories
- PsychoPy launched as ga user via `su - ga -c`

## Audit Fix History

### Round 1 (2026-02-05, first audit)
1. code_simple_experiment description gave away answer → removed code example
2. Export scripts used grep → rewrote with AST/XML parsing
3. Demo unpacking fails silently → direct cp from package dir
4. configure_experiment_settings free points → scoped data filename check
5. modify_demo_experiment nReps too loose → exact comparison
6. Pre-task PsychoPy launched as root → su - ga -c
7. Misleading numpy constraint → removed <2.0

### Round 2 (2026-02-05, comprehensive audit)
1. **CRITICAL**: All tasks gameable without GUI → added nonce gate, structural complexity gate, component param validation
2. **CRITICAL**: Screenshots showed wrong view → setup scripts now focus Builder/Coder specifically
3. **HIGH**: No component parameter validation → text variable refs, keyboard corrAns, nReps checked
4. **HIGH**: Deeper validation awarded zero points → deep validation now primary scoring
5. **HIGH**: Task metadata leaked verifier values → stripped from all task.json
6. **HIGH**: configure score exceeded 100 → score capped at min(score, 100)
7. **HIGH**: modify_demo no Stroop derivation check → has_stroop_content + has_trial_routine
8. **HIGH**: modify_demo no flow ordering check → instructions_before_trial
9. **MEDIUM**: Over-prescriptive descriptions → reduced for medium tasks
10. **MEDIUM**: sleep 10 instead of wait_for_psychopy → wait_for_psychopy 30
11. **MEDIUM**: data filename free points → reduced to 5 pts
12. **MEDIUM**: instruction text checked all routines → scoped to instructions routine
13. **MEDIUM**: instructions routine substring match → exact name match
14. **MEDIUM**: syntax_valid defaulted to True → defaults to False
15. **MEDIUM**: Window size check too loose → validates exact order [1024, 768]
16. **LOW**: Export scripts spawned Python 5-7 times → single Python call
17. **LOW**: JSON construction via heredoc → Python json.dump
18. **LOW**: No startup dialog dismissal → dismiss_psychopy_dialogs added

### Round 3 (2026-02-05, third audit)
1. **CRITICAL**: Stroop demo availability not guaranteed → 3-method package discovery (pip show → python3 import → glob search) in setup_psychopy.sh; active recovery in modify_demo_experiment/setup_task.sh
2. **CRITICAL**: Programmatic bypass possible without VLM (max 70, pass 60) → added independent file re-analysis to all 4 file-based verifiers; verifier pulls actual file from VM and re-parses on host as PRIMARY data source
3. **HIGH**: configure_experiment_settings free points from fullScr=False default → combined fullScr + window size into single 15pt criterion; default alone gives only 3 pts
4. **MODERATE**: code_simple_experiment Coder view not reliably opened → explicit Ctrl+L keyboard shortcut to open Coder before focusing
5. **MODERATE**: modify_demo_experiment Stroop derivation check bypassable → requires 2+ distinct markers (letterColor, stroop, corrAns); tiered scoring (10/5/3/2 pts)
6. **MODERATE**: flanker_conditions.csv data error (row 9: `==>==>==` → `==>==`)
7. **LOW**: `import psychopy` gives full import credit (15 pts) → bare import capped at 5 pts; only specific submodule imports get 15 pts
8. **LOW**: code_simple_experiment text match false positive risk → requires both "press" AND "space" in TextStim args only (removed global string check)

### Round 4 (2026-02-05, fourth audit)
1. **HIGH**: code_simple_experiment gameable without PsychoPy (70 programmatic pts > 60 threshold) → lowered programmatic max to 55 pts, raised VLM to 45 pts; agent MUST use PsychoPy Coder to pass
2. **HIGH**: No semantic correctness check for corrAns in create_conditions_file → added corrAns-vs-stimulus-direction validation (10 pts); verifies center arrow direction matches corrAns
3. **MODERATE**: Conditions file reference too loose in create_stroop_experiment → tightened from `"conditions" in pval.lower()` to `"stroop_conditions" in pval.lower()`
4. **MODERATE**: modify_demo can be created from scratch → added trial_component_count and param_count depth check; full Stroop derivation requires 2+ trial components AND 50+ params
5. **LOW**: Data filename trivially passable in configure_experiment_settings → added check that filename references experiment name, not just default template
6. **LOW**: No letterColor specific check in create_stroop_experiment → added `text_uses_lettercolor` tracking; full points only with `$letterColor` reference

### Round 5 (2026-02-06, fifth audit)
1. **CRITICAL**: create_conditions_file fully gameable without GUI (85 pts programmatic > 60 threshold) → lowered programmatic max to 55 pts, raised VLM to 45 pts (25+20); added second VLM check for final screenshot
2. **CRITICAL**: code_simple_experiment no structural complexity gate → added penalty for short scripts (<5 lines: -10 pts, <8 lines: -5 pts); prevents trivially short terminal-crafted scripts from passing
3. **HIGH**: modify_demo_experiment proceeds when demos missing → setup writes `.demo_status` flag; verifier checks flag and returns instant fail if demos were unavailable
4. **HIGH**: modify_demo Stroop derivation bypassable with marker strings → added `has_demo_component_names` check for original demo components ('word', 'resp'); full points require demo names + markers + structural depth
5. **MODERATE**: Coder view opened via fragile Ctrl+L without verification → multi-method fallback (Ctrl+L → Ctrl+Shift+C → Alt+V menu) with `get_coder_window` verification after each attempt
6. **MODERATE**: VLM yes/no parsing fragile — `'yes' in response` causes false positives → all 5 verifiers updated to use `startswith('yes')` or `re.findall(r'\byes\b')` for whole-word matching
7. **LOW**: Export/verifier inconsistency for stroop conditions ref → export script tightened from `"stroop_conditions" in pval or "conditions" in pval.lower()` to `"stroop_conditions" in pval.lower()` to match verifier

## Known Issues
1. **PsychoPy dbus abort**: `python3 -c "import psychopy"` aborts with dbus error when run without DISPLAY or as root. PsychoPy works fine with `DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1`.
2. **appData.cfg patching**: The `lastVersion` field must be updated AFTER first launch. Fixed by removing `set -e` and adding `|| true` guards.
3. **Demo unpacking**: `psychopy.demos.unpackDemos()` is not available in v2025.2.4; demos are copied directly from package directory.
4. **"Additional configuration needed" dialog**: Appears on restart, handled by `dismiss_psychopy_dialogs` in setup scripts.
5. **Verification result is pre-audit**: The verification_result.json was captured before audit fixes (Rounds 1-5). Post-fix testing requires a clean environment boot.
