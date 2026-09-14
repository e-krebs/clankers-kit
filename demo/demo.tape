# clankers-kit setup demo.
# Regenerate with:  vhs demo/demo.tape   (run from the repo root)
#
# The hidden block copies the repo into an isolated sandbox and points HOME at a throwaway
# dir, so recording never touches a real ~/.claude and no personal paths appear on screen. It
# also drops the AGENTS.md a fork already has, so the AGENTS.md questions show as on a first run.
# The run names its agents (so the agents question, asked only when none is on PATH, never
# shows), skips the privacy step (the copy has no remote) and the upstream skill (a network
# install), so the recording is deterministic and offline. The tools on PATH still decide which
# rows and prompts appear (the MCP row needs claude and npx, the interview offer needs claude),
# so the key presses below assume every required tool is present.

Output assets/setup-demo.gif

Require bash
Require git
Require jq
Require claude
Require npx
Require gh

Set Shell "bash"
Set FontSize 18
Set Width 1200
Set Height 1280
Set Padding 24
Set Theme "Dracula"

Hide
Type 'rm -rf /tmp/clankers-demo && mkdir -p /tmp/clankers-demo/home /tmp/clankers-demo/clankers-kit'
Enter
Type 'cp -R "$PWD/." /tmp/clankers-demo/clankers-kit && rm -rf /tmp/clankers-demo/clankers-kit/.git'
Enter
Type 'rm -f /tmp/clankers-demo/clankers-kit/.agents/AGENTS.md'
Enter
Type 'export HOME=/tmp/clankers-demo/home'
Enter
Type 'export PS1="$ "'
Enter
Type 'cd /tmp/clankers-demo/clankers-kit && clear'
Enter
Show

Sleep 800ms
Type "./setup.sh --agents claude,codex --no-private --without writing-for-agents --name 'Ada Lovelace' --role 'Staff frontend engineer'"
Sleep 600ms
Enter
Sleep 1800ms

# One grouped picker — an arrow-key checklist with section headers and a live detail pane.
# The cursor starts on the locked core row: space on it shows the "stays on" note.
Space
Sleep 1200ms
# Arrow through the layout, instructions and style rows so the descriptions are visible.
Down
Sleep 900ms
Down
Sleep 900ms
Down
Sleep 900ms
Down
Sleep 900ms
Down
Sleep 900ms
Down
Sleep 900ms
# chrome-devtools MCP — uncheck it.
Down
Sleep 900ms
Space
Sleep 1000ms
# workflow-profile — try to uncheck it: write-plan requires it, so the note says "kept".
Down
Sleep 900ms
Space
Sleep 1500ms
# Down the workflow skills to show the descriptions; pr-merge and rebase-branch also show
# their "Works better with" edges.
Down
Sleep 1200ms
Down
Sleep 1200ms
Down
Sleep 1000ms
Down
Sleep 1000ms
Down
Sleep 1000ms
Down
Sleep 1600ms
Down
Sleep 1600ms
Enter
Sleep 1500ms

# AGENTS.md — name and role came from the flags. "let Claude interview you ...? [y/N]" — decline,
# to show the scripted questions (accepting would launch a live, non-deterministic Claude session).
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

# The recap prints — every link, preset, skill and hook it will wire. Pause to read it, then Proceed.
Sleep 3000ms
Enter
Sleep 5s
