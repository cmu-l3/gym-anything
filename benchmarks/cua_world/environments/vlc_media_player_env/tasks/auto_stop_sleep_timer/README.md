# Auto Stop Sleep Timer Task

**Difficulty**: 🟡 Medium  
**Skills**: Command-line parameters, automation, scheduling  
**Duration**: 75 seconds  
**Steps**: ~30

## Objective

Configure VLC to automatically stop playback and quit after 45 seconds, simulating a sleep timer functionality for battery saving and scheduled shutoff.

## Task Description

The agent must:
1. Launch VLC with a looping video
2. Configure automatic termination after 45 seconds using:
   - `--run-time=45` command-line flag (recommended), OR
   - `timeout` command to kill after duration, OR  
   - VLC runtime configuration

## Expected Results

- VLC launches and begins playing video
- VLC automatically terminates after 45 seconds (±10s tolerance)
- Clean process exit (not crashed)
- No zombie processes remain

## Verification Criteria

1. ✅ **VLC Launched**: VLC process started successfully
2. ✅ **Runtime Configuration**: Correct runtime parameter detected
3. ✅ **Auto Termination**: VLC terminated within 45±10 seconds
4. ✅ **Clean Exit**: No zombie processes or crashes

**Pass Threshold**: 75%

## Skills Tested

- VLC command-line usage (`--run-time` flag)
- Process automation and scheduling
- Understanding of runtime parameters
- Alternative: System commands (`timeout`)

## Real-World Context

Users who play media as sleep aid need VLC to auto-stop to preserve battery, prevent screen burn-in, and avoid being woken by continuing playback. This task simulates configuring a 45-second timer (scaled down from 30-minute real-world use case).

## Controls

### Method 1: VLC Command-Line (Recommended)