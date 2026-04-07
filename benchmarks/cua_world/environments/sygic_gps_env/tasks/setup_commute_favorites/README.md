# Setup Commute Favorites

## Overview
A construction worker sets up daily commute locations in Sygic GPS Navigation: configuring Home, Work, and a Favorite gas station using the app's location search and save features.

## Domain Context
Construction workers frequently commute to job sites and need quick-access navigation to Home, Work, and regular stops (gas stations). Setting up these saved locations requires using the app's search, address resolution, and multiple save flows (Home vs Work vs Favorites — each has a different UI flow).

## Goal / End State
- Home address set to 1600 Pennsylvania Avenue NW, Washington, DC (lat ~38.90, lon ~-77.04)
- Work address set to 350 5th Avenue, New York, NY (lat ~40.75, lon ~-73.99)
- A Favorite named "Gas Station" saved for any gas station location

## Verification Strategy
Four criteria (100 points total):
1. **Home set** (25 pts): `place` table has entry with type=0 (Home)
2. **Work set** (25 pts): `place` table has entry with type=1 (Work)
3. **Favorite added** (25 pts): `favorites` table has at least one entry
4. **Coordinate accuracy** (25 pts): Home coords within 0.1° of expected (12.5 pts), Work coords within 0.1° (12.5 pts)

Gate: If no place entries AND no favorites exist, score = 0.

## Data Sources
- Places database: `/data/data/com.sygic.aura/databases/places-database` (SQLite)
  - `place` table: type 0=Home, 1=Work; columns: id, title, latitude, longitude, address_*
  - `favorites` table: id, title, latitude, longitude, address_*

## Edge Cases
- Search may return multiple results — agent must select the correct address
- "Gas Station" search requires the app to have network access for POI search
- Home and Work save flows are different from the general Favorites save flow
- Coordinates will vary depending on which search result the agent selects
