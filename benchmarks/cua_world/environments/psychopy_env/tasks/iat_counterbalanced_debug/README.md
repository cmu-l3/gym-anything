# IAT Counterbalanced Debug

## Domain Context

The Implicit Association Test (IAT; Greenwald, McGhee & Schwartz, 1998) is the most widely used measure of implicit social attitudes in psychology research. Clinical neuropsychologists, social cognition researchers, and psychology faculty regularly build and maintain IAT experiments. A well-formed IAT requires precise block ordering (compatible block 3 must precede incompatible block 4), correct variable referencing, and valid data-saving configuration. Subtle bugs introduced during file transfer or editing are common and produce invalid D-scores.

## Goal

A broken IAT experiment file (`iat_broken.psyexp`) has 5 bugs that cause incorrect data collection and runtime errors. The agent must discover every bug independently, fix all of them, add a required debriefing routine, and save the corrected experiment as `iat_fixed.psyexp`.

## Success Criteria

The fixed experiment (`iat_fixed.psyexp`) must:
- Have Block 3 (compatible) appearing before Block 4 (incompatible) in the Flow
- Have a practice block loop with `nReps > 0`
- Have the code component use `==` (comparison) not `=` (assignment) in its if-statement
- Reference `$stim_color` (not `$category_color`) in the label text color field
- Use `$participant` (with dollar sign) in the Settings data filename
- Contain a `debrief` routine at the end of the Flow

## Verification Strategy

Each of the 6 criteria (5 bug fixes + debrief addition) is verified independently via XML parsing of the saved `.psyexp` file. The verifier also independently re-parses the file directly (not relying solely on the export JSON) for adversarial robustness. Scoring: 100 pts total, pass threshold 60 pts.

1. Flow block order: block3_loop appears before block4_loop (20 pts)
2. Practice nReps > 0 (15 pts)
3. Code `==` in Each Frame code (15 pts)
4. Color reference is `$stim_color` (15 pts)
5. Filename uses `$participant` (10 pts)
6. Debrief routine exists in Flow (15 pts)
7. File validity gate (10 pts)

## Schema Reference

- Input: `/home/ga/PsychoPyExperiments/iat_broken.psyexp` (XML, PsychoPy2experiment format)
- Conditions: `/home/ga/PsychoPyExperiments/conditions/iat_*.csv`
- Output: `/home/ga/PsychoPyExperiments/iat_fixed.psyexp`

## Edge Cases

- Agent may save in-place (overwriting broken file) or as new file — both acceptable if output path is `iat_fixed.psyexp`
- Agent may rebuild from scratch rather than editing — acceptable if all 6 criteria met
- Agent may use Coder view (direct XML edit) or Builder GUI — both acceptable
