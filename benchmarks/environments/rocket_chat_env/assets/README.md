# Rocket.Chat Real Data Source

This environment uses real release announcement data from the official Rocket.Chat GitHub repository.

- Source URL: `https://api.github.com/repos/RocketChat/Rocket.Chat/releases?per_page=25`
- Retrieval date (UTC): `2026-02-16`
- Local snapshot file: `rocketchat_releases_github_api_2026-02-16.json`

The post-start setup script reads this snapshot and seeds the `#release-updates` channel with release messages containing real release version tags, publish dates, and official release URLs.
