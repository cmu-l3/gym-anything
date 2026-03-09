# Task: debug_runtime_crash

## Overview
The NotepadApp project has been reported to crash at runtime. The project compiles successfully, but when the app launches it crashes with multiple runtime errors. The agent must diagnose the crashes using Android Studio's debugging tools, logcat output, or code inspection, identify the root causes, and fix them.

## Domain Context
Debugging runtime crashes is one of the most common tasks for Android developers and QA testers. Unlike compilation errors that the IDE highlights, runtime crashes require understanding control flow, reading stack traces, and reasoning about program state.

## Goal
Fix all runtime crashes in the NotepadApp so that it launches without errors and the core functionality (loading notes, validating, formatting) works correctly. The project already compiles -- the bugs are logical/runtime errors.

## Success Criteria
- NotepadActivity.kt: formatter and validator are properly initialized before use
- NoteFormatter.kt: formatPreview handles short content without crashing
- NoteValidator.kt: isNoteComplete does not recurse infinitely
- Note.kt: charCount returns correct count without crashing
- Project still compiles after fixes
- All 4 runtime bugs are fixed

## Verification Strategy
Each bug fix is verified independently by checking the source code for the corrected pattern. Build success is also verified.
