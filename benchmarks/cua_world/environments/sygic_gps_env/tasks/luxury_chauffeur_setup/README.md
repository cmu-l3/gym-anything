# Task: luxury_chauffeur_setup

## Summary

Configure Sygic GPS Navigation to the exact standards of Prestige Executive Transport, a premium chauffeured car service. The fleet director must enable arrive-in-direction, set night display, allow toll roads, enable permanent compass, and set DMS GPS coordinates format.

## Occupation Context

**Primary occupation**: Shuttle Drivers and Chauffeurs
**GDP relevance**: $38M economic output; premium chauffeured transport is a high-standard GPS use case where precision and professionalism depend on correct navigation settings

## Scenario

Prestige Executive Transport has five mandatory GPS settings for evening shift:

1. **Arrive-in-direction**: White-glove service — clients must not step around the car or cross traffic.
2. **Night theme**: Permanent dark display — bright screen reflects off windshield in dim conditions.
3. **Tolls allowed**: Pre-negotiated toll access; toll routes should never be excluded.
4. **Compass always on**: Navigation in hotel loops, parking garages, and private estates requires bearing.
5. **DMS GPS format**: Concierge team uses degrees-minutes-seconds for vehicle staging coordination with hotel staff.

## Difficulty: very_hard

No vehicle profile creation required — the task is entirely about settings configuration. Description gives only the professional/operational rationale, no Sygic menu paths or setting names.

## Verification

Scoring (100 pts, pass=65):
| Criterion | Points |
|-----------|--------|
| Arrive-in-direction enabled | 25 |
| App theme = Night | 25 |
| Toll roads NOT avoided (allowed) | 20 |
| Compass always on enabled | 20 |
| GPS format = DMS | 10 |

## Gate Check

The verifier rejects the do-nothing case: if none of the 5 settings changed from their baseline values, score=0.

## Setup Starting State

| Setting | Start Value | Target Value |
|---------|-------------|--------------|
| Arrive-in-direction | false | true |
| App theme | Auto (0) | Night (2) |
| Avoid toll roads | true | false |
| Compass always on | false | true |
| GPS coordinate format | Degrees (0) | DMS (1) |
