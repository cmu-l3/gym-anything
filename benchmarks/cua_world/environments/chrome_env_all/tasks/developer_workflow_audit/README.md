# Developer Workflow Audit (`developer_workflow_audit@1`)

## Overview

**Domain**: Software Developer -- Browser Workspace Separation

A software developer joining a new team must configure their browser according to the team's development workflow standard. The current bookmark bar contains 40 bookmarks -- a mix of development tools and personal sites -- all placed flat with no organization. The team standard requires separating development bookmarks from personal content into a structured folder hierarchy, configuring project-specific search engine shortcuts, and updating browser settings to match team policies.

## Initial State

- **Bookmarks**: 40 flat bookmarks on the bookmark bar (22 development + 18 personal). Development bookmarks include GitHub, Stack Overflow, Python Docs, MDN, Docker Hub, Kubernetes, Terraform, Grafana, Prometheus, Jenkins, Jira, Confluence, npm, PyPI, Go Packages, crates.io, and AWS Docs. Personal bookmarks include YouTube, Netflix, Reddit, Spotify, Twitter, Instagram, Amazon, eBay, ESPN, Weather.com, Craigslist, Pinterest, Tumblr, Twitch, and others.
- **Preferences**: Non-compliant defaults -- homepage set to `google.com`, no custom search engines, third-party cookies allowed, Do Not Track disabled, download directory at `/home/ga/Downloads`, prompt_for_download false, restore_on_startup = 5.
- **Spec file**: `~/Desktop/dev_team_browser_standard.txt` -- Engineering Team Browser Configuration Standard v3.0.
- **Download directory**: `/home/ga/projects/downloads` pre-created.

## Goal

All specifications from the team standard are implemented:

- **Development** folder on the bookmark bar with 5 sub-folders:
  - `Source Control` -- all GitHub bookmarks
  - `Documentation` -- docs.python.org, developer.mozilla.org, kubernetes.io/docs, docs.aws.amazon.com
  - `Package Registries` -- npmjs.com, pypi.org, pkg.go.dev, crates.io, hub.docker.com, registry.terraform.io
  - `DevOps` -- grafana.com, prometheus.io, jenkins.io
  - `Project Management` -- Jira and Confluence bookmarks
- **Reference** folder containing Stack Overflow bookmarks.
- **Personal** folder containing all non-work bookmarks (no personal bookmarks left loose on the bookmark bar).
- 4 custom search engine shortcuts: `gh` (GitHub), `so` (Stack Overflow), `mdn` (MDN Web Docs), `pypi` (PyPI).
- Homepage set to `https://github.com`.
- Startup set to restore previous session (`restore_on_startup = 1`).
- Third-party cookies blocked, Do Not Track enabled.
- Download directory: `/home/ga/projects/downloads`, prompt enabled.

## Success Criteria

The task is verified against 7 criteria totaling 100 points. Pass threshold: **70/100**.

## Scoring Breakdown

| # | Criterion | Points | Details |
|---|-----------|--------|---------|
| 1 | Development folder with sub-folders | 20 | Folder exists (5 pts); each valid sub-folder with matching bookmarks (3 pts each, up to 15 pts for 5 sub-folders) |
| 2 | Reference folder | 10 | Folder exists (5 pts); contains Stack Overflow bookmark(s) (5 pts) |
| 3 | Personal folder with personal bookmarks | 15 | Folder exists (3 pts); >= 12 of 18 personal bookmarks inside (7 pts proportional); no personal bookmarks loose on bar (5 pts) |
| 4 | Custom search engines | 15 | Scored per engine found: 1=3pts, 2=7pts, 3=11pts, 4=15pts |
| 5 | Homepage and startup | 15 | Homepage contains `github.com` (8 pts); restore_on_startup = 1 (7 pts) |
| 6 | Cookie/privacy settings | 10 | Third-party cookies blocked (5 pts); Do Not Track enabled (5 pts) |
| 7 | Download directory | 15 | Path contains `projects/downloads` (8 pts); prompt_for_download = true (7 pts) |

## Verification Strategy

1. **Development folder**: Bookmark bar is searched for a folder named "Development" (case-insensitive). Inside it, 5 named sub-folders are checked. Each sub-folder earns 3 points only if it both exists AND contains at least one bookmark matching its expected domain list.
2. **Reference folder**: Bookmark bar searched for "Reference" folder. Stack Overflow domain matching applied to its contents.
3. **Personal folder**: Bookmark bar searched for "Personal" folder. Personal domain bookmarks inside are counted against the 18-domain list. Additionally, the bookmark bar's top-level URL children are scanned -- any personal domain bookmark still at the top level is a deduction.
4. **Search engines**: Preferences JSON scanned across `search_provider_overrides`, `default_search_provider.list`, `search_engines`, and raw JSON keyword-matching. Each of `gh`, `so`, `mdn`, `pypi` is checked.
5. **Homepage/startup**: `homepage` field checked for `github.com`. `session.restore_on_startup` checked for value 1.
6. **Cookie/privacy**: `profile.cookie_controls_mode` checked for 1 (block third-party). `enable_do_not_track` checked for true.
7. **Download**: `download.default_directory` checked for `projects/downloads`. `download.prompt_for_download` checked for true.

## Edge Cases and Potential Issues

- **Reddit ambiguity**: Reddit appears in both development-adjacent form (`reddit.com/r/programming`) and personal form (`reddit.com`, `reddit.com/r/gaming`). The verifier classifies `reddit.com` as personal. The `reddit.com/r/programming` bookmark is an edge case -- the URL-based domain check will match `reddit.com`, classifying it as personal. The agent must reason about the spec which says "ALL personal/non-work bookmarks" go to Personal.
- **Sub-folder naming**: Sub-folder matching is case-insensitive exact match. "Docs" instead of "Documentation" will not match.
- **Bookmark deduplication**: Some domains appear in multiple bookmarks (e.g., GitHub has 3 bookmarks: main, PRs, notifications). All should go to `Source Control`.
- **Startup mode semantics**: The spec says "restore the previous session" which maps to `restore_on_startup = 1`, not 4 (specific pages) or 5 (new tab page).
- **Cookie controls mode**: The verifier checks `profile.cookie_controls_mode` for value 1. The alternate check via `default_content_setting_values.cookies = 2` is also accepted.
- **No contamination injection**: All 40 bookmarks are legitimate -- the challenge is correct classification and comprehensive configuration, not filtering.
