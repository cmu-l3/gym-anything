# Screaming Frog SEO Spider Environment - Evidence Documentation

**Last Updated**: 2026-02-03

## Environment Details
- **Environment ID**: frog_seo_spider_env@0.1
- **Application**: Screaming Frog SEO Spider 23.2
- **Base Image**: ubuntu-gnome-systemd_highres
- **Tasks**: crawl_website, find_broken_links, export_crawl_report
- **Target URL**: https://crawler-test.com/ (REAL public SEO test website)

## IMPORTANT: Task Start State Verification

### What the Setup Script Does

The `setup_task.sh` script performs the following steps before the agent begins:

1. **Records task start time** to `/tmp/task_start_time` for file modification tracking
2. **Kills any existing Screaming Frog processes** to ensure clean state
3. **CLEARS PREVIOUS CRAWL DATA** to ensure fresh start:
   - Removes `~/.ScreamingFrogSEOSpider/crawl_cache/*`
   - Removes `~/.ScreamingFrogSEOSpider/tmp/*`
   - Removes `~/.ScreamingFrogSEOSpider/*.seospider`
   - Removes `~/.ScreamingFrogSEOSpider/recent_crawls.xml`
   - Clears any previous export files from `/tmp/`
4. **Records initial export file count** to detect new files created during task
5. **Launches Screaming Frog** via launch script
6. **Waits for process** (30 second timeout)
7. **Waits for window** (45 second timeout)
8. **Handles EULA dialog** automatically if it appears (first-run only)
9. **Waits for UI readiness** via `wait_for_sf_ready(60)`:
   - Checks process is running
   - Checks window exists and doesn't contain "loading/initializ/starting"
   - Takes test screenshot and verifies size (main UI > 400KB, splash < 400KB)
   - Verifies window can be activated
   - Waits minimum 15 seconds for stability
   - Saves ready-state screenshot to `/tmp/sf_ready_state.png`
10. **Additional 5-second stabilization**
11. **Focuses the main window** for immediate interaction

### How to Verify Task Start State

After setup completes, check:
1. `/tmp/sf_ready_state.png` - Screenshot captured when UI was verified ready
2. `/tmp/setup_timing.log` - Timestamps of wait function completion
3. Window title should show "Screaming Frog SEO Spider" without "loading"

### Known Limitation

The screenshots in this folder (e.g., `setup_01_loading_splash.png`) show intermediate states during the setup process, NOT the actual task start state. These are provided for documentation of the setup flow but should not be confused with what the agent sees.

The actual task start state is captured in `/tmp/sf_ready_state.png` during each run.

## Screenshot Organization

### Setup Phase (intermediate states - NOT task start)
- `setup_01_loading_splash.png` - Initial loading/splash screen
- `setup_02_eula_dialog.png` - EULA dialog (auto-accepted)
- `setup_03_loading_after_eula.png` - Loading after EULA

### Task Phase (what agent sees after setup)
- `task_01_ready_state.png` - Application ready with URL bar visible
- `task_02_url_entered.png` - URL entered in address bar
- `task_03_crawl_in_progress.png` - Crawl running
- `task_04_crawl_complete.png` - Crawl completed
- `task_05_final_state.png` - Final state

## Data Quality

This environment uses **real website data**:
- **crawl_website**: https://crawler-test.com/
- **find_broken_links**: https://crawler-test.com/links/broken_links
- **export_crawl_report**: https://crawler-test.com/

crawler-test.com is a real public website specifically designed for SEO crawler testing.

## Verifier Requirements

### crawl_website verifier
- SF must be running
- Window title must contain "crawler-test" (strict domain check)
- url_count > 0 from exports OR VLM confirms crawl visible
- **Pass**: SF running AND correct URL AND (url_count > 0 OR VLM >= 15)

### find_broken_links verifier
- SF must be running
- Window title must contain "crawler-test"
- 404 errors must be found in exports created AFTER task started
- Export must contain both "404" AND "crawler-test" (prevents false positives)
- **Pass**: SF running AND correct URL AND (response codes checked OR broken link found)

### export_crawl_report verifier
- New CSV file must be created after task started
- CSV must contain "crawler-test" URLs (domain verified)
- At least 5 rows of data
- **Pass**: File created AND domain_verified AND csv_rows >= 5

## Anti-Cheating Measures

1. **Domain verification**: All verifiers require "crawler-test" in window title or export content
2. **File timestamp checking**: Only files modified AFTER task_start_time are considered
3. **No file-name pattern assumptions**: find_broken_links no longer sets response_codes_checked based on filename alone
4. **Strict VLM verification**: Visual confirmation requires specific indicators

## Fixes Applied

### 2026-02-03 Updates

1. **Fixed find_broken_links false positive**: Removed file-pattern-based `RESPONSE_CODES_CHECKED` detection. Now only set true if export contains actual response code data for crawler-test.com.

2. **Enhanced UI readiness verification**: `wait_for_sf_ready()` now:
   - Takes test screenshot and verifies file size (splash screen vs main UI)
   - Attempts window activation to verify UI responsiveness
   - Requires minimum 15 seconds wait
   - Saves ready-state screenshot for verification

3. **Clarified task descriptions**: Added explicit STEPS and SUCCESS CRITERIA to all task descriptions.

4. **Fixed mtime comparison bug**: export_crawl_report now correctly uses task_start_time file instead of mtime of listing file.

5. **Added task_start_time recording**: All setup scripts now record task start time for accurate file tracking.

6. **Fixed VLM error handling**: Added type safety checks to handle cases where VLM returns unexpected types (string instead of dict). Now validates `vlm_result` is a dict and `response` is a string before processing.

7. **Added export content verification**: crawl_website verifier now additionally checks that exported CSV contains "crawler-test" URLs, not just any URL count.

8. **Clear pre-existing crawl data**: All setup scripts now clear Screaming Frog's cache, temp files, seospider files, and recent_crawls.xml to ensure a completely fresh start state. This prevents false positives from checkpointed/cached crawl results.

## Log Files
- `pre_start_log.txt` - Installation log
- `post_start_log.txt` - Setup log
- `pre_task_log.txt` - Task setup log
- `export_result_output.txt` - Export script output
