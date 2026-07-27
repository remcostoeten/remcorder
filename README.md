# Remcorder

A native control center and reliable background service around
[`gpu-screen-recorder`](https://git.dec05eba.com/gpu-screen-recorder/about/) for
GPU-accelerated recording on Wayland.

## What works

- Start, pause, resume, stop, toggle, and inspect a recording through a
  per-user Unix socket.
- Graceful `SIGINT` shutdown so MP4 files are finalized instead of corrupted.
- Direct Wayland monitor capture by default, with portal capture available.
- Desktop audio, configurable FPS/codec/quality, and timestamped filenames.
- Automatic cleanup of stale sockets and safe shutdown with the desktop session.
- Machine-readable JSON status for panels, scripts, and the future overlay.
- A compact, click-through QML overlay that appears only while recording.
- A Qt 6 control center with monitor and audio discovery, quality presets,
  persistent settings, tray controls, and save notifications.
- A live microphone meter with peak hold, headphone listen-back, and an input
  gain slider that drives the real PipeWire source volume.
- Optional experimental motion blur that preserves the original recording and
  creates a second `-blur.mp4` copy, using hardware encoding when available.
- A non-destructive trim editor with video preview, precise in/out points, and
  hardware-accelerated `-trim.mp4` export.

## Install (Arch Linux)

```sh
./scripts/pre-reqs.sh
make install
systemctl --user enable --now remcorder.service remcorder-overlay.service
```

Recordings default to the XDG Videos directory, under `Recordings`.

## Live in the system tray

```sh
make tray
```

That builds, installs, writes `~/.config/autostart/remcorder-tray.desktop`, and
relaunches Remcorder straight into the tray with no window. The tray menu starts,
pauses, stops, and opens recordings; clicking the icon opens the window, and
closing the window returns it to the tray instead of quitting.

```sh
make tray-off   # remove the autostart entry and stop the tray instance
```

The flag behind it works on its own too:

```sh
remcorder --tray
```

`--tray` is ignored when the desktop has no tray, or when `--trim` is passed, so
the app never starts invisible with no way to reach it.

## Use

Launch **Remcorder** from the desktop application menu, or run:

```sh
remcorder
```

The graphical application can start the background service automatically.
Settings are saved with Qt's standard per-user settings storage.

Turning **Sound → Microphone** on reveals a live input meter with peak hold,
a **Listen** button that plays the microphone through the default output, and a
**Gain** slider. Listen-back is disabled while recording, and switches itself off
when a recording starts, because desktop-audio capture would otherwise record the
loopback. Use headphones while listening. The gain slider is not monitor-only: it
sets the PipeWire source volume through `pactl`, so it changes what is recorded —
and it stays applied system-wide until changed again. The monitor stream is only
open while the window is visible and the microphone is enabled.

Enable **Experimental → Motion blur copy** to produce both versions. Subtle,
Smooth, and Strong blend 2, 3, or 5 successive frames. The original MP4 is
available immediately; the blurred copy is processed afterward, with progress
shown in the window and tray. Closing the window is safe because processing
continues in the tray.

After a recording is saved, choose **Trim original…** or **Trim blurred copy…**.
The editor provides a muted video preview and a range slider. Trim export always
creates a new file, such as `recording-trim.mp4`; it never modifies the source.
Progress and completion are shown in both the main window and system tray.
You can also open the trim editor directly:

```sh
remcorder --trim /path/to/video.mp4
```

The CLI remains available for shortcuts and scripts:

```sh
remcorderctl start
remcorderctl status
remcorderctl pause
remcorderctl resume
remcorderctl toggle-pause
remcorderctl stop
remcorderctl toggle
remcorderctl --json status
```

Bind `remcorderctl toggle` to a compositor shortcut. For example, in Hyprland:

```ini
bind = SUPER SHIFT, R, exec, remcorderctl toggle
bind = SUPER SHIFT, P, exec, remcorderctl toggle-pause
```

For compositor-neutral portal selection, override the service:

```sh
systemctl --user edit remcorder.service
```

Then add:

```ini
[Service]
ExecStart=
ExecStart=%h/.local/bin/remcorderd -capture portal
```

Useful daemon options:

```text
-capture screen|portal|DP-1
-fps 60
-audio default_output
-codec h264|hevc|av1
-quality medium|high|very_high|ultra
-output-dir /path/to/recordings
-cursor=true|false
```

Run `gpu-screen-recorder --list-monitors` and
`gpu-screen-recorder --list-audio-devices` to discover exact source names.

## Development

```sh
make check
go run ./cmd/remcorderd
cmake -S . -B build
cmake --build build
./build/remcorder
```

The QML indicator polls a private, atomically updated state snapshot in the
user runtime directory. It never controls recording itself, keeping the
recorder lifecycle independent from the UI.

### Layout

```text
app/            Qt 6 control center (C++ backend + QML)
cmd/remcorderd  background daemon that owns the recording lifecycle
cmd/remcorderctl CLI client for shortcuts and scripts
internal/       recorder engine and the Unix-socket control protocol
overlay/        click-through recording indicator
packaging/      desktop entries and icon
systemd/        user units
```

## Git

The repository is private: <https://github.com/remcostoeten/remcorder>, default
branch `main`, cloned over HTTPS with the `gh` credential helper.

```sh
gh repo clone remcostoeten/remcorder     # or: git clone https://github.com/remcostoeten/remcorder.git
cd remcorder
./scripts/pre-reqs.sh
make check
```

To use SSH instead:

```sh
git remote set-url origin git@github.com:remcostoeten/remcorder.git
```

Work on a branch, never straight on `main`:

```sh
git switch -c feat/mic-meter
make check                       # go test, go vet, cmake build, qmllint
git add -p
git commit -m "feat(ui): add microphone level meter"
git push -u origin feat/mic-meter
gh pr create --fill
```

Commit messages follow Conventional Commits, so the subject reads as
`type(scope): imperative summary` under about 72 characters:

```text
feat(ui):    a user-visible capability
fix(app):    a defect, with the symptom in the body
refactor:    behaviour-preserving restructuring
perf:        measured improvement, with numbers in the body
docs:        README and comments only
chore:       build files, packaging, dependencies
```

Common operations:

```sh
git status -sb                   # short status with upstream tracking
git switch main && git pull --ff-only
git rebase main                  # keep a feature branch current
git commit --amend --no-edit     # fold a fixup into the tip commit
git restore --staged path        # unstage without losing the edit
git restore path                 # discard an unwanted local edit
git log --oneline --graph -20
git diff main...HEAD             # exactly what a PR would contain
```

Before pushing, `make check` must pass: it runs `go test ./...`, `go vet ./...`,
a Release CMake build, and `qmllint` over the QML. Build output lives in
`build/` and is ignored, as are the `remcorderd` and `remcorderctl` binaries
produced by a bare `make` and any stray `*.mp4` recordings — keep recordings out
of the repository.

Tags mark releases:

```sh
git tag -a v0.2.0 -m "Microphone monitoring and tray autostart"
git push origin v0.2.0
```
