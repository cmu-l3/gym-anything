# times_table_memory_game

## Task Overview

**Environment**: Sugar Learning Platform (OLPC)
**Difficulty**: Hard
**Occupation**: 3rd-grade math teacher
**Application**: Sugar Memorize activity

## Domain Context

Elementary school teachers at OLPC schools use the Memorize activity to create custom memory card matching games for students. For multiplication tables, teachers create pairs where the front card shows an expression (e.g., "6x3") and the back card shows the answer (e.g., "18"). Students then play the game to practice the times table. Creating a full game with 8 pairs is a non-trivial task requiring familiarity with Memorize's card editing interface.

## Goal

Create a memory card matching game for the 6 times table (6x1 through 6x8) with 8 card pairs:

| Front (expression) | Back (answer) |
|-------------------|---------------|
| 6x1 | 6 |
| 6x2 | 12 |
| 6x3 | 18 |
| 6x4 | 24 |
| 6x5 | 30 |
| 6x6 | 36 |
| 6x7 | 42 |
| 6x8 | 48 |

Save the completed game to Sugar Journal with title **"6 Times Table Game"**.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Journal entry "6 Times Table Game" found | 30 |
| Game data file has content (>100 bytes) | 10 |
| 6× table expressions found in game data | 25 |
| Answer "6" (6×1) present in game data | 15 |
| Answer "48" (6×8) present — full range verified | 20 |
| **Total** | **100** |

**Pass threshold**: score ≥ 60 AND journal_found=True AND has_six_table=True

## Verification Strategy

1. `setup_task.sh` records timestamp, launches Memorize activity
2. `export_result.sh` scans `~/.sugar/default/datastore/*/metadata/title` for "6 Times Table Game"; if found, reads the `data` file from that journal entry and parses it for 6× expressions and answer values
3. `verifier.py` reads `/tmp/times_table_memory_game_result.json` and evaluates all criteria

## Memorize Game Data Format

Sugar Memorize stores games as XML files in the Sugar Journal datastore. The data file typically contains `<pair>` elements or similar XML structure. The export script searches for 6× expressions via regex (`6\s*[xX×*]\s*\d+`) and answer values.

## Edge Cases

- The agent must use the **Create/Edit tab** in Memorize to add card pairs, not just open an existing game
- If the agent saves the game with a slightly different title (e.g., "6x Times Table"), verification will fail since the title check is exact
- The data file size check (>100 bytes) ensures the game was actually populated, not just saved empty
- Partial completion (e.g., only 4 of 8 pairs) will still be detected if expressions and "6" answer are present
