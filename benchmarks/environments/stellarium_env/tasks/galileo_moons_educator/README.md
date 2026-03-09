# Task: Science Educator — Galileo's Discovery of Jupiter's Moons (1610)

## Domain Context

Planetarium educators and science museum presenters routinely use Stellarium to recreate historical
astronomical observations for live demonstrations and exhibit preparation. Galileo Galilei's
discovery of Jupiter's four large moons in January 1610 is one of history's most important
astronomical observations — the first proof that not all celestial bodies orbit Earth.

This task simulates the workflow of an educator preparing an interactive two-night comparison
demonstration: showing the same field of view on January 7 and January 8, 1610 to illustrate how
the moons visibly shifted position in just 24 hours. The educator must configure Stellarium for
Galileo's observing site (Florence, Italy), navigate to the historical dates, set up appropriate
display conditions (telescope-like clear view), zoom into Jupiter, and document both nights.

## Occupation / Industry

**Occupation**: Science Educator / Planetarium Presenter / Science Museum Guide
**Industry**: Education / Science Communication / Museums

## Task Description (for agent)

You are a science educator at a natural history museum preparing an interactive demonstration of
Galileo Galilei's discovery of Jupiter's moons in January 1610. Configure Stellarium to recreate
Galileo's observations from Florence, Italy (latitude 43.7696°N, longitude 11.2558°E, altitude 50m).

For Night 1: Set the date to January 7, 1610 at 19:00 UTC. Configure the display for a clear
telescope-like view: disable the atmosphere, disable the ground landscape, and enable constellation
lines so visitors can orient themselves in the sky. Find Jupiter using the search function, center
the view on it, and zoom in closely until the Galilean moons (Io, Europa, Ganymede, Callisto) are
visible alongside Jupiter's disk. Take a screenshot at this zoom level.

For Night 2: Without changing the location or display settings, advance the date to January 8, 1610
at 19:00 UTC (24 hours later). Center on Jupiter again and take another screenshot showing how the
moons have shifted their positions.

Write your educator's presentation notes to /home/ga/Desktop/galileo_demo_notes.txt documenting
both observation dates (January 7 and January 8, 1610) and describing what the comparison shows
about Jupiter's moons.

## Success Criteria

1. **Florence location set**: lat ≈ 43.77°N (0.7637 rad), lon ≈ 11.26°E (0.1965 rad)
2. **Constellation lines enabled**: for visitor sky orientation
3. **Atmosphere disabled**: for clean telescope-like view
4. **2+ screenshots taken**: one per night
5. **Demonstration notes written**: /home/ga/Desktop/galileo_demo_notes.txt with date content

## Scoring (100 points)

- Florence location set (lat within 0.08 rad of 0.7637 rad): **25 points**
- Constellation lines enabled: **15 points**
- Atmosphere disabled: **15 points**
- 2+ screenshots taken: **25 points**
- Demonstration notes written with 1610/Galileo/Jupiter content: **20 points**

Pass threshold: 70 points

## Real Data Sources

- Florence, Italy coordinates: 43.7696°N, 11.2558°E, ~50m altitude
  - Source: Official geographic coordinate databases (Galileo's observing location)
- Galileo's observation dates: January 7-8, 1610 (Gregorian calendar)
  - Source: Galileo Galilei (1610). "Sidereus Nuncius" (Starry Messenger). Venice: Thomas Baglioni
  - Galileo first recorded Jupiter's moons on January 7, 1610, noting their movement January 8
- Jupiter's Galilean moons: Io, Europa, Ganymede, Callisto — named by Simon Marius (1614)

## Edge Cases

- Both dates are historical (1610) — requires navigating ~414 years back from 2024
- Zoom level must be high enough to see moons — requires multiple zoom-in steps
- After Night 2, the agent should NOT change location or display settings from Night 1 state
