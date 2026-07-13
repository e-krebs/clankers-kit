# clankers-kit setup demo.
# Regenerate with:  vhs demo/demo.tape   (run from the repo root)
#
# The hidden block copies the repo into an isolated sandbox and points HOME at a throwaway
# dir, so recording never touches a real ~/.claude and no personal paths appear on screen.

Output assets/setup-demo.gif

Require bash

Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 940
Set Padding 24
Set Theme "Dracula"

Hide
Type 'rm -rf /tmp/clankers-demo && mkdir -p /tmp/clankers-demo/home /tmp/clankers-demo/clankers-kit'
Enter
Type 'cp -R "$PWD/." /tmp/clankers-demo/clankers-kit && rm -rf /tmp/clankers-demo/clankers-kit/.git'
Enter
Type 'export HOME=/tmp/clankers-demo/home'
Enter
Type 'export PS1="$ "'
Enter
Type 'cd /tmp/clankers-demo/clankers-kit && clear'
Enter
Show

Sleep 800ms
Type "./setup.sh --name 'Ada Lovelace' --role 'Staff frontend engineer'"
Sleep 600ms
Enter
Sleep 1800ms

# "let Claude interview you and draft the whole file? [y/N]" — decline, to show the scripted
# questions (accepting would launch a live, non-deterministic Claude session).
Type "n"
Enter
Sleep 1000ms
# Each scripted question offers a sensible placeholder default — press enter to accept it.
Enter
Sleep 800ms
Enter
Sleep 800ms
Enter
Sleep 1500ms

# Settings presets — an arrow-key checklist with a live detail pane.
Space
Sleep 900ms
Down
Sleep 700ms
Space
Sleep 900ms
Down
Sleep 900ms
Down
Sleep 900ms
Up
Sleep 700ms
Enter
Sleep 1500ms

# Skills — the same arrow-key checklist, now showing each skill's real description in the
# detail pane. Arrow through a few so the descriptions are visible, then select a couple.
Sleep 1000ms
Down
Sleep 1600ms
Down
Sleep 1600ms
Space
Sleep 1000ms
Down
Sleep 1600ms
Down
Sleep 1600ms
Space
Sleep 1200ms
Enter
Sleep 1500ms

# The recap prints — now listing the chosen skills with a count. Pause to read it, then Proceed.
Sleep 2500ms
Enter
Sleep 5s
