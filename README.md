# Omarchy Pets

A pixel-art companion for your Hyprland desktop. It is your **notification
center** (an animated stack of tooltip-style cards next to the pet), it
**thinks out loud** about what matters — which agent just finished, which one
needs you, which process is eating your CPU or memory — it mirrors your
**AI coding agents** (Claude Code, Codex), reflects **machine health**, and
doubles as the **screensaver**. It runs inside the Omarchy shell (Quickshell):
no extra daemon, no Electron, a few milliseconds of work every few seconds.

It uses the **Codex Pets** sprite format, so any of Codex's built-in pets or the
600+ community pets work as-is. The default is Rocky, "a steady rock when the
diff gets large".

> Codex shows its pets on the desktop only on macOS. This is the Linux version
> Codex doesn't ship — native to Hyprland, and it also knows about Claude Code.

## What it does

| State | When | Rocky |
|---|---|---|
| **Needs you** | An agent asks for permission or input (Claude Code hook `Notification`, or a "waiting for your input" notification) | Jumps once, then stands still looking at you |
| **Weak** | Battery ≤ 15 % and discharging | Lies down |
| **Tired** | CPU ≥ 85 %, package > 85 °C, memory ≥ 92 % (for 20 s) or thermal throttling | Sweating, slumped — and thinks *who* is responsible ("CPU at 100% — chrome takes 96%") |
| **Working** | Any agent is in a turn (hooks), or its transcript was written in the last 8 s (no hooks needed) | Types on a tiny laptop |
| **Ready** | An agent finished and you haven't come back (fades after 10 min) | Holds the result, happy |
| **Hungry** | Any weekly usage limit ≥ 90 % (from the Omarchy agents widget data) | Sagging, slow |
| **Asleep** | Session idle > 2 min | Eyes closed, a "z" — every timer stops, zero CPU |
| **Resting** | Nothing pending | Looks toward your cursor (left / right / front) |

States are prioritised in that order: whatever needs your action wins.

### A notification center next to the pet

Omarchy's own notification service keeps running (D-Bus server, history,
Do Not Disturb, actions), but its top-right toast stack is hidden. The pet
watches the service's per-toast state files and shows **every live
notification** as a compact card in the current theme's tooltip colors, newest
on top, animated in and out, with a red border for critical urgency (up to five
on screen, then "+N more"). **Left click** a card to run its action, **right
click** to dismiss it. Each event plays a short sound (normal, critical,
"needs you", "done") with a cooldown so a hook and its own desktop notification
never ring twice.

### Any number of agents — understood from what they announce

Agents are not hardcoded. Each one has its own state (waiting › running › done,
the strongest wins), the pet's state is the strongest across all of them, and
thoughts name everyone: "*Claude & Kimi are working · Codex is done*",
"*Aider & Kimi need you: Waiting for your approval*", "*Codex is done ·
my-app — take a look. Claude is still working.*"

The primary source is the **notification stream itself**: any tool that sends
a desktop notification — directly, or through the terminal's OSC 9 / OSC 777
support (Ghostty, Kitty, WezTerm forward those as desktop notifications) — is
understood with zero configuration. The agent id comes from the app name
("Claude Code" → claude, "Kimi Code" → kimi, a terminal-forwarded "Kimi: …"
→ kimi) and the state from the wording ("waiting for your input", "needs your
permission", "approval" → waiting; "done", "complete", "finished", "ready for
review" → done). The wording rules are regexes you can override:

```json
"signals": {
  "waiting": "waiting for (your )?input|needs? your (permission|approval)|approv",
  "done":    "\\b(done|complete[d]?|finished|ready for review)\\b",
  "ignoreApps": "^(system|git|omarchy)$"
}
```

A "waiting" inferred from a notification is considered answered when that
agent shows activity again or when you dismiss the card. On top of that, two
optional refinements: the hooks (Claude Code and Codex ship hook systems; any
tool can call `omarchy-pets-agent-state <id> running|waiting|done|idle`), and
the transcript-activity detector, which knows where the common CLIs write their
sessions (claude, codex, kimi, grok, gemini, opencode) and takes more from the
settings:

```json
"agents": {
  "myagent": { "dir": "~/.myagent/logs", "glob": "*.log" },
  "grok":    { "dir": "" }
}
```

(an entry with the same id overrides the default; an empty `dir` disables it).

Tip: Codex announces turn completions and approvals as terminal notifications
when `~/.codex/config.toml` has `[tui] notifications = true` — the installer
does not touch that file, set it yourself if you want Codex covered without
hooks.

### Thoughts

Above the cards, a thought bubble says what the pet is thinking:

- "**Claude needs you**: Claude needs your permission to use Bash · my-app" — stays until you answer
- "**Codex is done** · control-tower-app — take a look." — for a few seconds
- "**Memory at 93 %** — next-server holds 3.1 GB" / "**CPU at 100 %** — chrome takes 96 %" — when it gets tired
- Left-click the pet for the full picture: CPU and its top process, temperature, RAM and its top process, battery, weekly limits.

### Switching pets

Right-click the pet to open the picker. It lists **every pet you can have**:
the installed ones (validated against what the animations need — a spritesheet
and the nine Codex Pets rows; anything incomplete is greyed out with the reason)
and Codex's built-in catalog — Codex, Dewey, Fireball, Rocky, Seedy, Stacky,
BSOD, Null Signal. One click switches; a pet that is not downloaded yet is
fetched first (about 600 KB from OpenAI's CDN, once — after that it is local)
and then selected. `omarchy-pets-fetch --all` grabs all eight up front. Community
pets go in with `omarchy-pets-fetch <id> <folder>`. `omarchy-shell pets picker`
opens the same list from a keybinding.

### Naming your pet

The picker's first row is the current pet's name: type a nickname and press
Enter (leave it empty to go back to the original). Each pet keeps its own name
(`names` in the settings), and the pet uses it when it talks. Scripts:
`omarchy-shell pets rename "Piedrita"`.

### Where it lives

The pet **does not wander** on the desktop: drag it to the corner that bothers
you least and it stays there — the position is remembered per monitor and
survives reboots. Everything outside the sprite is click-through. It hides
itself while the focused window is fullscreen.

Free roaming is reserved for the **screensaver**: when Omarchy's screensaver
starts, the shell dims and blurs the desktop (a Hyprland layer rule; the
wallpaper stays softly visible instead of a black screen) and the same pet
strolls, pauses and naps across the whole screen, changing height after each
nap so OLED panels never see the same pixels twice.

## Requirements

- [Omarchy](https://omarchy.org) 3.x (Hyprland + Quickshell shell), Arch Linux
- `jq`, `curl`, `pw-play` (PipeWire) — all present on a stock Omarchy install
- Claude Code and/or Codex CLI if you want agent states (optional)

## Install

```bash
git clone https://github.com/jlopezlira/omarchy-pets ~/Projects/omarchy-pets
cd ~/Projects/omarchy-pets
./install.sh                 # no root needed
./install.sh --screensaver   # additionally hook the screensaver (asks for sudo once)
./install.sh --all-pets      # download all eight built-in pets now (~5 MB), so switching is instant
```

The installer copies the plugin and scripts into your home, downloads the pet's
spritesheet from OpenAI's CDN (the same file the Codex app fetches; it is not
part of this repository), clones Omarchy's notification service with the toast
hidden, adds the agent hooks (with timestamped backups of `~/.claude/settings.json`
and `~/.codex/hooks.json`), enables the plugin and restarts the shell.

Check it is alive:

```bash
omarchy-shell pets status | jq
```

### Other pets

Any built-in Codex pet: `omarchy-pets-fetch dewey` (ids: `codex dewey fireball
rocky seedy stacky bsod null-signal`), then right-click the pet and pick it. A
community pet folder containing `pet.json` + `spritesheet.webp`:
`omarchy-pets-fetch <id> /path/to/folder`. `./install.sh --pet <id>` does both
at install time.

## Configuration

`~/.config/omarchy/pets.json` — hot-reloaded, no restart needed:

```json
{
  "pet": "rocky",
  "names": { "rocky": "Piedrita" },
  "sounds": true,
  "volume": 0.5,
  "scale": 0.5,
  "doneTimeoutMin": 10,
  "thoughtSeconds": 8,
  "screensaverDim": 0.55,
  "sound": {
    "notification": "/usr/share/sounds/freedesktop/stereo/message-new-instant.oga",
    "critical":     "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga",
    "attention":    "/usr/share/sounds/freedesktop/stereo/window-attention.oga",
    "done":         "/usr/share/sounds/freedesktop/stereo/complete.oga"
  }
}
```

- `pet` — id of the pet to show (also set by the right-click picker)
- `names` — your nickname per pet id (also set from the picker or `pets rename`)
- `scale` — sprite scale on the desktop (`0.5` = 96×104 px, crisp at display scale 1)
- `doneTimeoutMin` — how long "Ready" stays before fading back to resting
- `thoughtSeconds` — how long a timed thought stays on screen
- `screensaverDim` — darkness of the screensaver overlay (0 = wallpaper as is, 1 = black)
- `agents` — extra or overridden agent transcript locations for the activity detector (see above)
- `signals` — regexes that turn notification wording into agent states (see above)

IPC (for keybindings or scripts):

```bash
omarchy-shell pets status              # JSON: pet, state, thought, agents, notes, health, positions
omarchy-shell pets listPets            # catalog + installed pets with validity and reason
omarchy-shell pets setPet dewey        # switch pet (must be installed)
omarchy-shell pets installPet dewey    # download a built-in pet and switch to it
omarchy-shell pets rename "Piedrita"   # nickname the current pet ("" = original name)
omarchy-shell pets picker              # open / close the pet picker
omarchy-shell pets think "hello"       # make it think something (scripts, hooks)
omarchy-shell pets screensaverToggle   # try the screensaver mode right now
omarchy-shell notifications toggleDnd # Do Not Disturb (Omarchy's own)
```

## How it works

```
Claude Code / Codex hooks ──▶ omarchy-pets-agent-state ──▶ ~/.local/state/omarchy/pets/agents/<agent>-<session>.json
Omarchy notification service ─────────────────▶ ~/.local/state/omarchy/notifications/<id>.json  (one per live toast)
Omarchy agents widget ─────────────────────────▶ ~/.local/state/omarchy/agents/usage/<agent>.json (weekly limits)
omarchy-pets-health (every 10 s, 60 s when asleep) ────▶ JSON on stdout
                                                        │
                                             Service.qml (Quickshell)
                                    watches the folders, computes the state,
                            draws the sprite from the Codex Pets atlas per screen
```

- **Layer**: one full-screen transparent `PanelWindow` per monitor on the `top`
  layer-shell layer with an input **mask** limited to the sprite and its bubble —
  the same technique Omarchy uses for its own overlays.
- **Sprite**: the Codex Pets atlas (8 columns × 9 rows of 192×208; rows `idle,
  running-right, running-left, waving, jumping, failed, waiting, running, review`)
  drawn with `Image.sourceClipRect`, nearest-neighbour, at 8 fps.
- **Cursor facing**: layer surfaces only see the pointer over the sprite, so the
  global cursor is polled from Hyprland (`hyprctl cursorpos`, 4 Hz, paused when
  asleep, hidden or in screensaver mode).
- **Cost**: at rest the pet ticks at 4 fps and repaints only its own rectangle;
  asleep, every timer stops. Health, activity and cursor polls are short
  processes of a few milliseconds. The spritesheet is decoded once; the
  screensaver and the picker load it only while visible.
- **Screensaver**: Omarchy's screensaver runs `ttfx` in a terminal. A wrapper at
  `/usr/local/bin/ttfx` (earlier in `PATH` than `/usr/bin`) intercepts that call,
  asks the shell for screensaver mode over IPC, stays alive as the process named
  `ttfx` (which Omarchy polls and later kills), and turns the mode off on exit.
  If the shell doesn't answer, the real `ttfx` runs as before.

## Files

```
plugin/jlopezlira.pets/      the Quickshell service plugin (manifest.json, Service.qml)
bin/omarchy-pets-health              machine health snapshot (JSON), root-free
bin/omarchy-pets-agent-state         called by the agent hooks; one file per agent session
bin/omarchy-pets-activity            hook-free "is an agent writing right now?" detector
bin/omarchy-pets-list                installed pets, validated (used by the picker)
bin/omarchy-pets-fetch               downloads a built-in Codex pet or installs a community one
hypr/omarchy-pets.lua                Hyprland rules: blurred screensaver layer, hidden screensaver terminal
hooks/install-hooks.py      adds/removes the Claude Code + Codex hooks (flagged, reversible)
screensaver/ttfx            the screensaver wrapper (installed to /usr/local/bin with --screensaver)
config/pets.json             default settings
pets/rocky/pet.json         Rocky's manifest (the spritesheet is downloaded, not shipped)
install.sh / uninstall.sh
```

## Uninstall

```bash
./uninstall.sh          # plugin, scripts, hooks, notification clone, screensaver hook
./uninstall.sh --purge  # also config, downloaded pets and saved state
```

## Credits and licensing

- Code: MIT (see `LICENSE`).
- Pet sprites are © OpenAI, part of Codex Pets. They are downloaded at install
  time for personal use and are **not** redistributed here; delete
  `~/.config/omarchy/pets` if you don't want them.
- Built on [Omarchy](https://omarchy.org) and [Quickshell](https://quickshell.org).
