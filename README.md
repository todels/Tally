# Tally

A menu bar time tracker for macOS that separates real work from time sinks.
Fully offline — no accounts, no servers, no network code anywhere in it.

## What it watches

- **The frontmost app**, via AppKit. Figma, Xcode, Terminal, whatever.
- **The front tab in Dia**, via a single Apple event. Only the *domain* is kept
  (`youtube.com`), never the full URL, path, or query string.
- **Idle time**, via the HID system. After 5 minutes without a keystroke or
  mouse move you're marked **Idle** — recorded as its own category, so away
  time is visible rather than being a hole in the data.

### The microphone exception

Sitting perfectly still on a call is not the same as being away. If anything is
using the input device, idle detection is suspended and the ceiling rises to two
hours — so a meeting counts, but Discord left open in a voice channel overnight
can't log a full night's "work".

This checks one CoreAudio boolean, `kAudioDevicePropertyDeviceIsRunningSomewhere`
— the same signal behind the orange dot in the menu bar. It opens no stream,
captures no audio, and needs no microphone permission.

### What is never recorded

Worth being exact, since a tracker could plausibly do all of this and doesn't:

| | |
|---|---|
| Keystrokes / typed text | **No.** The only input signal is *seconds since the last event* — one integer. No event tap, no key codes, no text. |
| Audio or speech | **No.** Only "is the device running", a boolean. |
| Mouse position or movement | **No.** Same single integer; coordinates are never read. |
| Screen contents / screenshots | **No.** No screen recording permission is requested. |
| Full URLs | **No.** The host is extracted and the path and query are discarded before anything is written. `youtube.com`, never the video. |

## When the Mac sleeps

The clock stops, and it stops at the right second — three independent
mechanisms, so no single failure can inflate your numbers:

1. **Power notifications.** macOS announces sleep, display-off, screen lock and
   fast user switching *before* they happen, so the open session is banked at
   that exact moment.
2. **A gap guard.** Every tick checks how long since the last one. More than 15
   seconds means the process wasn't running, so the session is closed at the
   last moment the machine was provably awake — never stretched across the gap.
   This catches sleep even if a notification is missed.
3. **Idle detection**, as the final backstop after 90 idle seconds.

The gap guard matters because of a specific trap: shutting the lid *immediately*
after typing leaves a session open with under 90 seconds of idle time. Without
it, that session would silently absorb the entire sleep — close the lid at 6pm,
open at 9am, and you'd have "worked" 15 hours in Figma.

App Nap is disabled for the poll loop (via `beginActivity`) so macOS can't
throttle it into looking like a sleep, but idle system sleep is still allowed —
the app never keeps your Mac awake.

Chrome, Arc, and Safari are deliberately never scripted. If you use them they
show up as plain apps with no site detail.

## Three buckets

| | |
|---|---|
| **Focus** | Figma, editors, terminals, design tools, github.com, linear.app … |
| **Drain** | youtube.com, x.com, reddit.com, instagram.com, netflix.com … |
| **Other** | Everything unclassified. Never guessed at silently. |

Click the coloured dot next to any row to move it between buckets. Because
categories are computed from rules at read time — never baked into the stored
data — reclassifying something **retroactively corrects your entire history**.

## Using it

Tally is two things sharing one engine:

- **The window** — a normal app with a Dock icon. Day / Week / Month tabs,
  arrows to step back through history, a stacked bar chart per day, and a
  ranked list of everything you touched. Closing the window does **not** stop
  tracking; it keeps running in the menu bar.
- **The menu bar item** — top-right of your screen, near the clock. Shows live
  focus time. Click it for today at a glance, or **Open Tally** for the window.

**To quit properly:** menu bar item → **Quit**, or `⌘Q` with the window focused.
Closing the window alone just hides it.

## Sharing it

### Send them the DMG

Every push to `main` is built by GitHub Actions and published at

> **https://github.com/todels/Tally/releases/latest**

Send that link. They download **Tally.dmg**, drag Tally to Applications, and
open it. From then on the **Update** button in the menu bar panel fetches each
new release — they never need to hear from you again.

**The one speed bump:** the first launch shows *"Apple could not verify Tally is
free of malware"*, because the app is signed ad-hoc rather than with a paid
Apple Developer identity. One-time fix, either of:

- **System Settings › Privacy & Security**, scroll down, **Open Anyway**.
- Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Tally.app`

`INSTALL.md` inside the DMG walks them through it. Updates don't hit this wall
again — they're fetched by `curl`, which doesn't attach the quarantine flag a
browser download does.

Then, on first run they'll get the usual macOS prompt to let Tally control
Dia — that one is a normal permission dialog, and declining it just means no
per-site breakdown.

### Or send them the repo

```bash
git clone https://github.com/todels/Tally.git
cd Tally && ./build.sh && open Tally.app
```

For anyone who wants to change things. Building locally skips the Gatekeeper
wall entirely, and the Update button does `git pull` + rebuild instead of
downloading. Needs the Swift toolchain (`xcode-select --install`, ~2 GB, no
Apple account).

### Making the warning go away properly

The only way to remove the first-launch step is an **Apple Developer Program**
membership ($99/year). With one:

```bash
DEVID="Developer ID Application: Your Name (TEAMID)" ./release.sh
xcrun notarytool submit Tally.zip --apple-id you@example.com \
  --team-id TEAMID --password APP_SPECIFIC_PASSWORD --wait
xcrun stapler staple Tally.app
```

That gets a clean double-click install on any Mac. Not worth it for a handful
of friends; worth it if you hand it to strangers.

## Build

```bash
./build.sh
open Tally.app
```

Drag `Tally.app` to `/Applications` to keep it. "Open at login" is in the
footer of the menu bar panel.

On first run macOS asks for permission to control Dia. That prompt is the
Apple-event access — if you miss it, the panel shows an **Allow Dia access**
button that jumps straight to the right settings pane.

## Updating

The footer of the menu bar panel has a **Check for updates** button; when
there's something new it becomes **Update**. One click installs it and
relaunches. Nothing is ever fetched or installed without that click.

How it gets the new version depends on how this copy was built:

| Built by | Stamped into Info.plist | Update does |
|---|---|---|
| `build.sh` (a checkout) | `TallySourceRepo` | `git pull --ff-only`, then `build.sh` |
| `release.sh` (the DMG) | `TallyBuild` + `TallyUpdateRepo` | `curl` the latest `Tally.zip` from GitHub Releases, verify its signature, swap the bundle in place |

Tally still contains no network code. It shells out to `git` or `curl` — both
already on every Mac, already signed by Apple — and never opens a socket
itself. Check any time:

```bash
nm -u Tally.app/Contents/MacOS/Tally | grep -i urlsession   # no output
```

**What you're trusting.** An installed copy runs whatever the latest release on
`TallyUpdateRepo` is. The download goes over HTTPS to github.com, so nobody in
between can swap the file; what's left is the GitHub account that owns the
repo. That's the same trust as cloning and building — it's just GitHub's
runner doing the compiling instead of you. Keep two-factor on that account.

If you fork this, change `TallyUpdateRepo` in `Resources/Info.plist` to your
own `owner/repo` and your copies will follow your releases instead.

## Your data

Plain newline-delimited JSON, one file per day:

```
~/Library/Application Support/Tally/
├── 2026-08-14.ndjson
└── rules.json
```

Readable with `cat`, greppable, and deletable a day at a time. The **Data**
button in the footer opens the folder.

```json
{"start":"2026-08-14T13:04:11Z","end":"2026-08-14T13:52:40Z","app":"Figma","bundleID":"com.figma.Desktop"}
```

## Layout

| File | |
|---|---|
| `Tracker.swift` | The 2-second poll loop, session building, idle handling |
| `DiaBridge.swift` | Talks to Dia; hard 3s timeout so it can't ever hang the UI |
| `Rules.swift` | Classification + defaults, longest-suffix domain matching |
| `Store.swift` | Append-only NDJSON, splits sessions across midnight |
| `Period.swift` | Day/week/month maths, history loading and caching |
| `DashboardView.swift` | The window |
| `ContentView.swift` | The menu bar panel |
| `Timeline.swift` | Builds the day's bars; merges slivers without bridging gaps |
| `Updater.swift` | The update button: `git`+`build.sh` for checkouts, `curl`+swap for releases; opens no sockets |
