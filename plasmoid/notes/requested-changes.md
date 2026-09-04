# Claude Sessions widget — requested changes

**Captured:** 2026-09-04, from Pedro, verbatim.
**Status:** none of these are implemented yet. The widget as committed alongside
this file is the first version, before any of the list below.

Written down because the request came in on a Friday on the work PC; the work
continues from the home PC.

Two screenshots referenced in the list are saved next to it:

- `images/panel-blue-blends-in.png` — item 2, the working-blue against the panel
  background.
- `images/browser-reload-icon.png` — item 5, the single-arrow reload icon to copy.

---

## The list, as given

> ohhhhh, already looks really nice brooo, amazing job!
> but there is a few things i'd like to ask you to add/do:
>
> before you do ANYTHING, move this list into a text file, commit and push it (as
> well as all of you're other changes and the entire widget system), as it is
> friday and i'm in my work pc, so i wont be finishing this on this PC, and will
> do it at home.

**1.** make it so the user can change the colors of each status on the widget
configuration/settings, can be on the general tab, make it so if the user
toggles/checks (whatever you choose, dont really care about which you use) the
"Customize status colors", 3 new entries appear bellow it, one for each status
with their respectfull color, which when clicked opens the color picker (if the
toggle/check is undone, it should use the default colors, not the last ones the
user had selected when the toggle/check was on).

**2.** after you add the option of the user changing the status colors, current
ones will become defaults. but i do want you to change the working default color,
as it blends in with my background making it hard to see (close up it is a bit
harder to see what i mean, but from further away i promise you the blue does
blend in with the background: `images/panel-blue-blends-in.png`), see what the
industry standard colors are for this type of thing and pick the first (or second
if blue is the first) most used one.

**3.** make it so the menu that opens up when the user clicks the widget gets
dynamically resized based on the ammount of sessions, make the current size the
max size, if there are more sessions than the max size can fit, a scrollbar
should appear so that the user can scroll to see the ones that didnt fit inside
the menu. also, make it so the max size can be customizable on the settings of
the widget, can also be in the general tab, and make the current size the default
one.

**4.** currently i dont see a reset button on the widget settings, if it is not a
button that should/usually appears in the bottom bar of the settings window, add
it as a button in the general settings at the very top, which resets all the
settings to the widget's defaults.

**5.** no idea about which icons you can choose to add to the widget menu, but
the current icon you picked for the refresh button doesnt really look like a
refresh button, it looks more like a restart/reset button. either try another one
that only has 1 arrow in the circle (like the browser's reload icon, it was right
in my face, too easy to send you as example to not do so:
`images/browser-reload-icon.png`), if you dont find another you're confident in
using, tell me how i can look at all the options and i'll pick one for you.

**6.** in the widget dropdown, change the title from "Claude Code" to "Claude
Code Sessions".

**7.** bellow the title, where you give the summary, make it so the numbers of
each status uses the status colors, so in "X working, Y done", the "X" would be
blue and "Y" would be green (you can keep the current behaviour where the whole
summary becomes the waiting color if one of the sessions is waiting for user
input).

**8.** pick a single color for the waiting status, on the widget it is orange,
and on the widget dropdown menu it is orange as well, but on the summary it is
yellow (turns yellow if a session is waiting for user input), use only one color
for all (both yellow and orange are good ones, see what is the most used industry
standard color for it and use it, just like you're going to do for the "working"
color) (this entry might be resolved bt the one bellow it, see for more details).

**9.** add another status for when an agent is waiting for a subagent, command or
script to finish running, no idea what it could be called as we're already using
"waiting" for when it is waiting for user input, but i think you'll figure it
out. the reason why this entry might solve entry number 8 is because maybe an
appropriete color for this status could be yellow, as it is waiting but doesnt
require human interaction, and orange is a color that represents a bit better the
need of human interaction (at least in my opinion), which would resolve the
conflict of choosing between yellow and orange.

**10.** not sure if you already added this status, but add one with the default
color red for sessions that stopped because of an error.

**11.** in the widget dropdown, add a button that sensors the names of sessions
and disables (makes invisible but of course doesnt actually delete forever) the
subtitle of the session entry, the one bellow the session title (as there would
only be the sensored title of each session and no "description", the title should
align with the vertical center of the session div/entry/slot.

**12.** currently when sessions are clicked they expand showing more details of
the session (looks amazing btw). make it so when the user clicks off (closes) the
widget dropdown/menu all of the session that ware expanded retract, so when the
widget is opened again all of the sessions are retracted.

**13.** add a new entry to the session details called "Repository", which
displays the git repository setup in the sessions directory. if there isnt any,
just disable/ommit (make invisible) this entry.

**14.** add a new entry to the session details called "Branch", which displays
the git repository's currently selected branch. if there isnt any, just
disable/ommit (make invisible) this entry.

**15.** make it so the following session details entries can be toggled/checked
to be enabled or disabled in the widget settings: "Version", "Session",
"Repository", "Branch", "Process".

**16.** make it so by default the "Branch" appears at the end of the "Repository"
session details entry (maybe like "repository/branch", do it the way you think is
best), but add the option in the widget settings for the user to make it use it's
dedicated session details entry (regardless of how it is being displayed, if the
user toggles the "Branch" session details entry off, it gets disabled/removed,
either from the end of the "Repository" entry, or it's dedicated entry gets
disabled/removed).

**17.** rename the session detail entry "Folder" to "Directory".

**18.** rename the session detail entry "Started" to "Uptime".

**19.** reorder the expanded session details like this: "Profile", "Uptime",
"Directory", "Repository", "Branch", "Session", "Process", "Version".

**20.** in the widget settings allow the user to check/toggle the option to use
"Dir" and "Repo" for the "Directory and "Repository" session details entries.

**21.** add a button that appears when the user hovers over a session of a pencil
that allows the user to rename the session. if it's not possible to make the
session rename get applied to the actual session in the claude code app without
either a session or terminal refresh/restart (user has to do it manually or might
interfer with user's work), make it so the rename is only applied to the session
in the widget (like giving it a nickname only in the widget).

**22.** make it so when the user right clicks a session, when it's details are
retracted a command to open it on a fresh terminal gets coppied to the user's
clipboard, and when right clicked with the session's details expanded the entire
session's details (title, description and all the session detail entries) get
coppied to the user's clipboard.

**23.** not sure it it is possible (if it isnt just skip over this one!), change
the hover color to a light graysh color instead of the blue, because when using
blue it kinda doesnt match wtih the thing colored after the session's current
status.

**24.** make it so when the session details are expanded, if the user left clicks
the entries "Directory", "Repository", "Branch", "Session", "Process" or
"Version" their value gets coppied to the user's clipboard.

**25.** not sure it it is possible (if it isnt just skip over this one!), add 2
buttons besides the session rename one, that also only appear when the session is
being hovered, one that kills that session completly (closes the claude code app
instance that had it opened in the terminal), and one that just stops/pauses
(this button should only appear if the session status is "Working") the session,
just like interrupting it but not fully closing it.

**26.** on the widget icon, currently the bars that represent each running
session have different heights based on their current status, make it so they're
all the same height independent of their current status.

**27.** make it so the color of the total number of sessions on the widget's icon
matches the color of the status that has the highest amount (feel free to just
like you do with the "Waiting" status, allow any other rule you might also want
to, take over the color of the number independed of there being more sessions of
another status).

**28.** make it so the user can disable and enable the total number of sessions
on the widget's icon in the widget settings.

**29.** !IF POSSIBLE! based on the current setup of the entire widget, add a
profile selector that contains the usage bar of that profile, the selector
shouldnt change anything else in the widget's behaviour or funcionality, it just
allows the user to select the profile he wants to display when the selector isnt
expanded (as when expaned it will show both profile's usage bar).

**30.** on this new profile selector, add a arrow pointing to the right on both
the selector entries (can be clicked even on the profile that isnt the currently
selected one), that opens a lil selector menu where the user can select between
the usage bar types (weekly limit, session limit or fable limit).

**31.** make this it's own repo, liked this so much i want it separate and
displayed on my linkdin, CV and github. this is the last entry on the list as i
imagine this is probably pretty tangled up with the Claude-Acc-Manager project,
and making that untanglement isnt top priority right now as i'm the only one
who's going to be using this, and i use both projects so it isnt an issue for me.

---

## Notes for picking this up

These are one-line pointers only — no decisions have been made, and nothing below
overrides the list above.

- **Items 9 and 10 need research before design.** The widget reads Claude Code's
  own session registry, whose `status` field is a closed set of four values
  (`busy`, `shell`, `idle`, `waiting`) — see
  `docs/superpowers/specs/2026-09-04-sessions-widget-design.md`. "Waiting on a
  subagent/command" and "stopped with an error" are not among them, so check
  whether the record carries them elsewhere (`tempo`, `state`, `detail`, `needs`
  are all in the schema and currently unused) before assuming a new source is
  needed.
- **Item 29** wants the usage bars from the abandoned design at
  `docs/superpowers/specs/2026-07-13-usage-plasmoid-design.md`, whose captured
  API response is kept at `docs/superpowers/specs/fixtures/usage-work.json`.
  That design was never built and its endpoint is undocumented — treat it as a
  starting point, not a spec.
- **Item 31** is the tidiest cut once the rest is done: `plasmoid/`, plus
  `tests/test-widget.fish`, plus the sessions-widget design doc, are the whole
  widget. Nothing outside `plasmoid/` is imported by it.
