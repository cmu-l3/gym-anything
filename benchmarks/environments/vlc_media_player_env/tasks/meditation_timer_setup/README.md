# Meditation Timer Setup Task

**Difficulty**: 🟡 Medium  
**Skills**: Timer configuration, command-line arguments, automation  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Configure VLC Media Player to automatically quit after exactly 30 minutes when playing a meditation video, enabling hands-free timed playback sessions.

## Real-World Context

A mindfulness practitioner wants to play a nature soundscape video during their evening meditation session. They need VLC to automatically stop after exactly 30 minutes (their session duration) without manual intervention, allowing them to focus entirely on their practice without technological distraction.

## Task Description

The agent must:
1. VLC launches or is available to launch
2. Configure VLC to auto-quit after 30 minutes (1800 seconds)
3. Use one of these methods:
   - Launch VLC with `--run-time=1800` command-line argument
   - Configure timer via VLC preferences/settings
   - Use `--stop-time` parameter for playback time limit

## Expected Results

- VLC configured to automatically quit after 30 minutes
- Configuration verifiable in bash history or VLC config
- Timer functionality works correctly (verified with short test)

## Verification Criteria

1. ✅ **Video File Exists**: Meditation video file is present
2. ✅ **Timer Configured**: Found --run-time in commands or config
3. ✅ **Practical Test Passes**: Short-duration test confirms auto-quit works

**Pass Threshold**: 70%

## Skills Tested

- VLC command-line argument usage
- Understanding of time units (minutes to seconds)
- Configuration persistence
- Process monitoring
- Automation setup

## Methods to Configure Timer

### Method 1: Command-line (Recommended)