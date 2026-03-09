# Task: Build Corporate Site Structure

## Domain Context
**Occupation:** Web Developer (SOC 15-1254.00) / Graphic Designer (SOC 27-1024.00)
**Rationale:** Web developers routinely transform WordPress blogs into corporate websites by creating page hierarchies, setting static front pages, and configuring site identity. This requires cross-area navigation (Pages, Reading Settings, General Settings).

## Goal
Transform the blog into a corporate website for "NexGen Solutions" with a hierarchical page structure, static front page, and updated branding.

## Expected End State
- 6 pages created and published:
  - "Services" (top-level, set as static front page)
  - "Web Development" (child of Services)
  - "Mobile Apps" (child of Services)
  - "Cloud Solutions" (child of Services)
  - "About" (standalone)
  - "Careers" (standalone)
- Each page has at least 50 words of relevant content
- Reading settings: show_on_front = "page", page_on_front = Services page ID
- Site title: "NexGen Solutions"
- Tagline: "Innovative Technology Consulting"

## Verification Strategy
7 programmatic criteria (70 pts total):
1. Page "Services" exists and published (5 pts)
2. "Web Development" is child of "Services" (10 pts)
3. "Mobile Apps" is child of "Services" (10 pts)
4. "Cloud Solutions" is child of "Services" (10 pts)
5. "About" and "Careers" exist (10 pts)
6. Static front page set to "Services" (15 pts)
7. Site title and tagline updated (10 pts)

VLM checks (30 pts).

Pass threshold: score >= 70 AND Services exists AND static front page set to Services.

## Schema Reference
- Pages: `wp_posts WHERE post_type='page'`
- Parent-child: `wp_posts.post_parent` field
- Reading settings: `wp_options` — `show_on_front`, `page_on_front`
- Site identity: `wp_options` — `blogname`, `blogdescription`

## Edge Cases
- Agent might create "About" page but one already exists from setup — export checks by title
- Parent-child relationships require setting post_parent to the Services page ID
- Twenty Twenty-Four is a block theme — page creation uses the Gutenberg editor
- Agent may need to navigate to Settings > Reading to set static front page
