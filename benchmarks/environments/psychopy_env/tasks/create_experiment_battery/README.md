# Create Experiment Battery

## Domain Context
Clinical neuropsychologists administer standardized cognitive assessment batteries combining multiple attention paradigms. Building a multi-task battery in PsychoPy requires managing complex flow with multiple loops, conditions files, instruction screens, and break periods — a task that tests deep Builder expertise.

## Goal
Combine three classic attention paradigms (Stroop, Flanker, Simon) into a single PsychoPy Builder experiment. Each task block needs its own instruction screen, trial loop referencing the correct conditions file, and break screens between blocks. The experiment also needs a welcome and debrief screen.

## Success Criteria
- Single .psyexp file with 8+ routines
- 3 separate loops, each referencing the correct conditions file (stroop_conditions.csv, flanker_conditions.csv, simon_conditions.csv)
- Welcome/intro screen at start
- 3 task-specific instruction routines
- 2+ break screens between task blocks
- Debrief/end screen
- Structural complexity: 100+ params, 200+ lines

## Verification Strategy
1. All 3 conditions file references detected in loops
2. Welcome routine present
3. 3+ instruction routines
4. 2+ break routines
5. Debrief routine present
6. Structural complexity gates

## Edge Cases
- Task blocks may be in different order (Stroop-Flanker-Simon is specified)
- Agent may create additional routines (e.g., fixation between trials)
- Break screens may have different names
