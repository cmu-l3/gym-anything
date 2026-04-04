#!/bin/bash
set -e
echo "=== Setting up NSF Grant Narrative Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Documents/results

# Remove any previous output file
rm -f /home/ga/Documents/NSF_SES2415837_ProjectDescription.odt 2>/dev/null || true

# Create the project data JSON file
cat > /home/ga/Documents/project_data.json << 'JSONEOF'
{
  "pi": {
    "name": "Dr. Elena Vasquez-Reyes",
    "title": "Associate Professor",
    "department": "Department of Sociology",
    "institution": "University of New Mexico",
    "address": "MSC05 3080, 1 University of New Mexico, Albuquerque, NM 87131",
    "email": "evasquez@unm.edu",
    "phone": "(505) 277-2501"
  },
  "co_pis": [
    {"name": "Dr. Marcus Whitehorse", "title": "Assistant Professor", "department": "Department of Geography and Environmental Studies", "institution": "University of New Mexico"},
    {"name": "Dr. Sarah Chen-Ramirez", "title": "Associate Professor", "department": "School of Public Health", "institution": "University of New Mexico"}
  ],
  "project": {
    "title": "Community Resilience and Environmental Justice in Extraction Zones: A Mixed-Methods Study of Frontline Communities in the American West",
    "nsf_program": "Sociology Program (SES)",
    "proposal_number": "SES-2415837",
    "requested_amount": 349875,
    "duration_months": 36,
    "start_date": "2025-09-01",
    "end_date": "2028-08-31",
    "keywords": ["environmental justice", "resource extraction", "community resilience", "collective efficacy", "rural sociology", "mixed methods"]
  },
  "study_sites": [
    {"name": "Permian Basin", "states": "New Mexico / Texas", "population_centers": ["Carlsbad, NM", "Hobbs, NM", "Pecos, TX"], "industry": "Oil and natural gas extraction", "context": "Largest oil-producing basin in the US; rapid boom-bust cycles since 2010 shale revolution"},
    {"name": "San Juan Basin", "states": "New Mexico", "population_centers": ["Farmington, NM", "Bloomfield, NM"], "industry": "Coal mining, natural gas extraction", "context": "Legacy coal region transitioning away from extraction; Four Corners Power Plant retired units"},
    {"name": "Powder River Basin", "states": "Wyoming", "population_centers": ["Gillette, WY", "Sheridan, WY"], "industry": "Coal mining, coalbed methane extraction", "context": "Largest US coal-producing region; significant employment contraction since 2015"}
  ],
  "methods": {
    "survey": {"sample_size": 1200, "per_site": 400, "sampling_strategy": "Stratified random sampling by census tract proximity to extraction sites (0-1 mile, 1-5 miles, 5-15 miles)", "instrument": "60-item questionnaire covering perceived environmental risk (12 items), community attachment (8 items), collective efficacy (10 items), self-reported health impacts (15 items), demographic characteristics (15 items)", "mode": "Mixed-mode: online (Qualtrics) and mailed paper questionnaire", "response_rate_target": "45% minimum"},
    "interviews": {"sample_size": 90, "per_site": 30, "target_participants": "Community leaders, long-term residents (10+ years), newcomers (<3 years), local government officials, tribal representatives (San Juan and Powder River basins)", "format": "Semi-structured, 60-90 minutes, recorded and transcribed", "analysis": "Thematic analysis using Dedoose software, dual-coded by PI and GRA"},
    "gis_analysis": {"data_sources": ["EPA Toxics Release Inventory (TRI)", "US Census American Community Survey 5-year estimates", "State oil and gas well permit databases (NM OCD, TX RRC, WY OGCC)", "CDC PLACES health data (census tract level)", "USGS National Hydrography Dataset"], "software": "ArcGIS Pro 3.x, GeoDa 1.22", "analyses": "Spatial clustering of health outcomes near extraction infrastructure, environmental justice screening using CalEnviroScreen methodology adapted for study regions"}
  },
  "theoretical_framework": {
    "primary_theories": ["Treadmill of Production theory (Schnaiberg 1980; Gould, Pellow & Schnaiberg 2008)", "Environmental justice framework (Bullard 1990, 2000; Mohai, Pellow & Roberts 2009)", "Community resilience model (Norris et al. 2008; Magis 2010)"],
    "contribution": "Integrates macro-structural political economy (treadmill of production) with meso-level community processes (collective efficacy, place attachment) to explain variation in resilience outcomes across extraction-dependent communities"
  },
  "timeline": {
    "year1": "IRB approval, instrument development and pilot testing, GIS database construction, begin Permian Basin fieldwork (survey + interviews)",
    "year2": "Complete Permian Basin data collection, conduct San Juan Basin and Powder River Basin fieldwork, begin survey data analysis",
    "year3": "Complete all data collection, qualitative analysis, GIS modeling, manuscript preparation, dissemination to communities and policymakers"
  },
  "broader_impacts": {
    "community_engagement": "Community advisory boards at each site; findings presented at town halls; plain-language policy briefs distributed to local governments and tribal councils",
    "training": "2 PhD students and 3 undergraduates trained in mixed-methods research; priority recruitment of students from underrepresented groups through UNM McNair Scholars Program",
    "policy_relevance": "Results will inform state-level environmental health policy in NM, TX, and WY; data shared with EPA Region 6 and Region 8 environmental justice offices",
    "open_science": "De-identified survey data and GIS layers deposited in ICPSR within 2 years of project completion; all publications submitted to open-access journals or posted as preprints"
  },
  "budget": {
    "personnel": [
      {"role": "PI (Dr. Vasquez-Reyes)", "effort": "2 months summer salary per year", "annual": 28500, "total": 85500},
      {"role": "Graduate Research Assistants (2)", "effort": "20 hrs/week, 12 months/year", "annual": 52000, "total": 156000},
      {"role": "Undergraduate Research Assistants (3)", "effort": "10 hrs/week, 9 months/year", "annual": 9000, "total": 27000}
    ],
    "travel": {"description": "Fieldwork travel to 3 study sites, 4 trips per year", "annual": 8125, "total": 24375},
    "participant_support": {"description": "Survey incentives ($20/respondent x 1200) + interview incentives ($50/interviewee x 90)", "total": 28500},
    "supplies": {"description": "Digital audio recorders, transcription software (Otter.ai Pro), Qualtrics license, ArcGIS Pro licenses, printing/mailing", "total": 12500},
    "other_direct_costs": {"description": "IRB fees, cloud storage, open-access publication fees, ICPSR deposit fee", "total": 16000},
    "total_direct_costs": 349875,
    "indirect_costs_note": "Indirect costs calculated at UNMs federally negotiated rate of 54.5% MTDC; waived for this submission per NSF budget cap"
  },
  "references": [
    "Bell, S.E. & York, R. (2010). Community economic identity: The coal industry and ideology construction in West Virginia. Rural Sociology, 75(1), 111-143.",
    "Bullard, R.D. (2000). Dumping in Dixie: Race, Class, and Environmental Quality (3rd ed.). Westview Press.",
    "Freudenburg, W.R. & Gramling, R. (2011). Blowout in the Gulf: The BP Oil Spill Disaster and the Future of Energy in America. MIT Press.",
    "Gould, K.A. & Lewis, T.L. (2017). Green Gentrification: Urban Sustainability and the Struggle for Environmental Justice. Routledge.",
    "Gould, K.A., Pellow, D.N. & Schnaiberg, A. (2008). The Treadmill of Production: Injustice and Unsustainability in the Global Economy. Paradigm Publishers.",
    "Jerolmack, C. & Walker, E.T. (2018). Please in My Backyard: Quiet Mobilization in Support of Fracking in an Appalachian Community. American Journal of Sociology, 123(5), 1251-1290.",
    "Magis, K. (2010). Community resilience: An indicator of social sustainability. Society and Natural Resources, 23(5), 401-416.",
    "Malin, S.A. & DeLuca, T.H. (2020). A paradox of plenty: Wind energy development and well-being in the rural American West. Rural Sociology, 85(3), 682-706.",
    "Mayer, A. (2016). Risk and benefits in a fracking boom: Evidence from Colorado. Risk Analysis, 36(6), 1172-1182.",
    "Mohai, P., Pellow, D. & Roberts, J.T. (2009). Environmental justice. Annual Review of Environment and Resources, 34, 405-430.",
    "Norris, F.H. et al. (2008). Community resilience as a metaphor, theory, set of capacities, and strategy for disaster readiness. American Journal of Community Psychology, 41, 127-150.",
    "Schnaiberg, A. (1980). The Environment: From Surplus to Scarcity. Oxford University Press.",
    "Willow, A.J. (2014). The new politics of environmental degradation: Un/expected landscapes of disempowerment and vulnerability. Journal of Political Ecology, 21, 237-257."
  ],
  "nsf_formatting_requirements": {
    "margins": "1 inch (2.54 cm) on all sides",
    "font": "Times New Roman or equivalent serif font, 11-point minimum for body text",
    "spacing": "Single-spaced body text",
    "page_limit": 15,
    "required_sections": [
      "Introduction and Intellectual Merit",
      "Theoretical Framework and Literature Review",
      "Research Design and Methods",
      "Data Sources and Sampling Strategy",
      "Timeline and Project Management",
      "Broader Impacts",
      "References Cited"
    ],
    "additional_notes": "Document must include a Table of Contents and page numbers. Budget Justification should include a summary table with line items."
  }
}
JSONEOF

# Set ownership
chown ga:ga /home/ga/Documents/project_data.json
chmod 644 /home/ga/Documents/project_data.json

# Launch OpenOffice Writer with a blank document
echo "Starting Apache OpenOffice Writer..."
pkill -f soffice 2>/dev/null || true
sleep 1

# Launch as user 'ga'
su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"

# Wait for window
echo "Waiting for Writer window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "OpenOffice Writer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice Writer" 2>/dev/null || true

# Wait a moment for UI to settle then take screenshot
sleep 3
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="