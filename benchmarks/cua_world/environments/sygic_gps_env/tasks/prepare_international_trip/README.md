# Prepare International Trip

## Overview
Configure Sygic GPS Navigation's display and regional settings for driving in the United Kingdom: switching to Miles, Fahrenheit, DMS coordinates, 12-hour time, and night mode.

## Domain Context
When driving internationally, GPS apps need regional settings adjusted to match local conventions. The UK uses miles, and a night motorway drive requires night mode. Professional drivers and tourists alike must reconfigure these settings before a trip.

## Goal / End State
- Distance units: Miles
- Temperature units: Fahrenheit
- GPS coordinate format: DMS (Degrees, Minutes, Seconds)
- Time format: 12-hour
- Color scheme: Night mode

## Verification Strategy
Five criteria (20 points each, 100 total):
1. Distance units = Miles / "0" (20 pts)
2. Temperature units = Fahrenheit / "Imperial" (20 pts)
3. GPS format = DMS / "1" (20 pts)
4. Time format = 12h / "1" (20 pts)
5. Color scheme = Night mode / "2" (20 pts)

Gate: If BOTH distance_units AND temperature_units are unchanged from setup defaults, score = 0.

## Data Sources
- Preferences: `/data/data/com.sygic.aura/shared_prefs/com.sygic.aura_preferences.xml`
  - Distance: `preferenceKey_regional_distanceUnitsFormat` ("0"=Miles, "1"=Km)
  - Temperature: `preferenceKey_weather_temperatureUnits` ("Metric"=Celsius, "Imperial"=Fahrenheit)
  - GPS format: `preferenceKey_regional_gpsFormat` ("0"=Degrees, "1"=DMS, "2"=DM)
  - Time: `preferenceKey_regional_timeFormat` ("0"=System, "1"=12h, "2"=24h)
  - Color scheme: `preferenceKey_app_theme` ("0"=auto, "1"=day, "2"=night)

## Edge Cases
- All 5 settings are in the same area of the app, but each has a different UI control (toggles, dropdowns, radio buttons)
- Some settings like GPS format and time format use selection dialogs rather than simple toggles
