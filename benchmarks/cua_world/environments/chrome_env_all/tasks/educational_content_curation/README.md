# Educational Content Curation (`educational_content_curation@1`)

## Overview

**Domain**: Instructional Coordinator -- Configuring Shared Classroom Browser

An instructional coordinator must configure a shared classroom Chrome browser according to the school district's Digital Learning Environment specification. The browser currently has 35 unorganized bookmarks -- a mix of educational resources and social media/entertainment sites that students should not access freely. The coordinator must organize bookmarks by academic subject, set up educational search shortcuts, configure content restrictions, set startup pages, and establish download and authentication policies appropriate for a shared student device.

## Initial State

- **Bookmarks**: 35 flat bookmarks on the bookmark bar:
  - 9 Mathematics and Science sites (Khan Academy, Khan Academy Math, Desmos, GeoGebra, PhET, Wolfram Alpha, NASA Education, National Geographic Education, Science Buddies, CK-12)
  - 7 Language Arts and Humanities sites (CommonLit, Newsela, ReadWorks, Storybird, PBS LearningMedia, EDSITEment, Facing History)
  - 3 Social Studies and Civics sites (iCivics, Library of Congress, Smithsonian Learning)
  - 10 Classroom Tools (Google Classroom, Quizlet, Kahoot, Edpuzzle, Padlet, Canva Education, Flipgrid, Nearpod, Seesaw, ClassDojo)
  - 5 restricted sites (Reddit, TikTok, Twitter/X, Twitch, Discord)
- **Preferences**: Non-compliant defaults -- homepage `google.com`, no custom search engines, download path `/home/ga/Downloads`, password saving and autofill enabled, third-party cookies allowed, notifications allowed, Safe Browsing in standard mode.
- **Spec file**: `~/Desktop/digital_learning_spec.txt` -- Unified School District #42 Digital Learning Environment Specification DLE-2026-003.
- **Download directory**: `/home/ga/Documents/Student_Resources` pre-created.

## Goal

All specifications from `~/Desktop/digital_learning_spec.txt` are implemented:

- Bookmarks organized into 5 subject-area folders:
  - `Mathematics & Science` -- Khan Academy, Desmos, GeoGebra, PhET, Wolfram Alpha, NASA, Nat Geo, Science Buddies, CK-12
  - `Language Arts & Humanities` -- CommonLit, Newsela, ReadWorks, Storybird, PBS LearningMedia, EDSITEment, Facing History
  - `Social Studies & Civics` -- iCivics, Library of Congress, Smithsonian Learning
  - `Classroom Tools` -- Google Classroom, Quizlet, Kahoot, Edpuzzle, Padlet, Canva Education, Flipgrid, Nearpod, Seesaw, ClassDojo
  - `Restricted - Teacher Only` -- Reddit, TikTok, Twitter/X, Twitch, Discord
- 3 educational search shortcuts: `learn` (Khan Academy), `wiki` (Wikipedia), `pbs` (PBS LearningMedia).
- Homepage: `https://classroom.google.com`.
- Startup pages: `classroom.google.com` and `khanacademy.org`.
- Third-party cookies blocked, notifications blocked by default, Safe Browsing in Enhanced Protection mode.
- Download directory: `/home/ga/Documents/Student_Resources`, prompt enabled.
- Password saving, address autofill, and payment methods all disabled.

## Success Criteria

The task is verified against 7 criteria totaling 100 points. Pass threshold: **70/100**.

## Scoring Breakdown

| # | Criterion | Points | Details |
|---|-----------|--------|---------|
| 1 | Subject-area bookmark folders exist | 20 | >= 4 of 5 folders found on bookmark bar = 20 pts; otherwise 4 pts per folder |
| 2 | Bookmarks correctly categorized | 10 | >= 6 Math/Science domains in Math/Science folder (5 pts); >= 6 Classroom Tools domains in Classroom Tools folder (5 pts) |
| 3 | Restricted folder with blocked sites | 10 | >= 3 of 5 restricted domains (reddit.com, tiktok.com, x.com, twitch.tv, discord.com) in restricted folder |
| 4 | Educational search shortcuts | 15 | 5 pts per search engine keyword found (`learn`, `wiki`, `pbs`) |
| 5 | Homepage and startup pages | 15 | Homepage contains `classroom.google.com` (5 pts); startup includes `classroom.google.com` (5 pts); startup includes `khanacademy.org` (5 pts) |
| 6 | Content safety settings | 15 | Third-party cookies blocked via `cookie_controls_mode=1` (5 pts); notifications blocked via `default_content_setting_values.notifications=2` (5 pts); Safe Browsing enhanced (5 pts) |
| 7 | Download and authentication settings | 15 | Download path contains `Student_Resources` (5 pts); prompt_for_download = true (3 pts); password saving disabled (4 pts); autofill disabled (3 pts) |

## Verification Strategy

1. **Bookmark folders**: Bookmark bar children are searched for folders using flexible keyword matching. For example, the "math_science" pattern requires both "math" and "science" to appear in the folder name (case-insensitive). Similarly, "restricted" requires both "restricted" and "teacher".
2. **Bookmark categorization**: Within the Math/Science folder, direct children URLs are matched against 9 expected domains (khanacademy.org, desmos.com, geogebra.org, etc.). Within Classroom Tools, 10 domains are checked. Each folder needs >= 6 matches for full credit.
3. **Restricted folder**: The restricted/teacher folder is located and its URLs checked against 5 blocked domains. Only direct children are counted (not recursive).
4. **Search shortcuts**: Preferences JSON is scanned across `default_search_provider_data.template_url_data`, `search_provider_overrides`, `custom_search_engines`, `keywords`, and `omnibox.recent_search_engines`. Keywords `learn`, `wiki`, `pbs` are matched.
5. **Homepage/startup**: `homepage` field checked for `classroom.google.com`. `session.startup_urls` checked for both `classroom.google.com` and `khanacademy.org`.
6. **Content safety**: `profile.cookie_controls_mode` checked for 1; `profile.default_content_setting_values.notifications` checked for 2; `safebrowsing.enhanced` checked for true.
7. **Download/auth**: `download.default_directory` checked for `student_resources` (case-insensitive); `download.prompt_for_download` for true; `credentials_enable_service` or `profile.password_manager_enabled` for false; `autofill.profile_enabled` or `autofill.credit_card_enabled` for false.

## Strategy Enumeration (Contamination Injection Safety)

Setup seeds both educational and restricted bookmarks into the same flat structure. The agent must selectively categorize:

| Strategy | Folders (20) | Categorization (10) | Restricted (10) | Search (15) | Homepage (15) | Safety (15) | Download/Auth (15) | Total |
|----------|-------------|---------------------|-----------------|-------------|--------------|-------------|-------------------|-------|
| **Do nothing** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | **0** |
| **Create folders but don't move BMs** | 20 | 0 | 0 | 0 | 0 | 0 | 0 | **20** |
| **Move all BMs into one folder** | 4 | 0 | 0 | 0 | 0 | 0 | 0 | **4** |
| **Only configure settings (no BMs)** | 0 | 0 | 0 | 15 | 15 | 15 | 15 | **60** |
| **Correct behavior** | 20 | 10 | 10 | 15 | 15 | 15 | 15 | **100** |

The "only configure settings" strategy reaches 60, still below the 70-point threshold. Full credit requires both bookmark organization and settings configuration.

## Edge Cases and Potential Issues

- **Folder name flexibility**: The verifier uses keyword-based matching. "Mathematics & Science" matches because it contains both "math" and "science". But "STEM Resources" would NOT match because it lacks "math". The agent should follow the spec's exact folder names.
- **Bookmark categorization depth**: The categorization check uses `_get_urls_in_folder` which only examines direct children (non-recursive). Bookmarks placed in sub-sub-folders would not be counted.
- **Restricted site blocking**: The spec mentions blocking these sites via Chrome site settings (Section 4.3), but the verifier for Criterion 3 only checks the bookmark folder. Site blocking in Preferences is not separately scored. However, the content safety criterion (Criterion 6) checks cookie and notification blocking, not per-site blocking.
- **Khan Academy has two bookmarks**: Both `khanacademy.org` (general) and `khanacademy.org/math` (math-specific) should go to the Mathematics & Science folder. The domain matching will count this as one domain match since both contain `khanacademy.org`.
- **Google Classroom dual role**: Google Classroom appears as a bookmark that should go to `Classroom Tools`, but also as the homepage and startup page. The bookmark organization and settings are verified independently.
- **Notification default value**: Chrome uses `1` for "allow" (or ask) and `2` for "block" in `default_content_setting_values.notifications`. The agent must set it to `2`, not just change it to `0`.
