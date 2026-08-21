# Tally

A time tracker that separates real work from doomscrolling. Everything it
records stays on your Mac — the app has no network code in it at all. The only
time anything is fetched is when *you* click **Update**, and that uses the
`curl` already on your Mac to grab the new version from GitHub.

Apple silicon (M1 or newer), macOS 14+.

---

## Install

1. Drag **Tally.app** onto the **Applications** folder next to it.

2. Open **Terminal** and paste this, then hit return:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Tally.app
   ```

3. Open Tally from Applications.

**Why step 2?** The app is signed, just not by a *paid* Apple developer account,
so macOS shows "Apple could not verify this app is free of malware" and refuses
to open it. That line clears the download flag. Skip it and you'll have to go to
System Settings › Privacy & Security › **Open Anyway** instead — same result,
more clicking. You only ever do this once — updates don't trigger it.

---

## Staying up to date

Click the menu bar icon. The footer has **Check for updates**; when there's a
new version it turns into **Update**. Click it and Tally fetches the new build,
swaps itself out, and relaunches. That's the whole process.

---

## What you'll see

- **A window** — Day / Week / Month, with a 24-hour timeline of your day. Hover
  any bar to see what you were doing and for how long.
- **A menu bar icon** near your clock showing today's focus time. Click it for a
  quick summary.

Closing the window does **not** quit it — it keeps tracking in the background.
To actually quit: `⌘Q`, or the **Quit** button in the menu bar panel.

Turn on **Open at login** in the menu bar panel and you can forget about it.

## Sorting your own apps

Everything unrecognised starts as **Other** — it never guesses. Click the
coloured dot next to anything in the list to move it between **Focus**, **Drain**
and **Other**. That rewrites your whole history, not just today, so it's worth
doing once early.

The big number on the window is a **pinned app** — Figma by default. Any row's
dot menu has "Show as headline" if you'd rather track something else.

## If you use the Dia browser

macOS will ask whether Tally can control Dia. Say yes — that's how it tells
`figma.com` from `youtube.com`. Only the **domain** is ever stored, never the
full address or the page.

Decline and it still works fine, you just get one lumped "Dia" row instead of a
per-site breakdown.

Chrome, Arc and Safari are never read, deliberately.

## What it records

Only whether you were active, never what you did:

- **Not** your keystrokes or anything you type — it reads one number, *seconds
  since your last input*, and nothing else.
- **Not** audio. It checks a single yes/no "is the mic on" flag (so meetings
  don't count as idle), and never opens the microphone.
- **Not** your mouse position, your screen, or full URLs.

## Your data

`~/Library/Application Support/Tally/` — one plain text file per day. Readable,
greppable, and deletable a day at a time. The **Data** button in the menu bar
panel opens the folder.
