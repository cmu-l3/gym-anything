# Consumer / Personal-Use Scenarios

This is the consumer-corpus replacement for the O*NET occupation × software
× GDP grid (`master_dataset.csv` / `selected_products.csv` in the enterprise
corpus). It defines what "realistic" means when tasks target *individuals
using software for personal reasons*, not employees using software at work.

Read this before designing any task. Every task you create should map to at
least one scenario class below.

---

## Core distinction: personal use ≠ professional use

| Dimension              | Enterprise framing (NOT this corpus)        | Consumer framing (this corpus)                      |
|------------------------|---------------------------------------------|-----------------------------------------------------|
| Who is the user?       | An employee in a role                        | A person living their life                          |
| Why are they here?     | Job responsibility / business goal           | Personal goal, family need, hobby, curiosity        |
| Whose constraints?     | Firm / industry / regulatory                 | Household budget, family, calendar, geography       |
| Output artifact        | Report, audit, structured data deliverable   | Saved note, planned itinerary, signed form, photo album, shared link, calendar event |
| Domain expertise       | Professional / specialist                    | General literacy + ability to research              |
| Persona opener         | *"You are a [analyst / engineer / clinician] at a [firm]"* | *"You are planning..." / "You need to..." / "Your family is..."* |

If a task starts with *"You are a labor economist at a regional planning
agency..."* or *"You are a DevSecOps engineer at a consultancy..."*, it
belongs in the enterprise corpus, not here.

---

## Scenario classes by app category

Each class lists *what kind of real personal-use work* the app supports.
These are not task descriptions — they are *spaces* to design tasks within.

### Web browser (Safari, Firefox, Chrome)

- **Trip planning** — itinerary across 3+ cities / regions, comparing flights, hotels, day-trips against a budget cap
- **Comparison shopping** — major purchase (car, mattress, laptop, appliance) — researching specs, reviews, total cost of ownership, financing
- **Family medical research** — symptoms, second opinions, in-network providers, drug interactions, finding a pediatrician with specific qualifications
- **Hobby / craft research** — sourcing materials, comparing tools (camera lenses, woodworking supplies, knitting yarn), tutorials
- **School research** — kid's class project, college shortlist (acceptance rate × cost × major × geography), tutoring options
- **Personal finance research** — comparing savings accounts, credit cards, insurance quotes, investment options
- **Recipe / meal planning** — gathering recipes across sites that match dietary constraints (gluten-free, vegan, kid-friendly), grocery-list synthesis
- **Local services** — finding a contractor, plumber, dentist, hair salon meeting criteria + proximity + reviews
- **Civic / news research** — researching local ballot measures, school board candidates, neighborhood zoning proposals for personal opinion-forming
- **Hobby content discovery** — tracking a sports team's transfer rumors across blogs/forums, comparing fan-theories about a TV show

### Notes app (Apple Notes, Bear, Obsidian, OneNote)

- **Daily journal / log** — health tracking (symptoms, meals, mood), workout log, sleep notes, reading log
- **Recipe collection** — collecting + organizing recipes with personal modifications, weekly meal plan
- **Travel itinerary** — multi-day trip plan with reservations, addresses, contact info, packing list
- **Household management** — passwords, account info, warranty info, contractor contacts, paint colors used in each room
- **Study / learning notes** — class notes, language-learning vocab, online-course notes
- **Project notes for personal hobby** — woodworking plans + cut lists, garden plan, home-renovation decisions
- **Party / event planning** — guest list, menu, shopping list, schedule, contingency plan
- **Personal writing** — journal entries, short stories, blog drafts, song lyrics

### Photo app (Apple Photos)

- **Family album curation** — selecting + arranging photos for an event / year / specific child
- **Vacation slideshow** — picking the best photos from a trip to share with extended family
- **Photo book prep** — selecting photos for a printed book (size constraints, chronological / thematic ordering)
- **Duplicate cleanup** — removing burst-mode duplicates, finding near-identical shots
- **Search and tagging** — finding "all photos of grandma at the beach" or "photos from the 2018 summer"
- **Sharing / privacy** — exporting a subset of photos to send to a relative, ensuring no sensitive shots are included
- **Photo editing for personal use** — straightening, cropping, brightening photos for printing or sharing

### Media player / recorder (QuickTime, VLC)

- **Screen recording for personal use** — recording a how-to for a relative (showing grandparent how to use FaceTime), recording gameplay, recording a Zoom call for memory
- **Trimming home video** — cutting a long recording down to share-worthy length
- **Audio note / voice memo** — recording / organizing voice notes
- **Watching downloaded content** — managing a library of personal video files

### PDF viewer (Preview, Adobe Reader)

- **Signing personal documents** — school permission slip, lease addendum, tax form, medical consent
- **Filling out forms** — job application, school application, government form
- **Comparing documents** — multiple insurance quotes, lease drafts, contractor estimates
- **Extracting pages** — pulling specific pages from a kid's school PDF to share with a tutor
- **Annotating personal reading** — highlighting + notes on a book / paper for a book club or personal study

### Word processor (Pages, Word)

- **Personal correspondence** — letter of recommendation, thank-you note, condolence letter, complaint letter
- **School assignment** — essay, lab report, presentation (for the user's own coursework)
- **Resume / cover letter** — personal job search documents
- **Party / event materials** — invitation, program, menu card
- **Family communication** — annual holiday letter, newsletter to extended family
- **Custom printables** — greeting card, sign, label

### Calendar (Apple Calendar)

- **Family scheduling** — coordinating across spouse + kids + own work calendar
- **Trip planning blocks** — booking time off, scheduling travel, meeting times in different time zones
- **Event planning** — birthday party, anniversary, study group, hobby meetup
- **Recurring personal routines** — workout schedule, medication reminders, weekly check-ins with a relative

### Maps (Apple Maps)

- **Trip itinerary** — plotting day-by-day route across a city / region
- **Finding kid-friendly route** — avoiding highways, finding rest stops, scenic alternatives
- **Transit comparison** — finding the best way to get from A to B given a constraint (avoid transfers, before 8 PM, wheelchair-accessible)
- **Discovering local interest** — finding restaurants, parks, museums matching criteria around a location

### Mail (Mail.app)

- **Family communication management** — organizing emails from school / doctor / kids' activities
- **Subscription cleanup** — finding + unsubscribing from unwanted mailing lists
- **Receipt / record collection** — finding tax-relevant receipts across the inbox
- **Trip booking confirmation gathering** — collecting flight, hotel, rental car confirmations

---

## Hardness levers for consumer tasks

The enterprise corpus achieves task hardness through *professional domain
complexity* (financial regulations, medical compliance, technical depth).
The consumer corpus achieves hardness through different levers:

1. **Multi-stakeholder constraints** — spouse + 2 kids with conflicting
   preferences (food, schedule, accessibility, age-appropriateness). Agent
   must satisfy *all* simultaneously.

2. **Household budget** — total cap not just sticker price; total cost
   of ownership (subscription, fuel, maintenance, training); financing
   tradeoffs.

3. **Multi-stage decisions** — research → shortlist → compare → decide →
   execute (book / buy / sign / save). The decision is the *means*, not
   the *end* — the artifact (booked reservation, signed form, saved
   itinerary) is the verifiable output.

4. **Geography constraints** — distance, transit availability, parking,
   local availability, time-zone math, weather seasonality.

5. **Time / calendar constraints** — pickup-by-X, conflict with existing
   events, school holidays, blackout dates.

6. **Multi-source synthesis** — combining 3+ independent sources (e.g. for
   a pediatrician: medical credentials directory + insurance network +
   review sites + appointment availability + practice location).

7. **Personal preferences** — dietary (vegan, kosher, gluten-free, halal,
   nut allergy), accessibility (wheelchair, hearing-impaired, low-vision),
   age-appropriate (toddler-friendly, teen-appropriate), pet-friendly,
   noise-sensitive.

8. **Real-world specificity** — actual cities, actual restaurants, actual
   products, actual schools, actual people (public figures only). Generic
   "Restaurant A vs Restaurant B" is not a real task.

9. **Conflicting information** — different sources disagree (one review
   site says X, another says Y); the agent must arbitrate.

10. **Output artifact integrity** — the saved file / note / event must be
    structurally correct in the app's native format (a Pages document, an
    Apple Notes note with attachments, a Calendar event with multiple
    attendees and a reminder), not just text dumped to a JSON.

---

## Anti-patterns specific to consumer task framing

Consumer tasks fail in distinctive ways. Avoid these:

- **"You are a [professional]" persona opener** — instant enterprise
  framing. Use *"You are planning..." / "Your family needs..." /
  "You're trying to decide between..."* instead.

- **Output as "save findings to ~/Documents/X.json"** — that is a
  professional research deliverable, not a personal-use output. The output
  should be: a note in Apple Notes, a calendar event with reminders, a
  signed PDF, an album in Photos, a Pages document ready to send, a
  shortlist saved as a bookmark folder.

- **Requiring professional certifications / standards as ground truth**
  (WCAG 2.1, SEC EDGAR filings, ACS surveys, GLP-1 RCTs, SOC2). Consumer
  tasks have *consumer* ground truth: actual product specs, actual reviews,
  actual prices, actual hours of operation, actual reservation
  availability.

- **Writing the task as an "audit"** — *"audit your subscriptions",
  "audit your family's screen time"* — agents trained on this corpus
  will produce auditor-flavored output. Write as *"clean up", "organize",
  "plan", "find", "decide", "choose"* instead.

- **Including the answer in metadata as a checklist of values to match**
  — for consumer tasks, the agent's *justified choice* is often the
  output, not a specific value from a ground-truth list. Verification
  should check the *artifact's structural properties + citation support*
  rather than exact-field equality.

- **Synthetic personas with full demographics** — *"You are Sarah, a
  35-year-old marketing manager with two kids ages 4 and 7 in San
  Francisco..."* This is theatrical and brittle. State just enough about
  the situation to constrain the task; let the agent fill in the rest.

---

## How to use this file when designing a task

1. Pick the app you're targeting.
2. Find that app's section above. Pick a scenario class that genuinely
   exercises 3+ of the app's features in a way a *real person* would.
3. Decide which of the 10 hardness levers above will make this specific
   instance non-trivial. A consumer task is hard because of *combined
   constraints*, not because the domain is complex.
4. Frame the task in personal-use language (no "you are a professional",
   no audit-flavor, no JSON deliverable unless it's a sensible personal
   artifact).
5. Decide the output artifact in the app's native format.
6. Plan the verification spine around the artifact's structural properties
   + (where applicable) citation support, not "exact field == ground
   truth from professional standard".
