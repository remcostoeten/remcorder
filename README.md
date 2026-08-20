<p align="center">
  <img src="packaging/icons/remcorder-128.png" width="88" alt="Remcorder logo" />
</p>

<h1 align="center">Remcorder</h1>

<p align="center">
  A native control center and a reliable background service around<br />
  <a href="https://git.dec05eba.com/gpu-screen-recorder/about/"><code>gpu-screen-recorder</code></a>,
  for GPU-accelerated screen recording on Linux.<br />
  Qt 6 window, system tray, click-through overlay, CLI, and a trim editor,<br />
  all talking to one daemon that owns the recording lifecycle.
</p>

Recording is a daemon, not a window. It listens on a per-user Unix socket, so a
compositor keybind, the tray, the CLI, and the GUI are all just clients. Close
the window mid-recording and nothing stops. `SIGINT` is handled gracefully, so
MP4 files are finalized instead of corrupted.

- Start, pause, resume, stop, toggle, and inspect a recording over the socket
- Direct monitor capture by default, portal capture on request
- Desktop audio, configurable FPS/codec/quality, timestamped filenames
- Machine-readable JSON status for panels and scripts
- A compact, click-through QML overlay that appears only while recording
- A Qt 6 control center: monitor/audio discovery, quality presets, persistent
  settings, tray controls, save notifications
- A live microphone meter with peak hold, headphone listen-back, and a gain
  slider wired to the real PipeWire source volume
- A non-destructive trim editor with video preview and hardware-accelerated
  `-trim.mp4` export, plus optional experimental motion blur

## Install

### Arch Linux (package)

Every tagged release publishes a pacman package. This is the shortest path, and
the one to prefer if you are not developing Remcorder:

```sh
gh release download --repo remcostoeten/remcorder --pattern '*.pkg.tar.zst'
sudo pacman -U remcorder-*.pkg.tar.zst
systemctl --user enable --now remcorder.service remcorder-overlay.service
```

The package installs to `/usr`, pulls in `gpu-screen-recorder` and the Qt 6
runtime, and suggests `ffmpeg` and `libpulse` for trimming, motion blur, and the
microphone meter. `gh` is required because the repository is private.

### From a checkout

Installs to `~/.local` and leaves the package alone:

```sh
./scripts/pre-reqs.sh
make install
systemctl --user enable --now remcorder.service remcorder-overlay.service
```

`scripts/pre-reqs.sh` reports what is missing per distribution rather than
installing anything behind your back; `scripts/packages.conf` holds the package
names it maps to.

Recordings default to the XDG Videos directory, under `Recordings`.

## Use

Launch **Remcorder** from the desktop application menu, or run `remcorder`. The
graphical application can start the background service automatically, and
settings are saved with Qt's standard per-user storage.

### Live in the system tray

```sh
make tray
```

That builds, installs, writes `~/.config/autostart/remcorder-tray.desktop`, and
relaunches Remcorder straight into the tray with no window. The tray menu starts,
pauses, stops, and opens recordings; clicking the icon opens the window, and
closing the window returns it to the tray instead of quitting.

```sh
make tray-off   # remove the autostart entry and stop the tray instance
remcorder --tray
```

`--tray` is ignored when the desktop has no tray, or when `--trim` is passed, so
the app never starts invisible with no way to reach it.

### Microphone

Turning **Sound → Microphone** on reveals a live input meter with peak hold, a
**Listen** button that plays the microphone through the default output, and a
**Gain** slider.

Listen-back is disabled while recording, and switches itself off when a recording
starts, because desktop-audio capture would otherwise record the loopback. Use
headphones while listening.

The gain slider is not monitor-only: it sets the PipeWire source volume through
`pactl`, so it changes what is recorded, and stays applied system-wide until
changed again. The monitor stream is only open while the window is visible and
the microphone is enabled.

### Trimming

After a recording is saved, choose **Trim**. The editor provides a muted video
preview and a range slider. Export always creates a new file and never modifies
the source. Progress and completion show in both the main window and the tray,
and closing the window is safe because the export continues in the tray.

The editor also carries the experimental **Motion blur** toggle, which blends
successive frames as the copy is encoded. Subtle, Smooth, and Strong blend 2, 3,
or 5 frames. Blur is a per-export choice rather than a persistent setting, so
nothing is processed unless you ask for it. The result is named
`recording-trim.mp4`, or `recording-trim-blur.mp4` when blur is on.

You can also open the editor directly:

```sh
remcorder --trim /path/to/video.mp4
```

### CLI

```sh
remcorderctl start
remcorderctl status
remcorderctl pause
remcorderctl resume
remcorderctl toggle-pause
remcorderctl stop
remcorderctl toggle
remcorderctl --json status
remcorderctl start --delay 3s
remcorderctl stop --open              # open the recording when it stops
remcorderctl stop --open-dir          # open the recording's folder when it stops
```

`--delay` only applies to `start` and waits before sending the command, so you
can switch windows before capture begins. `--open`/`--open-dir` only fire on
`stop`/`toggle` calls that actually end a recording, and use `xdg-open` to launch
the file or folder in your default application.

Bind `remcorderctl toggle` to a compositor shortcut. For example, in Hyprland:

```ini
bind = SUPER SHIFT, R, exec, remcorderctl toggle
bind = SUPER SHIFT, P, exec, remcorderctl toggle-pause
```

### Daemon options

For compositor-neutral portal selection, override the service with
`systemctl --user edit remcorder.service`:

```ini
[Service]
ExecStart=
ExecStart=%h/.local/bin/remcorderd -capture portal
```

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
make check                # go test, go vet, Release cmake build, qmllint
go run ./cmd/remcorderd
cmake -S . -B build && cmake --build build
./build/remcorder
```

The QML indicator polls a private, atomically updated state snapshot in the user
runtime directory. It never controls recording itself, keeping the recorder
lifecycle independent from the UI.

```text
app/             Qt 6 control center (C++ backend + QML)
cmd/remcorderd   background daemon that owns the recording lifecycle
cmd/remcorderctl CLI client for shortcuts and scripts
internal/        recorder engine and the Unix-socket control protocol
overlay/         click-through recording indicator
packaging/       desktop entries, brand icons, and the Arch PKGBUILD
systemd/         user units
```

### Icons

`packaging/icons/remcorder-<size>.png` is the application mark. `make install`
and the PKGBUILD fan those out into `share/icons/hicolor/<size>x<size>/apps/`,
which is what `Icon=remcorder` in the desktop entries resolves against.
`packaging/icons/tray/` holds the small-size tray exports.

Both sets are also compiled into the binary under the `:/branding` resource
prefix, so `app/Branding.h` can hand the window and the tray a real icon before
anything is installed. Adding a size means adding it to the `FILES` list in
`CMakeLists.txt`, the size list in `app/Branding.h`, and, for application sizes,
`ICON_SIZES` in the `Makefile` plus the matching loop in the PKGBUILD.

The exports are raster, generated from the artwork in the brand asset pack. There
is no vector master; regenerate the PNGs from the pack rather than editing them
in place.

### Git

The repository is private: <https://github.com/remcostoeten/remcorder>, default
branch `daddy`, cloned over HTTPS with the `gh` credential helper.

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

Work on a branch, never straight on `daddy`:

```sh
git switch -c feat/mic-meter
make check
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
git switch daddy && git pull --ff-only
git rebase daddy                 # keep a feature branch current
git commit --amend --no-edit     # fold a fixup into the tip commit
git restore --staged path        # unstage without losing the edit
git restore path                 # discard an unwanted local edit
git log --oneline --graph -20
git diff daddy...HEAD            # exactly what a PR would contain
```

Before pushing, `make check` must pass. Build output lives in `build/` and is
ignored, as are the `remcorderd` and `remcorderctl` binaries produced by a bare
`make` and any stray `*.mp4` recordings. Keep recordings out of the repository.

## Continuous integration

Two workflows run against the `daddy` branch.

**CI** (`.github/workflows/ci.yml`) runs `make check` in an `archlinux:base-devel`
container on every push and pull request. These are the same four steps you run
locally, so a green local check means a green CI check.

**Release** (`.github/workflows/release.yml`) fires on a `v*` tag. It runs
`make check`, builds a source tarball with `git archive`, stamps `pkgver` from
the tag, builds the package with `makepkg` as an unprivileged user, and uploads
the `.pkg.tar.zst` and the PKGBUILD to a GitHub Release.

Two things build fine locally but not in the container. Both are already
handled, so do not remove them:

- The job runs as root while the workspace belongs to the runner user, so `git`
  rejects it as *dubious ownership*. The release workflow marks the workspace
  safe before calling `git archive`.
- The source tarball extracts inside a git tree owned by another user, so Go's
  VCS stamping aborts the build. The PKGBUILD sets `GOFLAGS=-buildvcs=false`; a
  release build takes its version from `pkgver`, not from git.

## Releasing

Releases are cut with [`releaser`](https://github.com/remcostoeten/releaser),
configured by `releaser.config.json`. The version lives in **one** place,
`pkgver` in `packaging/pkgbuild/PKGBUILD`, and `CMakeLists.txt` is kept in step
by a match-counted replacement, so the two can never drift apart.

From a clean `daddy` that is in sync with origin:

```sh
releaser plan --bump patch     # read-only: shows the plan and changes nothing
releaser --bump patch          # execute after it asks
```

That rewrites `pkgver`, syncs `CMakeLists.txt`, commits `chore(release): vX.Y.Z`,
tags, and pushes the branch and the tag. The tag is what triggers the release
workflow, so watch it and confirm the package was actually produced:

```sh
gh run watch "$(gh run list --workflow=release.yml --limit 1 --json databaseId -q '.[0].databaseId')"
gh release view "v$(sed -n 's/^pkgver=//p' packaging/pkgbuild/PKGBUILD)"
```

Never edit `pkgver` by hand and never tag manually. Both bypass the single
source of truth and produce a tag whose PKGBUILD disagrees with it.

If a release is interrupted partway, finish it rather than starting a new one:

```sh
releaser status
releaser resume
```

To validate packaging changes without cutting a release, build the package the
way CI does:

```sh
ver=$(sed -n 's/^pkgver=//p' packaging/pkgbuild/PKGBUILD)
git archive --format=tar.gz --prefix="remcorder-$ver/" \
  -o "packaging/pkgbuild/remcorder-$ver.tar.gz" HEAD
(cd packaging/pkgbuild && makepkg --noconfirm --force)
git clean -fdx packaging/pkgbuild
```

Run `git archive` from the repository root. From inside `packaging/pkgbuild` it
silently archives only that subdirectory, and the build fails on missing sources.

## License

[MIT](LICENSE)
