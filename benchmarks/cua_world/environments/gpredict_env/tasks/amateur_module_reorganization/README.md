# Task: Amateur Satellite Multi-Module Reorganization

## Domain Context

Amateur radio operators who work with satellites organize their tracking software by operational mode — linear transponder satellites require different operating techniques than FM voice satellites, so club station managers keep separate tracking windows for each mode. Linear transponder satellites (like AO-7, FO-29, FuncUBE-1/AO-73) use a single uplink/downlink frequency pair and require compensation for Doppler shift; FM satellites (like SO-50, AO-85, AO-95) are used like FM repeaters. Having separate modules lets operators instantly see which satellites of each type are visible.

This task reflects real work that an amateur radio club station manager would perform when reorganizing their tracking setup after a new batch of active satellites are identified and categorized.

## Persona

DX Amateur Radio Club Station Manager (licensed amateur radio operator, typically Extra class) — managing a multi-operator satellite station with both linear and FM uplink capabilities. The station supports both SSB/CW (linear transponder) and FM (voice repeater) satellite contacts.

## Scenario

The club's GPredict installation has two specialty modules that were started but left incomplete by a previous operator. The Linear module only has AO-7, and the FM_Voice module only has AO-27. You need to complete both modules and add a remote receive site that the club recently set up for diversity reception.

The key challenge: GPredict must be open and running. The agent must navigate into each module's satellite list and add multiple satellites to each, plus add a new ground station — all without being told which menus or dialogs to use.

## Task Description (for agent)

You are the station manager for an amateur radio satellite club. Two tracking modules have been started but are incomplete. You must complete them and add a remote receive station:

1. Complete the **Linear** module (used for linear-transponder satellites). It currently only has AO-7. Add:
   - **FO-29** (JAS-2, NORAD catalog number 24278)
   - **FuncUBE-1** (AO-73, NORAD catalog number 39444)
   AO-7 (NORAD 7530) is already in the module and should remain.

2. Complete the **FM_Voice** module (used for FM repeater satellites). It currently only has AO-27. Add:
   - **SO-50** (SaudiSat 1C, NORAD catalog number 27607)
   - **AO-85** (Fox-1A, NORAD catalog number 40967)
   - **AO-95** (Fox-1Cliff, NORAD catalog number 43770)
   AO-27 (NORAD 22825) is already in the module and should remain.

3. Add a **remote receive site** ground station named **Remote_RX** at: Latitude = 40.7484°N, Longitude = 74.0060°W (Secaucus, NJ area), Altitude = 10 meters.

Login: username `ga`, password `password123`. GPredict is already open.

## Success Criteria

- Linear.mod contains NORAD IDs: 7530 (AO-7), 24278 (FO-29), 39444 (AO-73/FuncUBE-1)
- FM_Voice.mod contains NORAD IDs: 22825 (AO-27), 27607 (SO-50), 40967 (AO-85), 43770 (AO-95)
- Remote_RX.qth exists with LAT≈40.75, LON≈-74.01, ALT=10m
- Both modules still exist (not deleted or merged)

## Verification Strategy

Scoring (100 points, pass ≥ 70):
- Linear module has all 3 satellites (AO-7, FO-29, AO-73): 30 pts (10 per sat, partial credit)
- FM_Voice module has all 4 satellites (AO-27, SO-50, AO-85, AO-95): 40 pts (10 per sat)
- Remote_RX ground station with correct coordinates: 20 pts
- Both modules exist: 10 pts

## Key Data (from CelesTrak amateur.txt TLE data)

### Linear Transponder Satellites
| Satellite | NORAD ID | Transponder type | Status |
|-----------|----------|-----------------|--------|
| AO-7 (OSCAR 7) | 7530 | Linear CW/SSB | Active (partial) |
| FO-29 (JAS-2) | 24278 | Linear SSB | Active |
| FuncUBE-1 (AO-73) | 39444 | Linear CW/SSB | Active |

### FM Repeater Satellites
| Satellite | NORAD ID | Mode | Status |
|-----------|----------|------|--------|
| AO-27 (EYESAT A) | 22825 | FM voice | Active (limited) |
| SO-50 (SaudiSat 1C) | 27607 | FM voice repeater | Active |
| AO-85 (Fox-1A) | 40967 | FM + telemetry | Active |
| AO-95 (Fox-1Cliff) | 43770 | FM + telemetry | Active |

## GPredict File Format Notes
- Module files: `~/.config/Gpredict/modules/*.mod`
- SATELLITES field: semicolon-delimited NORAD catalog numbers (may have leading zeros stripped)
- Note: NORAD ID 7530 for AO-7 may appear as 7530 without leading zero
- Ground station files: `~/.config/Gpredict/*.qth`
