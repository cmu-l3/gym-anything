# Verify Video Metadata Task

**Difficulty**: 🟡 Medium  
**Skills**: Metadata extraction, digital forensics, documentation  
**Duration**: 180 seconds  
**Steps**: ~40

## Objective

Extract comprehensive metadata from a video file using VLC's Media Information tools to verify authenticity claims. This simulates real-world journalism and forensics workflows.

## Task Description

The agent must:
1. Open a video file claimed to be "shot yesterday on iPhone 14 Pro"
2. Access VLC's Media Information dialog (Tools → Media Information)
3. Extract technical specifications (codec, resolution, framerate, bitrate)
4. Document all available metadata (creation date, encoder, camera info)
5. Create a verification report documenting findings

## Expected Results

- Verification report created at `/home/ga/Documents/video_verification_report.txt`
- Report contains accurate metadata extracted from the video
- Key fields documented: codec, resolution, duration, dates, encoder

## Verification Criteria

1. ✅ **Report Exists**: Verification report file found and has content
2. ✅ **Codec Accurate**: Video codec correctly identified
3. ✅ **Resolution Accurate**: Video dimensions correctly documented
4. ✅ **Duration Accurate**: Video length correctly recorded
5. ✅ **Comprehensive**: Multiple metadata fields extracted (6+ fields)

**Pass Threshold**: 70%

## Skills Tested

- Menu navigation (Tools → Media Information)
- Tab navigation within dialog
- Technical information comprehension
- Text file creation and documentation
- Systematic metadata extraction
- Forensic verification methodology

## Controls

- **Menu**: Tools → Media Information (or Ctrl+I)
- **Tabs**: General Information, Codec Information, Metadata, Statistics
- **Text Editor**: Create report file

## Real-World Context

Journalists, fact-checkers, and digital forensics analysts use metadata extraction to:
- Verify video authenticity before publication
- Detect manipulated or misrepresented content
- Establish chain of custody for legal proceedings
- Combat misinformation and deepfakes

## Notes

The source claims the video was "shot yesterday on iPhone 14 Pro at downtown protest." The agent's job is to extract actual metadata to verify or contradict this claim.