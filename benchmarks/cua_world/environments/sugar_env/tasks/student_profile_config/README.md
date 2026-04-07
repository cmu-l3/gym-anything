# student_profile_config

## Task Overview

**Environment**: Sugar Learning Platform (OLPC)
**Difficulty**: Hard
**Occupation**: OLPC deployment coordinator
**Application**: Sugar System Settings (About Me) + Sugar Write

## Domain Context

OLPC deployment coordinators set up laptops for individual students. Each laptop must be personalized with the student's nickname (displayed in collaborative activities and the Journal) and XO icon color (used throughout Sugar to identify the student's work). A configuration log is created in Write to document the setup.

## Goal

Configure an OLPC laptop for student Alex Chen:

1. Set Sugar user **nickname to "AlexC"** — via the XO icon → profile settings → About Me
2. **Change the XO icon color** from the default red/blue (#FF2B34,#005FE4) to a warm orange/yellow preset
3. Create a **"Student Setup Log"** document in Sugar Write, saved to Sugar Journal as "Student Setup Log"

Initial state: nick="Learner", color="#FF2B34,#005FE4" (default red/blue)

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Nickname correctly set to "AlexC" | 40 |
| Nickname changed but wrong case | 20 (partial) |
| Nickname changed but any other value | 10 (partial) |
| XO icon color changed from default | 35 |
| Journal entry "Student Setup Log" found | 25 |
| **Total** | **100** |

**Pass threshold**: score >= 65 AND nick_correct=True AND color_changed=True

## Verification Strategy

1. `setup_task.sh` resets nick to "Learner" and color to "#FF2B34,#005FE4", records timestamp
2. `export_result.sh` reads `gsettings get org.sugarlabs.user nick` and `color`, scans Journal
3. `verifier.py` reads `/tmp/student_profile_config_result.json`

## gsettings Schema (org.sugarlabs.user)

Available keys: `nick`, `color`, `gender`, `birth-timestamp`, `default-nick`, `default-gender`, `group-label`, `resume-activity`

Note: `grade` key does NOT exist in this Sugar installation.

## Edge Cases

- Color verification is "changed from default" — any non-default color passes
- Nick is case-sensitive: "AlexC" passes, "alexc" gets partial credit
- Journal fallback: full journal scan if timestamp-filtered search finds nothing
