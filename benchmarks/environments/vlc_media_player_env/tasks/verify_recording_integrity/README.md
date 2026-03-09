# Verify Recording Integrity Task

**Difficulty**: 🟡 Medium  
**Skills**: Media analysis, codec inspection, audio track verification, technical reporting  
**Duration**: 180 seconds  
**Steps**: ~35

## Objective

Verify that a screen recording captured all intended elements correctly before investing time in editing. Content creators frequently face the frustrating scenario of discovering recording issues only after hours of work—this task simulates the critical verification workflow.

## Task Description

**Scenario**: A content creator just finished recording a gaming tutorial. Before spending hours editing, they need to quickly verify: (1) audio was captured from both game and microphone, (2) video specs match upload requirements (1920x1080, ≥30fps), (3) no frame drops or corruption, and (4) audio levels are balanced.

The agent must:
1. Open the recording file `/home/ga/Videos/gameplay_recording.mkv` in VLC
2. Check codec information (Tools → Codec Information or Ctrl+J for Media Information)
3. Verify video resolution is 1920x1080
4. Verify framerate is ≥30fps
5. Verify 2 audio tracks are present
6. Play through the video and check audio from both tracks
7. Identify that Track 2 (microphone) has very low/no volume
8. Generate a verification report indicating the low volume issue
9. Save report to `/home/ga/Videos/recording_verification_report.txt`

## Expected Results

**Recording file properties**:
- Resolution: 1920x1080
- Framerate: 30fps
- Codec: H.264
- Audio tracks: 2 (Game audio + Microphone)
- **Planted issue**: Track 2 (Microphone) has very low volume (~5% = -26dB)

**Verification report should contain**: