# Navigate DVD Bonus Features Task

**Difficulty**: 🟡 Medium  
**Skills**: DVD navigation, menu interaction, ISO handling  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Load a DVD ISO file, navigate through its DVD menu system to access bonus features (specifically, a behind-the-scenes featurette from Title 2), and verify correct playback.

## Task Description

The agent must:
1. Open VLC Media Player
2. Load the DVD ISO file (`/home/ga/Videos/sample_movie.iso`)
3. Navigate DVD menu structure to access bonus features
4. Play Title 2 (behind-the-scenes featurette, not the main feature)
5. Verify correct title is playing

**Real-World Context**: 
A user has archived their DVD collection and wants to access bonus content from an ISO. The DVD menu is in French (simulating real-world complexity of international media), and they need to navigate to the *Suppléments* (bonus features) section.

## Expected Results

- VLC playing Title 2 (bonus features) from ISO
- DVD/disc mode active (not simple file playback)
- Playback progressing beyond 10 seconds
- No critical errors in VLC logs

## Verification Criteria

1. ✅ **VLC Running with ISO** (20%): VLC process active with ISO loaded
2. ✅ **DVD Mode Active** (20%): Disc navigation mode confirmed
3. ✅ **Correct Title Playing** (30%): Title 2 (not Title 1) is active
4. ✅ **Playback Progress** (20%): Playback >10 seconds into content
5. ✅ **No Critical Errors** (10%): Clean logs, no navigation failures

**Pass Threshold**: 70% (need at least 4/5 criteria)

## Skills Tested

- Media → Open Disc menu navigation
- DVD menu interaction (arrow keys, Enter)
- Understanding DVD structure (titles vs. chapters)
- ISO file handling
- Distinguishing DVD mode from file playback

## Controls

- **Media → Open Disc**: Load DVD ISO
- **Arrow keys + Enter**: Navigate DVD menus
- **Title menu**: Switch between titles
- **T key**: Cycle through titles (shortcut)