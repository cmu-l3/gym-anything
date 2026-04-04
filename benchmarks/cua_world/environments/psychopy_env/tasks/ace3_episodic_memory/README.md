# ACE-III Episodic Memory

## Domain Context

The Addenbrooke's Cognitive Examination III (ACE-III; Mioshi et al., 2006) is the most widely used brief cognitive battery in memory clinics worldwide. Its episodic memory subscale uses a three-word registration–interference–recall–recognition design, directly analogous to the classic Rey Auditory Verbal Learning Test. The standard ACE-III target words (Lemon, Key, Ball) are selected for matched frequency and imageability. Clinical neuropsychologists are increasingly digitalizing paper-based assessments for tablet administration — a task requiring careful implementation of timing, response capture, and automated scoring.

## Goal

Build a complete ACE-III episodic memory experiment from scratch using PsychoPy Builder. The experiment must implement the full registration-interference-recall-recognition-scoring pipeline. Create both the `.psyexp` experiment file and the `ace3_recognition.csv` conditions file with exactly 12 items (3 targets + 9 foils) with correct response coding.

## Success Criteria

The experiment (`ace3_episodic_memory.psyexp`) must:
- Present the three target words (Lemon, Key, Ball) in a learning phase
- Include an interference task after learning
- Have a free recall phase with keyboard input
- Have a recognition phase driven by the conditions file loop
- Include a code component that tallies recall and recognition scores
- End with a scoring/summary screen

The conditions file (`ace3_recognition.csv`) must:
- Contain exactly 12 rows (3 targets + 9 foils)
- Have `word`, `is_target` (1/0), and `correct_response` ('y'/'n') columns
- Include Lemon, Key, and Ball as the target words (is_target=1, correct_response='y')

## Verification Strategy

8 independent criteria. Verifier independently re-parses both the conditions CSV and the psyexp XML. Scoring: 100 pts total, pass threshold 60 pts.

1. File valid and newly created (10 pts)
2. Conditions file structure: 12 rows, correct columns (10 pts)
3. Target/foil split: exactly 3 targets + 9 foils (15 pts)
4. Response coding: 3 'y' + 9 'n' correct_response values (10 pts)
5. Target words Lemon, Key, Ball present (15 pts)
6. Task structure: learning + interference + recall + recognition (20 pts)
7. Code component with scoring logic (10 pts)
8. Final scoring/summary screen (10 pts)

## Schema Reference

- Output experiment: `/home/ga/PsychoPyExperiments/ace3_episodic_memory.psyexp`
- Output conditions: `/home/ga/PsychoPyExperiments/conditions/ace3_recognition.csv`
- Standard ACE-III foil words: Apple, Chair, Table, Window, Pen, Doctor, House, River, Clock

## Edge Cases

- Interference task name is flexible; verifier detects by keywords: `interfere`, `distract`, `count`, `filler`, `delay`
- Free recall detected by: `recall`, `free`, `retrieve`, `remember`
- Recognition phase detected by: `recogni`, `identify`, `test`, `probe`
- Code component scoring accepts any variable names containing `recall`, `score`, `hit`, `recog`
- Target words may appear in text components OR in the conditions file (either location satisfies the criterion)
