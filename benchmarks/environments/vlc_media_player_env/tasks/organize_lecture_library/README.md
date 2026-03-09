# Organize Lecture Library Task

**Difficulty**: 🟡 Medium  
**Skills**: File management, organization, playlist creation  
**Duration**: 180 seconds  
**Steps**: ~60

## Objective

Organize scattered lecture recording files with cryptic auto-generated names into a structured course-based library with meaningful names and playlists.

## Scenario

Sarah, a college student, has 8 lecture recordings from online classes scattered in her Downloads folder with unhelpful auto-generated names like `GMT20241104-140052_Recording_1920x1080.mp4` and `zoom_recording_2345678.mp4`. She needs to organize them by course before finals.

## Task Description

The agent must:
1. Identify 8 lecture files in `/home/ga/Downloads/lectures_raw/`
2. Create course-specific folders under `/home/ga/Videos/Courses/`:
   - `Biology101/` (3 files)
   - `History202/` (3 files)
   - `Math150/` (2 files)
3. Move and rename files following pattern: `[Course]_Week[N]_[Topic].mp4`
4. Create a playlist for each course (`playlist.m3u`) with files in chronological order
5. Clean up the original `lectures_raw` folder

## Expected Results

- Organized folder structure created
- 8 files correctly distributed across 3 course folders
- Files renamed with meaningful names
- 3 playlists created (one per course)
- Source folder cleaned up

## Verification Criteria

1. ✅ **Folder Structure** (20%): All 3 course folders exist
2. ✅ **File Organization** (40%): Files in correct course folders
3. ✅ **Naming Convention** (20%): Files follow naming pattern
4. ✅ **Playlist Creation** (15%): Playlists exist and contain files
5. ✅ **Cleanup** (5%): Source folder empty

**Pass Threshold**: 80%

## Skills Tested

- File identification and classification
- Directory structure creation
- File moving/renaming operations
- VLC playlist creation and export
- Systematic organization workflow
- Understanding of file management

## Hints

- Files contain embedded metadata indicating course and topic
- Use VLC to preview files and check metadata (Tools → Media Information)
- Can also use `ffprobe` or file managers to inspect metadata
- VLC playlist feature: Media → Save Playlist to File
- File naming pattern: Course abbreviation_WeekNumber_TopicName.mp4

## Notes

This is a realistic workflow task combining file management with VLC playlist features. The challenge is identifying which files belong where and maintaining a consistent organization scheme.