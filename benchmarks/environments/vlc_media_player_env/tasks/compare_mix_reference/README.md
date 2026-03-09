# Compare Mix Reference Task

**Difficulty**: 🟡 Medium  
**Skills**: Playlist creation, audio workflow understanding, file management  
**Duration**: 90 seconds  
**Steps**: ~40

## Objective

Create a playlist for A/B comparison between a music mix and a professional reference track, enabling efficient switching between the two for quality checking.

## Scenario

Kira is a bedroom music producer who just finished mixing her first single. She needs to compare her mix against a professional reference track to ensure her bass levels, vocal clarity, and overall loudness match industry standards. Instead of juggling two VLC windows, she wants a single playlist where she can quickly switch between tracks to hear differences.

## Task Description

The agent must:
1. Open VLC's playlist functionality
2. Create a playlist containing two specific audio files in order:
   - `/home/ga/Music/my_mix.mp3` (Kira's mix - track 1)
   - `/home/ga/Music/reference_track.mp3` (professional reference - track 2)
3. Save the playlist as XSPF format to:
   - `/home/ga/Music/playlists/mix_comparison.xspf`

## Expected Results

- Playlist file created at specified location
- Playlist contains exactly 2 tracks in correct order
- Both tracks are accessible and playable
- Playlist is loadable in VLC

## Verification Criteria

1. ✅ **Playlist Exists**: Playlist file found and parseable
2. ✅ **Correct Track Count**: Playlist has exactly 2 items
3. ✅ **Correct Track Order**: First track is mix, second is reference
4. ✅ **Files Accessible**: Both audio files exist and are valid

**Pass Threshold**: 75%

## Skills Tested

- Playlist window navigation (View → Playlist)
- Adding multiple files to playlist
- Understanding playlist ordering
- Save dialog interaction
- File browser usage
- Understanding of audio production workflows

## Controls

- **Ctrl+L**: Open playlist view
- **Media → Open File**: Add files to playlist
- **Playlist → Save Playlist to File**: Save as XSPF
- **Drag and drop**: Add files by dragging into playlist
- **Next/Previous**: Switch between tracks (N/P keys)

## Notes

- XSPF (XML Shareable Playlist Format) is VLC's native playlist format
- The order matters: mix first, reference second (standard A/B comparison workflow)
- This workflow is used by professional audio engineers for quality checking