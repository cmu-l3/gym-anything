#!/bin/bash
echo "=== Setting up create_data_entry_form task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create seed data for bird sightings
cat << 'EOF' > /tmp/seed_birds.json
[
  {
    "title": "Sighting-2024-03-15-RedTailedHawk",
    "tags": "BirdSighting",
    "species": "Red-tailed Hawk",
    "scientific_name": "Buteo jamaicensis",
    "location": "Cedar Creek Ecosystem Science Reserve, East Bethel, MN",
    "count": "2",
    "observation_date": "2024-03-15",
    "observer": "Dr. Sarah Chen",
    "habitat": "Grassland-forest edge",
    "created": "20240315140000000",
    "modified": "20240315141500000",
    "text": "Two adults soaring in thermal over south meadow at ~1400h. Likely the same nesting pair documented at this site since 2021. Both showed typical eastern subspecies plumage—dark patagial bars, rufous tail. Wind SSW 12mph, partly cloudy, temp 42°F."
  },
  {
    "title": "Sighting-2024-03-18-GreatBlueHeron",
    "tags": "BirdSighting",
    "species": "Great Blue Heron",
    "scientific_name": "Ardea herodias",
    "location": "Riverside Marsh Unit, Minnesota Valley NWR, Bloomington, MN",
    "count": "1",
    "observation_date": "2024-03-18",
    "observer": "Dr. Sarah Chen",
    "habitat": "Freshwater marsh",
    "created": "20240318093000000",
    "modified": "20240318094200000",
    "text": "Single adult wading in north channel near the observation blind. First sighting of the season at this location. Water level approximately 18 inches. Bird was actively foraging, struck at prey twice in 15 minutes of observation."
  },
  {
    "title": "Sighting-2024-03-22-AmericanWoodcock",
    "tags": "BirdSighting",
    "species": "American Woodcock",
    "scientific_name": "Scolopax minor",
    "location": "William O'Brien State Park, Marine on St. Croix, MN",
    "count": "3",
    "observation_date": "2024-03-22",
    "observer": "Dr. Sarah Chen",
    "habitat": "Young forest with adjacent clearings",
    "created": "20240322194500000",
    "modified": "20240322200000000",
    "text": "Three males performing courtship display flights at dusk (peenting ground located on gravel trail edge). Display flights began at 19:38, approximately 22 minutes after sunset. Clear sky, calm winds, temp 38°F. Audio recorded on Zoom H5."
  },
  {
    "title": "Sighting-2024-03-28-SandhillCrane",
    "tags": "BirdSighting",
    "species": "Sandhill Crane",
    "scientific_name": "Antigone canadensis",
    "location": "Crex Meadows Wildlife Area, Grantsburg, WI",
    "count": "47",
    "observation_date": "2024-03-28",
    "observer": "Dr. Sarah Chen",
    "habitat": "Sedge meadow and flowage",
    "created": "20240328110000000",
    "modified": "20240328112000000",
    "text": "Large flock staging in Phantom Lake flowage area. Count of 47 via scope from observation platform on Refuge Road. Mix of paired adults and what appear to be subadults. Several pairs observed in unison calling display. Migration staging is approximately one week earlier than 2023."
  },
  {
    "title": "Sighting-2024-04-02-PileatedWoodpecker",
    "tags": "BirdSighting",
    "species": "Pileated Woodpecker",
    "scientific_name": "Dryocopus pileatus",
    "location": "Nerstrand Big Woods State Park, Nerstrand, MN",
    "count": "1",
    "observation_date": "2024-04-02",
    "observer": "Dr. Sarah Chen",
    "habitat": "Mature maple-basswood forest",
    "created": "20240402153000000",
    "modified": "20240402154000000",
    "text": "Single male excavating in dead American elm along Hidden Falls Trail. Rectangular excavation cavity approximately 15cm wide, consistent with foraging for carpenter ants. Bird allowed approach to ~12m before flushing. Prominent red crest and malar stripe confirmed male."
  },
  {
    "title": "Sighting-2024-04-05-BarredOwl",
    "tags": "BirdSighting",
    "species": "Barred Owl",
    "scientific_name": "Strix varia",
    "location": "Afton State Park, Hastings, MN",
    "count": "2",
    "observation_date": "2024-04-05",
    "observer": "Dr. Sarah Chen",
    "habitat": "Riparian bottomland forest",
    "created": "20240405210000000",
    "modified": "20240405211500000",
    "text": "Mated pair duetting at ~2045h from large cottonwood snag near river trail junction. Classic 'who-cooks-for-you' call with female responding in higher pitch. Pair has been documented at this territory for three consecutive breeding seasons. Overcast, light drizzle, temp 48°F."
  },
  {
    "title": "Sighting-2024-04-10-YellowBelliedSapsucker",
    "tags": "BirdSighting",
    "species": "Yellow-bellied Sapsucker",
    "scientific_name": "Sphyrapicus varius",
    "location": "Whitewater State Park, Altura, MN",
    "count": "4",
    "observation_date": "2024-04-10",
    "observer": "Dr. Sarah Chen",
    "habitat": "Mixed deciduous forest with birch",
    "created": "20240410081500000",
    "modified": "20240410083000000",
    "text": "Four individuals (2M, 2F) observed in active migration along Chimney Rock Trail ridge. All were foraging on paper birch sap wells. Fresh sapsucker wells noted on at least 8 birch trees in the survey area. Spring migrants—none were present during March surveys."
  },
  {
    "title": "Sighting-2024-04-14-EasternMeadowlark",
    "tags": "BirdSighting",
    "species": "Eastern Meadowlark",
    "scientific_name": "Sturnella magna",
    "location": "Felton Prairie SNA, Felton, MN",
    "count": "8",
    "observation_date": "2024-04-14",
    "observer": "Dr. Sarah Chen",
    "habitat": "Native tallgrass prairie",
    "created": "20240414071000000",
    "modified": "20240414073000000",
    "text": "Eight singing males on territory along the 2km prairie transect. Density consistent with 2023 breeding season counts (9 males). Several observed performing song-flight displays. Grassland quality at this site remains excellent with minimal woody encroachment. Species of conservation concern—population declining ~3% annually."
  },
  {
    "title": "Sighting-2024-04-18-RubyThroatedHummingbird",
    "tags": "BirdSighting",
    "species": "Ruby-throated Hummingbird",
    "scientific_name": "Archilochus colubris",
    "location": "Carpenter Nature Center, Hastings, MN",
    "count": "1",
    "observation_date": "2024-04-18",
    "observer": "Dr. Sarah Chen",
    "habitat": "Garden and woodland edge",
    "created": "20240418114500000",
    "modified": "20240418120000000",
    "text": "First-of-season male at the nectar feeders near the visitor center. Gorget brilliant ruby-red in direct sunlight. Arrived approximately 3 days earlier than the 10-year average first arrival date for this location. Feeders were set out April 10. Flowering red columbine also in bloom."
  },
  {
    "title": "Sighting-2024-04-22-BaltimoreOriole",
    "tags": "BirdSighting",
    "species": "Baltimore Oriole",
    "scientific_name": "Icterus galbula",
    "location": "Fort Snelling State Park, St. Paul, MN",
    "count": "3",
    "observation_date": "2024-04-22",
    "observer": "Dr. Sarah Chen",
    "habitat": "Riparian cottonwood gallery",
    "created": "20240422070000000",
    "modified": "20240422071500000",
    "text": "Three males (no females yet observed) singing from cottonwood canopy along Pike Island trail. Brilliant orange and black plumage. One observed inspecting potential nest sites in drooping elm branch—nest construction not yet begun. Insect prey abundant along river corridor."
  },
  {
    "title": "Sighting-2024-04-25-WoodDuck",
    "tags": "BirdSighting",
    "species": "Wood Duck",
    "scientific_name": "Aix sponsa",
    "location": "Rice Lake NWR, McGregor, MN",
    "count": "12",
    "observation_date": "2024-04-25",
    "observer": "Dr. Sarah Chen",
    "habitat": "Wooded wetland with nest boxes",
    "created": "20240425091000000",
    "modified": "20240425093000000",
    "text": "Twelve individuals (5 pairs + 2 extra drakes) utilizing the managed nest box area on the south shore. Three females observed investigating nest boxes. Box occupancy check scheduled for next week. Duckweed and aquatic invertebrates abundant—water quality appears good. Beaver dam maintaining optimal water level."
  },
  {
    "title": "Sighting-2024-04-29-ScarletTanager",
    "tags": "BirdSighting",
    "species": "Scarlet Tanager",
    "scientific_name": "Piranga olivacea",
    "location": "Frontenac State Park, Frontenac, MN",
    "count": "2",
    "observation_date": "2024-04-29",
    "observer": "Dr. Sarah Chen",
    "habitat": "Mature oak-hickory upland forest",
    "created": "20240429063000000",
    "modified": "20240429065000000",
    "text": "Two males singing from upper canopy on Blufflands Trail. Stunning crimson and black plumage on both—recently arrived neotropical migrants. Detected by song first (burry robin-like phrase), then located with binoculars at ~18m canopy height. Interior forest indicator species; presence suggests good habitat quality at this site."
  }
]
EOF

# Inject seed tiddlers using Node.js
echo "Injecting seed tiddlers..."
su - ga -c 'node -e "
const fs = require(\"fs\");
const path = require(\"path\");
const tiddlers = JSON.parse(fs.readFileSync(\"/tmp/seed_birds.json\", \"utf8\"));
const tiddlerDir = \"/home/ga/mywiki/tiddlers\";
if (!fs.existsSync(tiddlerDir)) {
    fs.mkdirSync(tiddlerDir, { recursive: true });
}
tiddlers.forEach(t => {
    let filename = t.title.replace(/[\/\\\\:*?\"<>|]/g, \"_\").replace(/\\s+/g, \" \");
    let filepath = path.join(tiddlerDir, filename + \".tid\");
    let content = \"\";
    if (t.created) content += \"created: \" + t.created + \"\\n\";
    if (t.modified) content += \"modified: \" + t.modified + \"\\n\";
    if (t.tags) content += \"tags: \" + t.tags + \"\\n\";
    content += \"title: \" + t.title + \"\\n\";
    Object.keys(t).forEach(k => {
        if (![\"title\", \"tags\", \"created\", \"modified\", \"text\"].includes(k)) {
            content += k + \": \" + t[k] + \"\\n\";
        }
    });
    content += \"\\n\" + (t.text || \"\");
    fs.writeFileSync(filepath, content, \"utf8\");
});
console.log(\"Seeded \" + tiddlers.length + \" bird sightings\");
"'

# Ensure the target form doesn't already exist (anti-gaming)
rm -f "/home/ga/mywiki/tiddlers/Bird Sighting Entry Form.tid" 2>/dev/null || true

# Gracefully restart TiddlyWiki to ensure it loads the new files
echo "Restarting TiddlyWiki server..."
pkill -f "tiddlywiki"
sleep 2
su - ga -c "cd /home/ga && nohup tiddlywiki mywiki --listen host=0.0.0.0 port=8080 > /home/ga/tiddlywiki.log 2>&1 &"

# Wait for server to come back up
for i in {1..30}; do
    if curl -s http://localhost:8080/ > /dev/null 2>&1; then
        echo "TiddlyWiki server is running"
        break
    fi
    sleep 1
done

# Focus Firefox and refresh page to show new tiddlers
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|tiddly" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    # Send F5 to refresh
    DISPLAY=:1 xdotool key F5
    sleep 2
    # Ensure maximized
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Record initial tiddler count
INITIAL_COUNT=$(count_user_tiddlers)
echo "$INITIAL_COUNT" > /tmp/initial_tiddler_count
echo "Initial tiddler count: $INITIAL_COUNT"

# Wait for UI to stabilize
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="