#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Manuscript Import Cleanup Task ==="

install -d -o ga -g ga /home/ga/Documents
kill_calligra_processes
rm -f /home/ga/Documents/frankenstein_manuscript.odt

python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.style import Style, TextProperties, ParagraphProperties
from odf.text import P, H, Span

doc = OpenDocumentText()

# ============================================================
# Define automatic styles for correct formatting
# ============================================================

# --- Correct body style: 12pt, justified, standard font ---
body_style = Style(name="BodyCorrect", family="paragraph")
body_style.addElement(ParagraphProperties(textalign="justify"))
body_style.addElement(TextProperties(fontsize="12pt", fontname="Liberation Serif"))
doc.automaticstyles.addElement(body_style)

# --- Correct heading 1 style ---
heading1_style = Style(name="Heading1Correct", family="paragraph", parentstylename="Heading_20_1")
heading1_style.addElement(TextProperties(fontsize="18pt", fontweight="bold", fontname="Liberation Sans"))
doc.automaticstyles.addElement(heading1_style)

# --- Correct italic span style (for emphasis) ---
italic_span_style = Style(name="ItalicCorrect", family="text")
italic_span_style.addElement(TextProperties(fontstyle="italic"))
doc.automaticstyles.addElement(italic_span_style)

# ============================================================
# Define ERROR styles (deliberately wrong formatting)
# ============================================================

# --- Error: Heading 3 style (wrong level for some headings) ---
heading3_err_style = Style(name="Heading3Error", family="paragraph", parentstylename="Heading_20_3")
heading3_err_style.addElement(TextProperties(fontsize="14pt", fontweight="bold"))
doc.automaticstyles.addElement(heading3_err_style)

# --- Error: Heading 2 style (wrong level for Letter 4) ---
heading2_err_style = Style(name="Heading2Error", family="paragraph", parentstylename="Heading_20_2")
heading2_err_style.addElement(TextProperties(fontsize="16pt", fontweight="bold"))
doc.automaticstyles.addElement(heading2_err_style)

# --- Error: Plain paragraph styled to look like heading (for Letter 2) ---
fake_heading_style = Style(name="FakeHeadingError", family="paragraph")
fake_heading_style.addElement(TextProperties(fontsize="20pt", fontweight="bold", fontname="Liberation Sans"))
fake_heading_style.addElement(ParagraphProperties(textalign="center"))
doc.automaticstyles.addElement(fake_heading_style)

# --- Error: Wrong font (Comic Sans MS) ---
wrong_font_style = Style(name="WrongFontError", family="paragraph")
wrong_font_style.addElement(ParagraphProperties(textalign="justify"))
wrong_font_style.addElement(TextProperties(fontsize="12pt", fontname="Comic Sans MS"))
doc.automaticstyles.addElement(wrong_font_style)

# --- Error: Wrong alignment (centered instead of justified) ---
wrong_align_style = Style(name="WrongAlignError", family="paragraph")
wrong_align_style.addElement(ParagraphProperties(textalign="center"))
wrong_align_style.addElement(TextProperties(fontsize="12pt", fontname="Liberation Serif"))
doc.automaticstyles.addElement(wrong_align_style)

# --- Error: Bold span style (incorrectly applied) ---
bold_err_span_style = Style(name="BoldError", family="text")
bold_err_span_style.addElement(TextProperties(fontweight="bold"))
doc.automaticstyles.addElement(bold_err_span_style)


# ============================================================
# Helper functions
# ============================================================

def add_heading(text, style_name, outline_level):
    """Add a heading element with specified style and outline level."""
    h = H(outlinelevel=outline_level, stylename=style_name, text=text)
    doc.text.addElement(h)


def add_body_para(text, style_name="BodyCorrect"):
    """Add a body paragraph."""
    p = P(stylename=style_name, text=text)
    doc.text.addElement(p)


def add_body_para_with_bold_word(before, bold_word, after, style_name="BodyCorrect"):
    """Add a body paragraph with an incorrectly bolded word."""
    p = P(stylename=style_name)
    p.addText(before)
    span = Span(stylename="BoldError", text=bold_word)
    p.addElement(span)
    p.addText(after)
    doc.text.addElement(p)


def add_body_para_with_italic_phrase(before, italic_phrase, after, style_name="BodyCorrect"):
    """Add a body paragraph with a properly italicized phrase."""
    p = P(stylename=style_name)
    p.addText(before)
    span = Span(stylename="ItalicCorrect", text=italic_phrase)
    p.addElement(span)
    p.addText(after)
    doc.text.addElement(p)


def add_body_para_missing_italic(text, style_name="BodyCorrect"):
    """Add a body paragraph where italic phrases are NOT italicized (error)."""
    p = P(stylename=style_name, text=text)
    doc.text.addElement(p)


def add_empty():
    """Add an empty paragraph."""
    doc.text.addElement(P(stylename="BodyCorrect"))


# ============================================================
# Document content: Frankenstein manuscript with injected errors
# ============================================================

# ---- LETTER 1 ----
# ERROR: Heading 3 instead of Heading 1
add_heading("Letter 1", "Heading3Error", 3)

add_body_para("To Mrs. Saville, England")
add_body_para("St. Petersburgh, Dec. 11th, 17\u2014")
add_empty()

# ERROR: Wrong alignment (centered instead of justified)
add_body_para(
    "You will rejoice to hear that no disaster has accompanied the commencement "
    "of an enterprise which you have regarded with such evil forebodings. I arrived "
    "here yesterday, and my first task is to assure my dear sister of my welfare and "
    "increasing confidence in the success of my undertaking.",
    "WrongAlignError"
)

# ERROR: Wrong font (Comic Sans MS)
add_body_para(
    "I am already far north of London, and as I walk in the streets of Petersburgh, "
    "I feel a cold northern breeze play upon my cheeks, which braces my nerves and "
    "fills me with delight. Do you understand this feeling? This breeze, which has "
    "travelled from the regions towards which I am advancing, gives me a foretaste "
    "of those icy climes.",
    "WrongFontError"
)

add_body_para(
    "I try in vain to be persuaded that the pole is the seat of frost and desolation; "
    "it ever presents itself to my imagination as the region of beauty and delight. "
    "There, Margaret Saville, the sun is for ever visible, its broad disk just skirting "
    "the horizon and diffusing a perpetual splendour."
)

# ERROR: should_be_italic "paradise of my own creation" is NOT italic
add_body_para_missing_italic(
    "There\u2014for with your leave, my sister, I will put some trust in preceding "
    "navigators\u2014there snow and frost are banished; and, sailing over a calm sea, "
    "we may be wafted to a land surpassing in wonders and in beauty every region "
    "hitherto discovered on the habitable globe. Its productions and features may be "
    "without example, as the phenomena of the heavenly bodies undoubtedly are in those "
    "undiscovered solitudes. What may not be expected in a country of eternal light? "
    "I may there discover the wondrous power which attracts the needle and may regulate "
    "a thousand celestial observations that require only this voyage to render their "
    "seeming eccentricities consistent for ever. I shall satiate my ardent curiosity "
    "with the sight of a part of the world never before visited, and may tread a land "
    "never before imprinted by the foot of man. These are my enticements, and they are "
    "sufficient to conquer all fear of danger or death and to induce me to commence this "
    "laborious voyage with the joy a child feels when he embarks in a little boat with "
    "his holiday mates on an expedition of discovery up his native river. But supposing "
    "all these conjectures to be false, you cannot contest the inestimable benefit which "
    "I shall confer on all mankind, to the last generation, by discovering a passage "
    "near the pole to those countries, to reach which at present so many months are "
    "requisite; or by ascertaining the secret of the magnet, which, if at all possible, "
    "can only be effected by an undertaking such as mine. I had a paradise of my own creation."
)

add_empty()

# ---- LETTER 2 ----
# ERROR: Plain paragraph with big font instead of Heading 1
add_body_para("Letter 2", "FakeHeadingError")

add_body_para("To Mrs. Saville, England")
add_body_para("Archangel, 28th March, 17\u2014")
add_empty()

# ERROR: Wrong alignment (centered instead of justified)
add_body_para(
    "This expedition has been the favourite dream of my early years. I have read with "
    "ardour the accounts of the various voyages which have been made in the prospect of "
    "arriving at the North Pacific Ocean through the seas which surround the pole.",
    "WrongAlignError"
)

# ERROR: Wrong font (Comic Sans MS)
add_body_para(
    "But it is a still greater evil to me that I am self-educated: for the first "
    "fourteen years of my life I ran wild on a common and read nothing but our Uncle "
    "Thomas's books of voyages. At that age I became acquainted with the celebrated "
    "poets of our own country; but it was only when it had ceased to be in my power "
    "to derive its most important benefits from such a conviction that I perceived "
    "the necessity of becoming acquainted with more languages than that of my native country.",
    "WrongFontError"
)

# ERROR: Wrong font (Comic Sans MS); also should_be_italic "Ancient Mariner" is NOT italic;
# also contains incorrectly bolded "supernatural"
p = P(stylename="WrongFontError")
p.addText(
    "I shall certainly find no friend on the wide ocean, nor even here in Archangel, "
    "among merchants and seamen. Yet some feelings, unallied to the dross of human "
    "nature, beat even in these rugged bosoms. My lieutenant, for instance, is a man "
    "of wonderful courage and enterprise; he is madly desirous of glory, or rather, "
    "to word my phrase more characteristically, of advancement in his profession. He is "
    "an Englishman, and in the midst of national and professional prejudices, unsoftened "
    "by cultivation, retains some of the noblest endowments of humanity. I first became "
    "acquainted with him on board a whale vessel; finding that he was unemployed in this "
    "city, I easily engaged him to assist in my enterprise. The master is a person of "
    "an excellent disposition and is remarkable in the ship for his gentleness and the "
    "mildness of his discipline. This circumstance, added to his well-known integrity "
    "and dauntless courage, made me very desirous to engage him. I feel a love for the "
    "marvellous, a belief in the marvellous, intertwined in all my projects, which "
    "hurries me out of the common pathways of men, even to the wild sea and unvisited "
    "regions I am about to explore. I am practically industrious and have avoided the "
    "Ancient Mariner and its "
)
bold_span = Span(stylename="BoldError", text="supernatural")
p.addElement(bold_span)
p.addText(" terrors to devote myself to the more rational study of mathematics.")
doc.text.addElement(p)

add_empty()

# ---- LETTER 3 ----
# CORRECT: Heading 1 (this one is right, to make it non-trivial)
add_heading("Letter 3", "Heading1Correct", 1)

add_body_para("To Mrs. Saville, England")
add_body_para("July 7th, 17\u2014")
add_empty()

add_body_para(
    "My dear Sister, I write a few lines in haste to say that I am safe\u2014and well "
    "advanced on my voyage. This letter will reach England by a merchantman now on its "
    "homeward voyage from Archangel; more fortunate than I, who may not see my native "
    "land, perhaps, for many years. I am, however, in good spirits: my men are bold and "
    "apparently firm of purpose, nor do the floating sheets of ice that continually pass "
    "us, indicating the dangers of the region towards which we are advancing, appear to "
    "dismay them. We have already reached a very high latitude; but it is the height of "
    "summer, and although not so warm as in England, the southern gales, which blow us "
    "speedily towards those shores which I so ardently desire to attain, breathe a degree "
    "of renovating warmth which I had not expected."
)

# ERROR: should_be_italic "what can stop the determined heart" is NOT italic
add_body_para_missing_italic(
    "No incidents have hitherto befallen us that would make a figure in a letter. One or "
    "two stiff gales and the springing of a leak are accidents which experienced navigators "
    "scarcely remember to record, and I shall be well content if nothing worse happen to "
    "us during our voyage. Adieu, my dear Margaret. Be assured that for my own sake, as "
    "well as yours, I will not rashly encounter danger. I will be cool, persevering, and "
    "prudent. But success shall crown my endeavours. Wherefore not? Thus far I have gone, "
    "tracing a secure way over the pathless seas, the very stars themselves being witnesses "
    "and testimonies of my triumph. Why not still proceed over the untamed yet obedient "
    "element? What can stop the determined heart and resolved will of man? But what can "
    "stop the determined heart when it is set upon its course?"
)

add_empty()

# ---- LETTER 4 ----
# ERROR: Heading 2 instead of Heading 1
add_heading("Letter 4", "Heading2Error", 2)

add_body_para("To Mrs. Saville, England")
add_body_para("August 5th, 17\u2014")
add_empty()

# ERROR: Wrong alignment (centered instead of justified)
add_body_para(
    "There is something at work in my soul which I do not understand. I am practically "
    "industrious\u2014painstaking, a workman to execute with perseverance and labour\u2014but "
    "besides this there is a love for the marvellous, a belief in the marvellous, "
    "intertwined in all my projects, which hurries me out of the common pathways of men, "
    "even to the wild sea and unvisited regions I am about to explore.",
    "WrongAlignError"
)

# ERROR: Wrong font (Comic Sans MS); also has incorrectly bolded "electricity"
p = P(stylename="WrongFontError")
p.addText(
    "Last Monday I was invited to dine with a gentleman of rank in this city, and there "
    "I met a young man of extraordinary talents. He had been educated at one of the best "
    "universities, and his knowledge of mathematics and natural philosophy was profound. "
    "We spoke at length about the wonders of the northern passages and the prospects of "
    "our expedition. He expressed great enthusiasm for the study of "
)
bold_span2 = Span(stylename="BoldError", text="electricity")
p.addElement(bold_span2)
p.addText(
    " and galvanism, and he believed that such forces might one day be harnessed to "
    "achieve feats beyond the imagination of our present age. I was struck by his "
    "conviction and the fire in his eyes as he spoke of the secrets yet to be unlocked "
    "by diligent inquiry and bold experimentation."
)
doc.text.addElement(p)

add_empty()

# ---- CHAPTER 1 ----
# ERROR: Heading 3 instead of Heading 1
add_heading("Chapter 1", "Heading3Error", 3)

add_body_para(
    "I am by birth a Genevese, and my family is one of the most distinguished of that "
    "republic. My ancestors had been for many years counsellors and syndics, and my father "
    "had filled several public situations with honour and reputation. He was respected by "
    "all who knew him for his integrity and indefatigable attention to public business. "
    "He passed his younger days perpetually occupied by the affairs of his country; a "
    "variety of circumstances had prevented his marrying early, nor was it until the "
    "decline of life that he became a husband and the father of a family."
)

add_body_para(
    "As the circumstances of his marriage illustrate his character, I cannot refrain from "
    "relating them. One of his most intimate friends was a merchant who, from a flourishing "
    "state, fell, through numerous mischances, into poverty. This man, whose name was "
    "Beaufort, was of a proud and unbending disposition and could not bear to live in "
    "poverty and oblivion in the same country where he had formerly been distinguished for "
    "his rank and magnificence. Having paid his debts, therefore, in the most honourable "
    "manner, he retreated with his daughter to the town of Lucerne, where he lived unknown "
    "and in wretchedness."
)

# ERROR: should_be_italic "Prometheus" is NOT italic; has incorrectly bolded "magnetism"
p = P(stylename="BodyCorrect")
p.addText(
    "My mother's tender caresses and my father's smile of benevolent pleasure while "
    "regarding me are my first recollections. I was their plaything and their idol, and "
    "something better\u2014their child, the innocent and helpless creature bestowed on them "
    "by heaven, whom to bring up to good, and whose future lot it was in their hands to "
    "direct to happiness or misery, according as they fulfilled their duties towards me. "
    "With this deep consciousness of what they owed towards the being to which they had "
    "given life, added to the active spirit of tenderness that animated both, it may be "
    "imagined that while during every hour of my infant life I received a lesson of "
    "patience, of charity, and of self-control, I was so guided by a silken cord that all "
    "seemed but one train of enjoyment to me. For a long time I was their only care. My "
    "mother had much desired to have a daughter, but I continued their single offspring. "
    "We explored the natural philosophy of Prometheus and its connection to "
)
bold_span3 = Span(stylename="BoldError", text="magnetism")
p.addElement(bold_span3)
p.addText(" in the modern world.")
doc.text.addElement(p)

add_empty()

# ---- CHAPTER 2 ----
# CORRECT: Heading 1 (this one is right, to make it non-trivial)
add_heading("Chapter 2", "Heading1Correct", 1)

add_body_para(
    "We were brought up together; there was not quite a year difference in our ages. I "
    "need not say that we were strangers to any species of disunion or dispute. Harmony "
    "was the soul of our companionship, and the diversity and contrast that subsisted in "
    "our characters drew us nearer together."
)

# ERROR: should_be_italic "tabula rasa" is NOT italic
add_body_para_missing_italic(
    "My education was neglected, yet I was passionately fond of reading. These volumes "
    "were my study day and night, and my familiarity with them increased that regret which "
    "I had felt, as a child, on learning that my father's dying injunction had forbidden "
    "my uncle to allow me to embark in a seafaring life. These visions faded when I "
    "perused, for the first time, those poets whose effusions entranced my soul and "
    "lifted it to heaven. I also became a poet and for one year lived in a tabula rasa "
    "of my own making. The change was wrought by a most beautiful influence."
)

add_body_para(
    "When I was thirteen years of age we all went on a party of pleasure to the baths "
    "near Thonon; the inclemency of the weather obliged us to remain a day confined to "
    "the inn. In this house I chanced to find a volume of the works of Cornelius Agrippa. "
    "I opened it with apathy; the theory which he attempts to demonstrate and the "
    "wonderful facts which he relates soon changed this feeling into enthusiasm. A new "
    "light seemed to dawn upon my mind, and, bounding with joy, I communicated my "
    "discovery to my father."
)

add_body_para(
    "My father looked carelessly at the title page of my book and said, 'Ah! Cornelius "
    "Agrippa! My dear Victor, do not waste your time upon this; it is sad trash.' If, "
    "instead of this remark, my father had taken the pains to explain to me that the "
    "principles of Agrippa had been entirely exploded and that a modern system of science "
    "had been introduced which possessed much greater powers than the ancient, because the "
    "powers of the latter were chimerical, while those of the former were real and "
    "practical, I should certainly have thrown Agrippa aside. It is even possible that the "
    "train of my ideas would never have received the fatal impulse that led to my ruin. "
    "But the cursory glance my father had taken of my volume by no means assured me that "
    "he was acquainted with its contents, and I continued to read with the greatest avidity."
)

add_body_para(
    "When I returned home my first care was to procure the whole works of this author, "
    "and afterwards of Paracelsus and Albertus Magnus. I read and studied the wild fancies "
    "of these writers with delight; they appeared to me treasures known to few besides "
    "myself. My father was not scientific, and I was left to struggle with a child's "
    "blindness, added to a student's thirst for knowledge. Under the guidance of my new "
    "preceptors I entered with the greatest diligence into the search of the philosopher's "
    "stone and the elixir of life; but the latter soon obtained my undivided attention. "
    "Wealth was an inferior object, but what glory would attend the discovery if I could "
    "banish disease from the human frame and render man invulnerable to any but a violent "
    "death! Nor were these my only visions. The raising of ghosts or devils was a promise "
    "liberally accorded by my favourite authors, the fulfilment of which I most eagerly "
    "sought; and if my incantations were always unsuccessful, I attributed the failure "
    "rather to my own inexperience and mistake than to a want of skill or fidelity in "
    "my instructors. And thus for a time I was occupied by exploded systems, mingling, "
    "like an unadept, a thousand contradictory theories and floundering desperately in a "
    "very slough of multifarious knowledge, guided by an ardent imagination and childish "
    "reasoning, till an accident again changed the current of my ideas."
)

doc.save("/home/ga/Documents/frankenstein_manuscript.odt", False)
print("Created frankenstein_manuscript.odt with deliberate formatting errors")
PYEOF

chown ga:ga /home/ga/Documents/frankenstein_manuscript.odt
chmod 0664 /home/ga/Documents/frankenstein_manuscript.odt

echo "Launching Calligra Words..."
launch_calligra_document "/home/ga/Documents/frankenstein_manuscript.odt" "/tmp/calligra_words_task.log"

if ! wait_for_process "/usr/bin/calligrawords" 20; then
    wait_for_process "calligrawords" 15 || true
fi

if ! wait_for_window "Calligra Words\\|frankenstein_manuscript" 60; then
    echo "ERROR: Calligra Words window did not appear"
    cat /tmp/calligra_words_task.log || true
fi

wid=$(get_calligra_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid" || true
    safe_xdotool ga :1 key Escape || true
    sleep 0.5
    safe_xdotool ga :1 key ctrl+Home || true
fi

take_screenshot /tmp/calligra_manuscript_import_cleanup_setup.png

echo "=== Manuscript Import Cleanup Task Setup Complete ==="
