#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up College Essay Consolidation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Applications"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the requirements file
REQUIREMENTS_PATH="$WORKSPACE_DIR/requirements.txt"

cat > "$REQUIREMENTS_PATH" << 'EOF'
COLLEGE APPLICATION ESSAY REQUIREMENTS - Fall 2024

STANFORD UNIVERSITY - Deadline: Jan 5
- Personal Statement (650 words max)
- Supplemental: Community Impact (250 words max)
- Supplemental: Intellectual Vitality (100-250 words)

NORTHWESTERN UNIVERSITY - Deadline: Jan 3
- Personal Statement (650 words max)
- Supplemental: Why Northwestern (300 words max)

UC BERKELEY - Deadline: Nov 30
- Personal Statement (650 words max)
- Personal Insight #1: Leadership (350 words max)
- Personal Insight #2: Creative Side (350 words max)

YALE UNIVERSITY - Deadline: Jan 2
- Personal Statement (650 words max)
- Supplemental: Community Impact (250 words max)

BROWN UNIVERSITY - Deadline: Jan 5
- Personal Statement (650 words max)
- Supplemental: Why Brown (200-250 words)

MIT - Deadline: Jan 1
- Personal Statement (650 words max)
- Supplemental: Community Impact (250 words max)

UNIVERSITY OF MICHIGAN - Deadline: Feb 1
- Personal Statement (650 words max)
- Supplemental: Why Michigan (550 words max)

CORNELL UNIVERSITY - Deadline: Jan 2
- Personal Statement (650 words max)
- Supplemental: Why Cornell (650 words max)
EOF

chown ga:ga "$REQUIREMENTS_PATH"
echo "✅ Requirements file created"

# Create essay draft files with realistic content
# Essay 1: Personal Statement (687 words - OVER 650 limit)
cat > "$WORKSPACE_DIR/essay_personal_statement.txt" << 'EOF'
Finding My Voice Through Debate

I never imagined that standing in front of a room full of people would become my greatest strength. For years, I struggled with a learning disability that made reading comprehension feel like climbing a mountain with no summit in sight. Words would swim on the page, sentences would tangle in my mind, and I convinced myself that I simply wasn't smart enough to succeed academically. My teachers' well-intentioned encouragement felt hollow when I couldn't even finish a reading assignment without exhaustion overwhelming me.

Everything changed when my English teacher, Ms. Rodriguez, suggested I join the debate team. "You have opinions," she said, "you just need a different way to express them." I was terrified. How could someone who struggled to read prepared text possibly succeed at thinking on their feet? But desperation and her persistent faith in me won out, and I showed up to my first debate practice with sweaty palms and a racing heart.

Debate forced me to confront my disability head-on, but in an unexpected way. Instead of passively receiving information from a page, I was actively engaging with ideas, breaking them down, rebuilding them, and defending them. I discovered that my brain, which stumbled over static text, excelled at processing spoken information and constructing verbal arguments in real-time. The very thing I thought made me intellectually inferior became the foundation for a different kind of excellence.

My sophomore year, I competed in my first tournament. I lost every round, but I learned something crucial: failure in debate wasn't a referendum on my intelligence—it was data. Each loss taught me something about rhetoric, logical structure, and persuasion. I started spending lunch periods in the library, not struggling through reading assignments, but listening to audiobook versions of philosophy texts, TED talks, and Supreme Court oral arguments. I learned to process information through multiple channels, building my own accommodations rather than waiting for others to provide them.

By junior year, I had developed a system. I would listen to research papers using text-to-speech software, record my thoughts verbally, and then organize them into structured arguments. My debate partner and I refined a communication style that played to both our strengths—I would handle impromptu responses and rebuttals while she managed researched evidence cards. We qualified for the state championship, something my freshman self would have considered impossible.

But my greatest achievement wasn't the trophy. It was the day I volunteered to mentor a middle school student with dyslexia who wanted to try debate. As I explained my techniques for processing information and building arguments, I realized I had transformed my perceived weakness into a genuine expertise. I wasn't succeeding despite my learning disability—I was succeeding because navigating it had taught me to think differently, to find creative solutions, and to persist when others might give up.

This experience fundamentally changed how I approach challenges. I no longer see obstacles as evidence of my limitations, but as invitations to innovate. When I struggle, I ask: "What's a different way to approach this?" rather than "Why can't I do this?" This mindset has extended far beyond debate. I've applied it to math by creating visual diagrams of problems, to science by building physical models of concepts, and to social situations by developing stronger listening skills to compensate for slower text-based communication.

College represents the next arena where I'll need to advocate for myself, develop new systems, and prove that intelligence comes in many forms. I'm not looking for an easy path—I'm looking for an environment that values diverse thinking and creative problem-solving. I want to continue proving that the most interesting solutions often come from people who have to find unconventional routes to success. My learning disability taught me resilience, creativity, and empathy. These aren't consolation prizes—they're the very skills that will allow me to contribute meaningfully to any community I join.
EOF

# Essay 2: Community Service (245 words - UNDER 250 limit)
cat > "$WORKSPACE_DIR/essay_community_service.txt" << 'EOF'
Organizing Our Community Food Drive

Last November, I noticed something troubling at our local shelter: their food pantry was running critically low just before the holiday season. Rather than simply donating a few cans from my family's pantry, I decided to organize a comprehensive community food drive through our high school.

I started by researching what the shelter actually needed. Instead of accepting random donations, I created a specific needs list focusing on protein sources, baby formula, and hygiene products—items that are frequently requested but rarely donated. I then approached our school administration with a detailed proposal, including logistics for collection, storage, and transportation.

The project taught me that effective community service requires more than good intentions—it demands organization and communication. I created a week-by-week collection schedule, recruited volunteers for sorting and delivery, and coordinated with five local businesses to serve as additional drop-off points. I designed flyers explaining why specific items were needed, which proved more effective than generic requests for "canned goods."

The challenge came when we collected far more than anticipated—over 2,000 pounds of food and supplies. Our initial transportation plan was inadequate. I had to quickly negotiate with a local moving company for a donated truck and recruit additional volunteers for the physical work of loading and unloading.

We exceeded our goal by 300%, but more importantly, I learned that meaningful impact requires understanding community needs, building partnerships, and being flexible when plans need adjustment. This experience transformed how I think about service: it's not about what makes me feel good, but about what genuinely helps others.
EOF

# Essay 3: Why Northwestern (312 words - OVER 300 limit)
cat > "$WORKSPACE_DIR/essay_why_northwestern.txt" << 'EOF'
Why Northwestern's Journalism Program

When I attended Northwestern's summer journalism workshop last year, I knew within the first day that this was where I needed to be. Sitting in Fisk Hall, listening to Professor Martinez explain how the Medill School balances traditional reporting fundamentals with digital innovation, I finally saw a program that understood what journalism needs to become, not just what it has been.

What distinguishes Northwestern is the Medill Integrated Marketing Communications approach that recognizes modern journalists can't just report—they need to understand audience analytics, multimedia storytelling, and the business models that sustain investigative work. I'm particularly drawn to the opportunity to work with the Medill Justice Project, where students conduct actual investigations that have real policy impact. The idea that my coursework could directly contribute to criminal justice reform aligns perfectly with why I want to pursue journalism in the first place.

I'm also excited about Northwestern's quarter system, which would allow me to take a wider variety of courses across different disciplines. I want to combine journalism with coursework in sociology and data science, building skills that will allow me to report on systemic issues with both narrative power and statistical rigor. The flexibility to pursue certificates in areas like legal studies while maintaining a journalism focus is exactly what I'm looking for.

Beyond academics, Northwestern's location in Evanston provides the perfect balance—close enough to Chicago to access major newsrooms and media organizations for internships, but distinct enough to have its own community identity. I've already identified three student publications I want to contribute to, and I'm eager to join the Northwestern News Network to gain broadcast experience.

The combination of Medill's reputation, the interdisciplinary opportunities, and the collaborative culture I witnessed during my visit makes Northwestern not just a good fit, but the ideal environment for me to develop as a journalist who can adapt to and shape the future of media.
EOF

# Essay 4: Leadership Berkeley (348 words - UNDER 350 limit)
cat > "$WORKSPACE_DIR/essay_leadership_berkeley.txt" << 'EOF'
Leading the Environmental Action Club

When I joined the Environmental Action Club as a sophomore, it was a small group of twelve students who met occasionally to discuss climate issues but rarely took concrete action. By the time I became president junior year, I knew we needed to transform good intentions into measurable impact.

My first initiative was controversial: I proposed we stop organizing awareness events and instead focus on implementing actual sustainability changes at our school. Some members worried we'd lose participants if we required real work instead of just attending talks. But I argued that performative environmentalism wasn't enough—we needed to prove that student leadership could create institutional change.

I organized our members into three teams: waste reduction, energy efficiency, and sustainable food. Each team had to research current school practices, identify specific problems, and develop solutions with budget projections. The waste reduction team discovered our school was spending $15,000 annually on landfill fees that could be reduced by implementing proper composting. The energy team found that upgrading to LED lighting in half the building would pay for itself in eighteen months.

The real challenge was convincing administration to take us seriously. I scheduled a meeting with the principal and facilities director, bringing our research, budget analysis, and a detailed implementation timeline. I emphasized that we weren't asking them to do the work—we were asking for approval and minimal funding while we managed the projects. They were skeptical but agreed to a pilot program.

Over the next year, we implemented composting in the cafeteria, replaced lighting in three hallways, and worked with food services to source more local ingredients. We reduced waste by 30% and energy costs by $3,000 annually. More importantly, we changed the perception of student environmental groups from idealistic to pragmatic.

This experience taught me that effective leadership means moving beyond advocacy to implementation. It's not enough to identify problems—leaders must design solutions, build coalitions, manage logistics, and deliver results. That's the kind of environmental work I want to continue at Berkeley.
EOF

# Essay 5: Creative Side (298 words - UNDER 350 limit)
cat > "$WORKSPACE_DIR/essay_creative_side.txt" << 'EOF'
Street Photography as Social Documentation

My creative outlet is street photography, but not the aesthetically pleasing kind that fills Instagram. I'm interested in documentary photography that captures the reality of my community—the closing storefronts, the growing homeless encampments, the gentrification pushing longtime residents out of neighborhoods they've lived in for generations.

I started this project two years ago when I noticed my city changing rapidly but no one was documenting what was being lost. I began photographing small businesses that were closing, interviewing owners about why they couldn't afford rising rents. I photographed the demolition of affordable housing to make room for luxury condos. I documented the tent cities appearing under highway overpasses.

What started as a personal project evolved into something larger when a local nonprofit asked to display my work at a community meeting about affordable housing policy. My photographs became evidence—visual proof of displacement that statistics couldn't fully convey. City council members attended that meeting, and while my photographs alone didn't change policy, they contributed to a conversation that led to stronger tenant protections.

This work taught me that creativity doesn't have to be separate from social awareness. The most powerful art makes the invisible visible, forces viewers to confront uncomfortable realities, and contributes to collective understanding of complex issues. I'm not a professional photographer and don't plan to become one, but I've learned that creative skills can amplify other work I want to do in urban planning and community development.

I continue this project because I believe communities deserve to have their stories told by people who actually live there, not just by outside journalists parachuting in for dramatic stories. My photography is my way of saying: I see what's happening here, I'm documenting it, and this matters.
EOF

# Essay 6: Why Brown (203 words - within 200-250 range)
cat > "$WORKSPACE_DIR/essay_why_brown.txt" << 'EOF'
Why Brown's Open Curriculum

Brown's Open Curriculum represents exactly the kind of academic freedom I'm seeking. After spending high school working within rigid requirements, I'm ready to take ownership of my education and design a course of study that reflects my actual intellectual interests rather than arbitrary distribution requirements.

I want to combine urban studies with economics and sociology to understand how cities can address inequality through policy design. At most universities, I'd be forced to choose one major and treat the others as "electives." At Brown, I can build a genuinely interdisciplinary education where each course connects to a larger understanding of urban systems.

I'm particularly excited about Brown's relationship with Providence. The Swearer Center's community engagement opportunities would allow me to apply classroom learning to real challenges facing local neighborhoods. I want to work on projects like affordable housing advocacy and small business development support—not as volunteer work separate from my studies, but as integrated components of my academic experience.

The Open Curriculum also means I can take courses because they genuinely interest me, not because they fulfill a checkbox. I want to study Arabic to understand Middle Eastern urban development, take architecture courses to understand built environments, and explore public health to understand housing conditions—all without worrying whether they "count" toward some arbitrary requirement.
EOF

# Set ownership for all essay files
chown ga:ga "$WORKSPACE_DIR"/essay_*.txt

echo "✅ All essay draft files created (6 total)"
echo "   - Personal Statement: 687 words (OVER 650 limit)"
echo "   - Community Service: 245 words (under 250 limit)"
echo "   - Why Northwestern: 312 words (OVER 300 limit)"
echo "   - Leadership Berkeley: 348 words (under 350 limit)"
echo "   - Creative Side: 298 words (under 350 limit)"
echo "   - Why Brown: 203 words (within 200-250 range)"

# Create a blank starter document with just the title to give the agent a starting point
TRACKER_PATH="$WORKSPACE_DIR/essay_tracker.docx"

cat > /tmp/create_tracker_starter.py << 'PYEOF'
#!/usr/bin/env python3
from docx import Document
from docx.shared import Pt, Inches
import sys

doc = Document()

# Set up page margins
sections = doc.sections
for section in sections:
    section.top_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)

# Add a helpful starting title
title = doc.add_paragraph()
title_run = title.add_run("College Application Essay Tracker - Fall 2024")
title_run.bold = True
title_run.font.size = Pt(16)

doc.add_paragraph()
doc.add_paragraph("Student: Maya Chen")
doc.add_paragraph()
doc.add_paragraph("[Build your essay tracker below. Review the requirements.txt and essay files in this directory.]")

doc.save(sys.argv[1])
print(f"Starter tracker document created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_tracker_starter.py
python3 /tmp/create_tracker_starter.py "$TRACKER_PATH"
chown ga:ga "$TRACKER_PATH"

echo "✅ Starter tracker document created at: $TRACKER_PATH"

# Launch ONLYOFFICE with the tracker document
echo "Launching ONLYOFFICE Document Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$TRACKER_PATH' > /tmp/onlyoffice_essay_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_essay_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 960 540 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo ""
echo "=== College Essay Consolidation Task Setup Complete ==="
echo ""
echo "📚 SCENARIO:"
echo "Maya is a high school senior with 2 days until college application deadlines."
echo "She has essay drafts scattered across multiple files and needs to consolidate"
echo "them into one master tracker document."
echo ""
echo "📁 FILES AVAILABLE IN /home/ga/Documents/Applications/:"
echo "  - requirements.txt (all school requirements and deadlines)"
echo "  - essay_personal_statement.txt"
echo "  - essay_community_service.txt"
echo "  - essay_why_northwestern.txt"
echo "  - essay_leadership_berkeley.txt"
echo "  - essay_creative_side.txt"
echo "  - essay_why_brown.txt"
echo ""
echo "📝 YOUR TASK:"
echo "Create a comprehensive essay tracker document that includes:"
echo ""
echo "1. DEADLINE SUMMARY (chronological order)"
echo "   Nov 30: UC Berkeley"
echo "   Jan 1: MIT"
echo "   Jan 2: Yale, Cornell"
echo "   Jan 3: Northwestern"
echo "   Jan 5: Stanford, Brown"
echo "   Feb 1: University of Michigan"
echo ""
echo "2. ESSAY STATUS TABLE with columns:"
echo "   - Essay Name/Type"
echo "   - Current Word Count"
echo "   - Schools Using It"
echo "   - Word Limit"
echo "   - Status (OK, TRIM NEEDED, ADD WORDS)"
echo ""
echo "3. FULL ESSAY CONTENT SECTION"
echo "   Copy all essay text from the files with proper labels and headings"
echo ""
echo "4. PRIORITY ACTION ITEMS"
echo "   List which essays need trimming or expansion"
echo ""
echo "💡 HINTS:"
echo "  - Use File > Open to view the requirements and essay files"
echo "  - Create a table for the essay status (Insert > Table)"
echo "  - Copy/paste essay content from the text files"
echo "  - Use headings to organize sections"
echo "  - Personal statement (687 words) is OVER the 650 limit"
echo "  - Why Northwestern (312 words) is OVER the 300 limit"
echo "  - Save your work regularly (Ctrl+S)"
echo ""