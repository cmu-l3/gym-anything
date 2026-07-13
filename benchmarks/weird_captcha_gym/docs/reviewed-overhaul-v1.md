# Reviewed Puzzle Overhaul v1

Date: 2026-07-12

Status: implementation contract

This cohort exists because human VNC review exposed a quality-gate failure that
scripted browser solves did not. The nine mechanics below must be rebuilt from
their interaction thesis rather than cosmetically patched. Their existing human
review decisions remain authoritative until the human reviewer explicitly
changes them.

The binding parent doctrine is
[`interaction-puzzle-field-notes.md`](interaction-puzzle-field-notes.md).

## Cohort-wide rejection tests

Reject a rebuild if any answer is recoverable from one perfect initial
screenshot, if visible copy names the winning control, if a final-state flag can
replace the claimed interaction, or if rendering and grading use different
geometry. Every accepted browser trajectory must use ordinary mouse/keyboard
input and must remain outside the human-approved and verified surfaces.

Each mechanic must additionally satisfy all of these:

- at least three meaningful observe-act-reobserve cycles;
- fresh seeded layouts and answer/state permutations;
- a stale-challenge negative and at least one mechanic-specific forgery;
- a dominant but terse terminal verdict;
- initial, active, solved, pass, and fail-refresh evidence;
- no answer text, progress explanation, tutorial, or solver telemetry on the
  normal surface;
- browser/server/exported-verifier agreement through one independent grader;
- a real 1280x720 interaction run before human VNC handoff.

## 1. Consequences Boss — covenant reconstruction

### Rejected form

Four labeled moral choices were followed by a screen that literally displayed
`YOU CHOSE`. The later protect/exploit mapping was universal and erased the
claimed episodic-memory burden.

### Replacement thesis

The player freely commits five physical covenants: for each scene, place a
scene-specific relic into one of two sockets and set a four-position seal. After
an occluding transition, the scenes return in a new order with no choice recap.
The player must reconstruct every earlier socket and seal state. There is no
universal answer because the player creates the answer during the episode.

The verifier binds all five initial commitments and all five later
reconstructions to the current challenge, rejects missing/duplicate scenes, and
requires exact delayed consistency. The UI must never render the stored choice
during reconstruction.

## 2. Popup Exorcist — provoke, identify, contain

### Rejected form

The winning popup was labeled `KILL SWITCH` and said that one click ended every
process.

### Replacement thesis

All windows initially look like ordinary junk. Closing normal windows removes
them. Closing the parasite makes it visibly corrupt and spawn echoes, worsening
the desktop. That failed action activates a previously inert containment glyph.
The player must identify an infected echo through its post-interaction behavior,
bring it to the front, and physically drag it into containment; only then does
the purge propagate through the remaining windows.

The grader replays close, spawn, focus, drag, containment, and purge events. It
rejects direct containment before provocation, containing a clean window,
fabricated echo IDs, or claiming a purge while any live window remains.

## 3. Slime Commute — deterministic continuous crossing physics

### Rejected form

Collision was checked only when a key moved the player into a destination cell.
Moving vehicles could pass through a stationary player, water support was not
checked continuously, and logs did not carry the player.

### Replacement thesis

Run the crossing on a fixed-step world clock. Cars and trains occupy continuous
wrapped intervals and collide every simulation tick. Water is lethal unless a
real moving log interval supports the slime; support carries the slime by the
log velocity and can carry it off the board. Keyboard hops remain discrete and
human-readable, while the world continues evolving between inputs.

The submitted transcript contains tick-bound key actions. The server independently
replays the same fixed-step world through every tick and checks collisions,
support, carrying, wipeouts, visited rows, and the final home position.

## 4. Semantic Drag-Drop Absurdity — causal probe laboratory

### Rejected form

Objects and destinations were labeled, and every destination printed the exact
semantic relation (`POWERS`, `REPAIRS`, and so on).

### Replacement thesis

Four visually ambiguous specimens have hidden two-axis material responses.
Thermal and polarity probes reveal short-lived physical reactions only while
the player operates them. Four unlabeled receivers demonstrate their required
response signatures through separate pulses. The player must experimentally
identify each specimen, remember the transient reactions, and drag it to the
matching receiver.

Initial appearance, receiver position, specimen position, and signature mapping
all vary. No nouns or relation words identify an answer. Outcome grading uses
the final one-to-one placement; probes are necessary because the signatures do
not otherwise exist on screen.

## 5. Reload Interruption — interrupted gesture memory

### Rejected form

The base task was six presses of one lever. Interruptions displayed a code to
copy, named the exact button to press, or showed a two-symbol answer beside the
answer buttons.

### Replacement thesis

A mechanical drum previews one seven-gesture reload sequence once, using only
animated lever motion. The player must reproduce it with directional pointer
drags. After the second and fifth accepted gestures, an overload takes over the
surface. Clearing it requires continuously tracking a moving spark under a held
pointer while the sequence remains hidden. The player then resumes from memory,
not from a progress/tutorial panel.

The grader validates the gesture sequence and independently recomputes every
tracking sample against the generated spark path, minimum continuous hold, and
maximum sample gaps. It rejects copied labels because no directional labels are
rendered during the preview.

## 6. Rotate the Wrong Thing Upright — tri-axis gimbal

### Rejected form

The task was a static cue plus literal `-15` and `+15` controls. Its answer was a
small integer number of clicks.

### Replacement thesis

The target mark is mounted inside three coupled gimbal rings and must be aligned
with a world plumb axis. The player can inspect front, side, and top projections,
but only one view is visible at a time. Each ring is adjusted by continuous
pointer dragging with no numeric angle display. Changes that improve one view
can disrupt another, requiring repeated spatial inspection and correction.

The grader independently reconstructs the final three-axis orientation from
bounded drag deltas and requires the projected target to agree with the plumb
axis in every view. It rejects direct final-angle payloads and unobserved jumps.

## 7. Bureaucratic Signature Trap — carbon-copy aperture stack

### Rejected form

The prompt named the exact tool and labeled field, and clicking anywhere in a
large rectangle placed a centered mark automatically.

### Replacement thesis

Three translucent form layers hide the original signature aperture. The player
must drag independent sheet tabs until their seal fragments and punched windows
coincide. Only the physical overlap exposes the signing surface. The player then
draws one continuous closed counter-signature through the aligned aperture.

The grader replays sheet drags, recomputes final layer geometry, and validates a
continuous bounded stroke with sufficient length and quadrant coverage. It
rejects teleporting a sheet, drawing through a closed stack, or submitting a
single click as a signature.

## 8. Wonky Text — anamorphic registration press

### Rejected form

A static distorted token was entered into a text box. It was ordinary OCR.

### Replacement thesis

The token is split across three independently warped print plates. It is not an
answer to type; it is visual alignment material. Drag three optical wheels to
register the moving layers until the glyph fragments form one stable plate,
then physically lock and press it. Each wheel has a nonlinear visible effect,
so the player must adjust, inspect, and correct rather than calculate a displayed
number.

The grader replays bounded wheel drags and checks all three final phases against
the generated registration state. It rejects direct phase assignment and a
press made before all plate locks were physically engaged.

## 9. First Change Memory — active transient tracking

### Rejected form

Five visible objects changed permanently in sequence. Waiting for the first
obvious change and clicking once was enough.

### Replacement thesis

Seven marked objects move, cross, and pass behind occluders. Their identity marks
are visible only inside a cursor-controlled inspection lens. A short perimeter
pulse indicates where the first transient change is about to occur; the player
must move the lens, follow the object through the event, remember its identity,
and later locate that identity after the objects settle in a new permutation.
The first change reverts, and later decoys change too, so the final frame contains
no answer.

The selected object is outcome-graded against fresh challenge truth. The normal
surface exposes neither the target ID nor the event schedule, and failure creates
a new motion/event permutation.

## Human handoff rule

Automated completion changes these mechanics only to
`revision rebuilt / human review pending`. It does not clear the review ledger,
mark them approved, or place them in `verified`. Human VNC review is the next
acceptance gate.
