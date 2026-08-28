# provigil

Keep a Mac awake — lid closed, off the charger, still on the network — and watch
it do so on a live terminal dashboard. `provigil` bails out on its own if the
battery gets low or the battery gets hot, so an overnight job can't quietly cook
the machine.

## The problem

`caffeinate` alone won't hold a MacBook up with the lid shut; you need
`pmset disablesleep 1` as well. And once you've told a laptop it may not sleep,
you've disabled the safety net: it will happily sit in a closed bag, on battery,
pinned at 100% CPU, until it's flat or very warm.

`provigil` wraps the two commands you actually need, then supervises the result:

- holds the machine up with `caffeinate` + `pmset disablesleep 1`
- samples battery percentage and battery temperature every 30 s
- shows both as gauges, multi-row sparklines, trend arrows and rates (%/hr, °C/min)
- **exits by itself** at ≤10% battery or ≥45 °C, restoring every setting it changed
- posts a macOS notification when it warns or exits, so you find out from your
  phone rather than from a dead laptop

## What it looks like

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  provigil   mode default  ·  uptime 1h 42m 30s                                         │
├────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                        │
│  battery  [█████████████████░░░]   86%→   drain 12.0%/hr    ETA 8:47                   │
│           ▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁                                   │
│           ██████████████████████████████████████████                                   │
│           ██████████████████████████████████████████                                   │
│           ██████████████████████████████████████████                                   │
│           ██████████████████████████████████████████                                   │
│           ██████████████████████████████████████████                                   │
│                                                                                        │
│  temp     [████████████████▌░░░]  38.0°C↑  rate  +0.1°C/min  cap 54m                   │
│                                      ▁▁▁▁▁▁    ▁▁▃▅█                                   │
│                                   ▂▄▆██████▆▆▆▆█████                                   │
│                                ▁▅▇██████████████████                                   │
│                             ▂▄▆█████████████████████                                   │
│              ▁▃▅▅▅▅▅▅▅▅▃▃▅▅█████████████████████████                                   │
│            ▂▆███████████████████████████████████████                                   │
│                                                                                        │
│  power    Battery     load  1.42 1.31 1.18                                             │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  Ctrl+C to restore   ·   exits at battery ≤10%   ·   temp ≥45°C                        │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

> **Illustrative, not a captured session.** The frame above was produced by
> driving `provigil`'s own rendering code with synthetic sample data, so the
> layout, glyphs and column widths are real — but the numbers are made up.
> Your terminal also colours the gauges green/amber/red, which this
> plain-text README can't show.

Reading it:

| Field | Meaning |
| --- | --- |
| `battery` gauge | Charge as a fraction of 100% |
| `86%→` | Current charge, and the trend over the last 3 samples (`↑` `↓` `→`) |
| `drain` | Discharge rate in %/hr, measured over the last 5 minutes |
| `ETA` | macOS's own smoothed estimate from `pmset`, else `provigil`'s own projection to the battery floor |
| `temp` gauge | Battery temperature as a fraction of the **exit** threshold, so a full bar means "about to quit" |
| `rate` | °C/min over the last 3 minutes |
| `cap` | Projected time until the temperature ceiling, or `cooling`. A `⚠` appears under 15 minutes |
| sparklines | Last ~25 minutes of history. The temperature chart auto-scales to recent min/max, with a 2 °C floor so a flat reading looks flat |
| `load` | 1/5/15-minute load averages |

Under 72 columns the dashboard collapses to a single updating status line:

```
[provigil:default]  batt 86%  temp 38.0°C  Battery  up 1h 42m 30s
```

## Requirements

- **macOS.** `provigil` reads Apple-specific interfaces (`ioreg`,
  `AppleSmartBattery`, `pmset`, `caffeinate`) and is not portable. `install.sh`
  checks `uname` and refuses to install elsewhere; the script itself has no OS
  guard and will simply fail on the missing tools.
- **bash 3.2 or newer.** It runs on the `/bin/bash` that ships with macOS —
  no Homebrew bash needed.
- Standard system tools, all preinstalled: `ioreg`, `pmset`, `caffeinate`,
  `osascript`, `defaults`, `tput`, plus `awk`, `sed`, `grep`, `sort`, `seq`,
  `wc`, `tr`, `date` and `uptime`.
- **Passwordless `sudo` for `pmset`** — see below. `provigil` fail-fasts without it.
- A UTF-8 terminal, for the box-drawing and block glyphs.

## Install

```sh
git clone https://github.com/janhaak/provigil.git
cd provigil
./install.sh
```

`install.sh` is idempotent — re-run it whenever you like. It:

1. syntax-checks `bin/provigil` and makes it executable;
2. symlinks it into `/usr/local/bin` if that directory is writable, otherwise
   into `~/.local/bin` (created if needed), warning you if the chosen directory
   isn't on your `PATH`;
3. offers to set up passwordless `pmset`, validating the sudoers fragment
   *before* installing it.

It never silently replaces anything. If a `provigil` already exists at the
target it tells you what's there and asks first — repointing an existing
symlink, or moving a regular file aside to `provigil.bak`.

Useful flags:

| Flag | Effect |
| --- | --- |
| `--yes` | Assume yes to every prompt (for unattended runs) |
| `--no-sudoers` | Skip the passwordless-`pmset` step entirely |
| `--prefix DIR` | Install the symlink into `DIR` instead of autodetecting |

Don't run `sudo ./install.sh` — it only needs `sudo` for the one `install`
command that writes the sudoers file, and it invokes that itself. On a stock
macOS where `/usr/local/bin` isn't user-writable, the `~/.local/bin` fallback
is the intended path.

Or, without the installer, just put `bin/provigil` on your `PATH` yourself:

```sh
ln -s "$PWD/bin/provigil" ~/.local/bin/provigil
```

## Passwordless sudo for pmset

`provigil` runs `sudo -n pmset -a disablesleep 1` on start and
`sudo -n pmset -a disablesleep 0` on cleanup. `-n` means *never prompt* — so
without a sudoers rule the tool exits 1 immediately rather than blocking on a
password it can't ask for (which is the point: it has to be able to undo
`disablesleep` from a signal handler, unattended).

The rule you need, in `/etc/sudoers.d/pmset-nopasswd`:

```sudoers
# Installed by provigil (https://github.com/janhaak/provigil).
# Lets provigil toggle sleep without an interactive password prompt.
yourusername ALL=(root) NOPASSWD: /usr/bin/pmset
```

Replace `yourusername` with the output of `id -un`.

### Writing it safely

A syntax error in **any** file under `/etc/sudoers.d` can break `sudo` for the
whole machine, so never write there with a plain redirect. Two safe options.

**Option A — let `visudo` edit it directly.** `visudo` validates on save and
refuses to install a broken file:

```sh
sudo visudo -f /etc/sudoers.d/pmset-nopasswd
```

**Option B — write to a temp file, validate, then install.** This is what
`install.sh` does, and it's the better choice for scripting:

```sh
tmp=$(mktemp "${TMPDIR:-/tmp}/pmset-nopasswd.XXXXXX")
printf '%s\n' \
  '# Installed by provigil (https://github.com/janhaak/provigil).' \
  '# Lets provigil toggle sleep without an interactive password prompt.' \
  "$(id -un) ALL=(root) NOPASSWD: /usr/bin/pmset" > "$tmp"

# Validate BEFORE it goes anywhere near /etc. Aborts if the syntax is bad.
visudo -c -f "$tmp" || { echo "bad sudoers syntax, aborting"; rm -f "$tmp"; exit 1; }

# install(1) sets owner, group and mode atomically.
sudo install -m 0440 -o root -g wheel "$tmp" /etc/sudoers.d/pmset-nopasswd
rm -f "$tmp"
```

The mode and ownership matter: `sudo` **ignores** files in `sudoers.d` that are
group- or world-writable. Check the permission bits, owner and group look like
this (the size depends on your username and how many comment lines you kept):

```console
$ ls -l /etc/sudoers.d/pmset-nopasswd
-r--r-----  1 root  wheel  ...  /etc/sudoers.d/pmset-nopasswd
```

Verify it works — this should print your power settings with no prompt:

```sh
sudo -n pmset -g
```

Two notes on scope. This grants passwordless access to *all* of `pmset`, not
just `disablesleep`; `pmset` can change any power setting, so treat it as a
real, if narrow, privilege grant. And any other tool on the machine may be
relying on the same file — `uninstall.sh` warns you before deleting it.

## Usage

```sh
provigil [default|max]
```

Run it in a terminal window you can leave open, and stop it with `Ctrl+C`.

| Mode | Command it runs | What stays awake | Use it for |
| --- | --- | --- | --- |
| `default` | `caffeinate -ims` | System and disks stay up; **the display may sleep** | Lid closed, off charger, still online. The normal case: a long job or a sync that must survive a shut lid |
| `max` | `caffeinate -dims` | Also forces the **display** on and sets the screensaver idle time to 0 | Lid open and something must stay visible — a dashboard on a spare screen, a demo, a screen share |

Anything other than `default` or `max` prints usage and exits 1. `default` is
assumed if you pass nothing.

The `caffeinate` flags: `-d` display, `-i` idle system sleep, `-m` disk,
`-s` system (while on AC).

## Thresholds

| Setting | Default | Meaning |
| --- | --- | --- |
| Battery floor | 10% | At or below, notify and exit 2 |
| Temperature warning | 40 °C | At or above, notify once. Re-arms after cooling 2 °C below it |
| Temperature ceiling | 45 °C | At or above, notify and exit 3 |
| Poll interval | 30 s | Between samples |
| History | 50 samples | Sparkline window — ~25 min at the default poll |
| Sparkline height | 6 rows | Taller shows the slope more clearly |

Temperature comes from `ioreg -r -n AppleSmartBattery`, which exposes two
readings in centi-Celsius: `Temperature` (cell) and `VirtualTemperature` (the
effective figure Apple uses for thermal decisions). `provigil` takes the
**higher** of the two, so either sensor going hot trips the threshold. Note
these are *battery* temperatures, not CPU package temperature — 45 °C is hot for
a battery, not for a CPU.

### Overriding them

Every threshold reads an environment variable and falls back to the default
above, so you can tune a single run without editing the script:

| Variable | Default |
| --- | --- |
| `PROVIGIL_MIN_BATTERY` | `10` |
| `PROVIGIL_WARN_TEMP_C` | `40` |
| `PROVIGIL_MAX_TEMP_C` | `45` |
| `PROVIGIL_POLL_SECONDS` | `30` |
| `PROVIGIL_HIST_MAX` | `50` |
| `PROVIGIL_SPARK_HEIGHT` | `6` |

```sh
# Stop earlier and sample faster — a cautious overnight run.
PROVIGIL_MIN_BATTERY=25 PROVIGIL_POLL_SECONDS=15 provigil default

# A short, flat dashboard for a small terminal pane.
PROVIGIL_SPARK_HEIGHT=3 PROVIGIL_HIST_MAX=30 provigil max
```

Or export them from your shell profile to change your own defaults for good.
Raising `PROVIGIL_MAX_TEMP_C` raises the ceiling the tool was written to
enforce — that's your call, but it's the one knob worth thinking twice about.

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Clean stop — `Ctrl+C`, `SIGTERM`, or `caffeinate` exiting |
| `1` | Usage error, another instance already running, or passwordless `sudo` for `pmset` not configured |
| `2` | Battery hit the floor. Notified and stood down so the Mac can sleep |
| `3` | Battery temperature hit the ceiling. Notified and stood down so the Mac can cool |

Handy in a wrapper:

```sh
provigil default; rc=$?
case $rc in
  0) echo "stopped normally" ;;
  2) echo "ran the battery down — plug in before retrying" ;;
  3) echo "got too hot — let it cool, then retry" ;;
  *) echo "did not start (rc=$rc)" ;;
esac
```

## What it changes, and how it cleans up

While running, `provigil` changes exactly three things:

| Change | Restored by |
| --- | --- |
| `sudo pmset -a disablesleep 1` | `sudo -n pmset -a disablesleep 0` |
| A background `caffeinate` | The PID is killed |
| `max` only: screensaver `idleTime` set to 0 | The original value is read at start and written back verbatim |

An `EXIT`/`INT`/`TERM` trap does all of it, so `Ctrl+C`, a `kill`, a threshold
trip and a normal exit all take the same cleanup path: the cursor comes back,
sleep is re-enabled, the screensaver is restored and `/tmp/provigil.pid` is
removed.

The gap worth knowing about: cleanup can't run on `SIGKILL` (`kill -9`) or a
hard power-off. If that happens the machine is left with sleep disabled. Check
and fix it by hand:

```sh
pmset -g | grep SleepDisabled     # 1 means still disabled
sudo pmset -a disablesleep 0
rm -f /tmp/provigil.pid           # only if no provigil is actually running
```

A single-instance lockfile at `/tmp/provigil.pid` holds the PID. On start,
`provigil` only refuses to run if that PID is still alive, so a lockfile left
behind by a crash doesn't wedge you permanently.

## Troubleshooting

**`provigil already running (pid 12345)`** — a live instance holds the lock.
Find it with `ps -p 12345`. If that's a terminal you've lost, `kill 12345`
lets it clean up properly (never `kill -9`, which skips cleanup). If the PID
is genuinely gone, `provigil` will start anyway; if you want the file gone,
`rm -f /tmp/provigil.pid`.

**`Error: passwordless pmset not configured`** — the sudoers rule is missing,
malformed, or has the wrong permissions. Work through it:

```sh
sudo -n pmset -g                       # the exact check provigil makes
ls -l /etc/sudoers.d/pmset-nopasswd    # want -r--r----- root wheel
sudo visudo -c                         # does the whole sudoers set parse?
id -un                                 # does the rule name this user?
```

The most common cause is a username mismatch — the rule was written for a
different account, or the file is group-writable and `sudo` is ignoring it.
Re-run `./install.sh`, or see [Writing it safely](#writing-it-safely).

**The dashboard is a single line instead of a box** — your terminal is under
72 columns. Widen it, or accept the compact line. The layout is re-checked on
every poll, so the box appears within one interval of resizing. Between 72 and
90 columns the box shrinks to fit; at 90+ it settles at 90.

**Boxes, blocks or arrows render as `?` or mojibake** — the terminal isn't in
UTF-8. Set a UTF-8 locale (`export LC_ALL=en_US.UTF-8`) and use a font with
box-drawing and block-element coverage.

**Columns look misaligned** — the frame padding compensates for the two
double-width glyphs it uses (`⚡` and `⚠`). A font that renders those at a
different width, or an emoji-presentation variant, can shift a row by a
column. Cosmetic only.

**Temperature reads 0.0 °C, or battery is blank** — `ioreg` returned nothing
for `AppleSmartBattery`. Expected on a Mac with no battery (a Mac mini or Studio),
where `provigil` isn't much use anyway. Check with:

```sh
ioreg -r -n AppleSmartBattery | grep -E '"(CurrentCapacity|Temperature|VirtualTemperature)"'
```

**The Mac still slept with the lid closed** — check `pmset -g` shows
`SleepDisabled 1` while `provigil` runs. Some things override it regardless:
critically low battery, a genuine thermal emergency, and certain firmware or
MDM power policies.

**No notifications** — `provigil` posts via `osascript`. Allow notifications
for your terminal app in System Settings → Notifications. Notification failures
are swallowed on purpose; they never take the tool down.

## Development

```sh
make check   # bash -n on every script, plus an exit-code test. Never runs provigil for real
make lint    # shellcheck (brew install shellcheck)
make test    # both
```

`make check` is safe on any machine: it only parses, and the one thing it does
execute is `provigil badmode`, which exits before touching `pmset`.

**`provigil` targets bash 3.2**, the `/bin/bash` Apple ships. That's deliberate
— it means no Homebrew dependency — and it constrains contributions: no
associative arrays, no `${var,,}`, no `mapfile`/`readarray`, no namerefs. The
script carries explicit 3.2 workarounds, so please leave them be:

- `push_hist` appends to an array by name using `eval`
- `rate_per_min` reads arrays by name via indirect expansion (`${!ref}`)
- `trend_arrow` takes the last three values positionally rather than by reference

`.shellcheckrc` pins `shell=bash`. The two `# shellcheck disable=SC2034`
comments in `bin/provigil` are unavoidable: shellcheck can't see through `eval`
or indirect expansion, so it thinks `TIME_HIST` and `val` are unused. They
aren't.

There is no CI yet. The natural next step is a GitHub Actions workflow on
`macos-latest` running `make test` on every push — deliberately left out of
this commit, to be added separately.

## License

MIT — see [LICENSE](LICENSE).
