# Debug Broken Experiment

## Domain Context
Psychology teachers and researchers frequently inherit experiment files from colleagues who have left the lab. These files often contain subtle bugs that prevent experiments from running correctly. Debugging requires understanding PsychoPy's component system, flow control, conditions file references, and Builder XML structure.

## Goal
A Stroop experiment file (`broken_stroop.psyexp`) has 5 bugs that prevent it from working. The agent must discover each bug, understand why it's wrong, and fix all issues. The corrected experiment must be saved as a new file (`stroop_fixed.psyexp`).

## Success Criteria
The fixed experiment must:
- Reference the correct conditions file (`stroop_conditions.csv`)
- Use `$letterColor` for dynamic text color (not the British spelling `$colour`)
- Have valid keyboard response keys configured
- Run a positive number of trial repetitions (nReps > 0)
- Present instructions before the trial block in the flow

## Verification Strategy
Each bug fix is verified independently via XML parsing:
1. Color variable reference check
2. AllowedKeys non-empty check
3. Flow ordering check (instructions before trial)
4. nReps > 0 check
5. Conditions filename check

## Edge Cases
- Agent may rebuild the experiment from scratch rather than fixing in-place (acceptable if all criteria met)
- Agent may use Coder view to edit XML directly (acceptable)
- Different nReps values are fine as long as > 0
