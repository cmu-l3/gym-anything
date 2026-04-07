#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Print-on-Demand Manuscript Typesetting Task ==="

install -d -o ga -g ga /home/ga/Documents
kill_calligra_processes
rm -f /home/ga/Documents/yellow_wallpaper_manuscript.odt

# ------------------------------------------------------------------
# Create the raw manuscript using odfpy
# All content is plain P elements in default US Letter (which is the odfpy default)
# ------------------------------------------------------------------
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentText
from odf.text import P

doc = OpenDocumentText()

def add_paragraph(text=""):
    doc.text.addElement(P(text=text))

# Title page elements
add_paragraph("THE YELLOW WALLPAPER")
add_paragraph("By Charlotte Perkins Gilman")
add_paragraph("")

# Section I
add_paragraph("I.")
add_paragraph("It is very seldom that mere ordinary people like John and myself secure ancestral halls for the summer.")
add_paragraph("A colonial mansion, a hereditary estate, I would say a haunted house, and reach the height of romantic felicity—but that would be asking too much of fate!")
add_paragraph("Still I will proudly declare that there is something queer about it.")
add_paragraph("Else, why should it be let so cheaply? And why have stood so long untenanted?")
add_paragraph("John laughs at me, of course, but one expects that in marriage.")
add_paragraph("John is practical in the extreme. He has no patience with faith, an intense horror of superstition, and he scoffs openly at any talk of things not to be felt and seen and put down in figures.")
add_paragraph("John is a physician, and perhaps—(I would not say it to a living soul, of course, but this is dead paper and a great relief to my mind)—perhaps that is one reason I do not get well faster.")
add_paragraph("You see he does not believe I am sick! And what can one do?")
add_paragraph("If a physician of high standing, and one's own husband, assures friends and relatives that there is really nothing the matter with one but temporary nervous depression—a slight hysterical tendency—what is one to do?")
add_paragraph("So I take phosphates or phosphites—whichever it is, and tonics, and journeys, and air, and exercise, and am absolutely forbidden to \"work\" until I am well again.")
add_paragraph("Personally, I disagree with their ideas.")
add_paragraph("Personally, I believe that congenial work, with excitement and change, would do me good.")
add_paragraph("But what is one to do?")
add_paragraph("")

# Section II
add_paragraph("II.")
add_paragraph("We have been here two weeks, and I haven't felt like writing before, since that first day.")
add_paragraph("I am sitting by the window now, up in this atrocious nursery, and there is nothing to hinder my writing as much as I please, save lack of strength.")
add_paragraph("John is away all day, and even some nights when his cases are serious. I am glad my case is not serious!")
add_paragraph("But these nervous troubles are dreadfully depressing.")
add_paragraph("John does not know how much I really suffer. He knows there is no reason to suffer, and that satisfies him.")
add_paragraph("Of course it is only nervousness. It does weigh on me so not to do my duty in any way!")
add_paragraph("I meant to be such a help to John, such a real rest and comfort, and here I am a comparative burden already!")
add_paragraph("Nobody would believe what an effort it is to do what little I am able,—to dress and entertain, and order things.")
add_paragraph("It is fortunate Mary is so good with the baby. Such a dear baby!")
add_paragraph("And yet I cannot be with him, it makes me so nervous.")
add_paragraph("I suppose John never was nervous in his life. He laughs at me so about this wall-paper!")
add_paragraph("At first he meant to repaper the room, but afterwards he said that I was letting it get the better of me, and that nothing was worse for a nervous patient than to give way to such fancies.")
add_paragraph("")

# Section III
add_paragraph("III.")
add_paragraph("John went away for the day, and even the night. He has a serious case in town.")
add_paragraph("I have kept on creeping just the same, but I have locked the door.")
add_paragraph("I don't want to go out, and I don't want to have anybody come in, till John comes.")
add_paragraph("I want to astonish him.")
add_paragraph("I've got a rope up here that even Jennie did not find. If that woman does get out, and tries to get away, I can tie her!")
add_paragraph("But I forgot I could not reach far without anything to stand on!")
add_paragraph("This bed will not move!")
add_paragraph("I tried to lift and push it until I was lame, and then I got so angry I bit off a little piece at one corner—but it hurt my teeth.")
add_paragraph("Then I peeled off all the paper I could reach standing on the floor. It sticks horribly and the pattern just enjoys it! All those strangled heads and bulbous eyes and waddling fungus growths just shriek with derision!")
add_paragraph("I am getting angry enough to do something desperate. To jump out of the window would be admirable exercise, but the bars are too strong even to try.")
add_paragraph("")

# Section IV
add_paragraph("IV.")
add_paragraph("Besides I wouldn't do it. Of course not. I know well enough that a step like that is improper and might be misconstrued.")
add_paragraph("I don't like to look out of the windows even—there are so many of those creeping women, and they creep so fast.")
add_paragraph("I wonder if they all come out of that wall-paper as I did?")
add_paragraph("But I am securely fastened now by my well-hidden rope—you don't get me out in the road there!")
add_paragraph("I suppose I shall have to get back behind the pattern when it comes night, and that is hard!")
add_paragraph("It is so pleasant to be out in this great room and creep around as I please!")
add_paragraph("")

# Section V
add_paragraph("V.")
add_paragraph("I don't want to go outside. I won't, even if Jennie asks me to.")
add_paragraph("For outside you have to creep on the ground, and everything is green instead of yellow.")
add_paragraph("But here I can creep smoothly on the floor, and my shoulder just fits in that long smooch around the wall, so I cannot lose my way.")
add_paragraph("Why there's John at the door!")
add_paragraph("It is no use, young man, you can't open it!")
add_paragraph("How he does call and pound!")
add_paragraph("Now he's crying for an axe.")
add_paragraph("It would be a shame to break down that beautiful door!")
add_paragraph("\"John dear!\" said I in the gentlest voice, \"the key is down by the front steps, under a plantain leaf!\"")
add_paragraph("That silenced him for a few moments.")
add_paragraph("Then he said—very quietly indeed, \"Open the door, my darling!\"")
add_paragraph("\"I can't,\" said I. \"The key is down by the front door under a plantain leaf!\"")
add_paragraph("And then I said it again, several times, very gently and slowly, and said it so often that he had to go and see, and he got it of course, and came in. He stopped short by the door.")
add_paragraph("\"What is the matter?\" he cried. \"For God's sake, what are you doing!\"")
add_paragraph("I kept on creeping just the same, but I looked at him over my shoulder.")
add_paragraph("\"I've got out at last,\" said I, \"in spite of you and Jane. And I've pulled off most of the paper, so you can't put me back!\"")
add_paragraph("Now why should that man have fainted? But he did, and right across my path by the wall, so that I had to creep over him every time!")

doc.save("/home/ga/Documents/yellow_wallpaper_manuscript.odt")
PYEOF

chown ga:ga /home/ga/Documents/yellow_wallpaper_manuscript.odt
date +%s > /tmp/task_start_time.txt

# Launch Calligra Words with the document
launch_calligra_document "/home/ga/Documents/yellow_wallpaper_manuscript.odt"
wait_for_window "Calligra Words" 30

# Maximize the window for the agent
WID=$(get_calligra_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Dismiss potential recovery/startup dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
fi

# Take an initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="