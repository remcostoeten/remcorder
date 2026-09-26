# Using Remcorder

Launch **Remcorder** from the desktop application menu, or run `remcorder`. The
graphical application can start the background service automatically, and
settings are saved with Qt's standard per-user storage.

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
remcorder --tray
```

`--tray` is ignored when the desktop has no tray, or when `--trim` is passed, so
the app never starts invisible with no way to reach it.

## Start delay and sound cues

**Capture → Start delay** (Off / 3s / 5s / 10s) holds the recording back so you
can bring the right window forward first. During the countdown the hero card
shows the seconds left and the record button turns into a cancel button; `Esc`,
the tray's stop entry, and clicking the button all abort it.

**Capture → Sound cues** plays a synthesized two-note ping when a recording
starts, a falling pair when it stops, and a tick per countdown second. The tones
are generated in memory and played through the default output device, so they do
not depend on the system bell being enabled. Toggling the setting on plays a
sample ping.

## Screen annotations

The native app's **Annotation pen** works while Remcorder is open, including in
the tray. **Double-tap left Shift within 350ms** to enter drawing mode, then drag
with the left mouse button to draw. Double-tap left Shift again to return pointer input to the desktop;
the drawings remain visible and click through.

In drawing mode, **double right-click within 350ms** to open the
color palette. Choose a swatch, or **scroll up/down** while the palette is open
to increase/decrease the width (1–40px). Leaving drawing mode closes the palette.
Shift used with typing does not count; other keyboard keys leave drawing mode.

Set **Drawings stay (seconds)** in Overlay settings, or **Visible for** in the
palette, from 1 to 300 seconds (default 5). Each stroke's timer starts when you
finish drawing it. It then erases along its own path, from start to end, over
250ms. **Fade drawings without path motion** uses a gentle whole-stroke fade
instead. Color, width, duration, and preferences persist between launches;
changes apply to new strokes.

This uses the same `/dev/input` keyboard permissions described under keystrokes
below. Missing access is reported beside the pen switch. On Wayland, desktop
stacking requires a compositor supporting layer-shell and a LayerShellQt build.
Annotations are desktop overlays: monitor/region recordings include them, while
portal capture of a single application window may exclude them. The standalone
daemon/overlay launcher does not provide the pen; keep the native app running.

## Microphone

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

## After a recording

When a recording stops, the main window shows a **Recording saved** card with a
thumbnail, the file name, resolution, length, and size. Click the name (or the
pencil) to rename the file in place — the extension is kept, and a name that is
already taken is refused inline. **Open** plays the file, **Show in folder**
selects it in your file manager (through `org.freedesktop.FileManager1`, falling
back to opening the folder), **Trim** opens the editor, and the copy button puts
the path on the clipboard. The card stays for the last recording until you
dismiss it or start a new one; the Library and the tray menu also offer
**Show in folder** per recording.

## Trimming

After a recording is saved, choose **Trim**. The editor works on any video, not
only your recordings. Open one by:

- dropping a video file on the main window, the Library, or the editor itself,
- choosing **Edit video** in the main window, **Edit a video…** in the Library,
  or **Open…** in the editor header,
- picking **Open with → Remcorder** in your file manager.

The editor provides a video preview, the audio waveform, and a range slider.
Click or drag on the waveform to seek; the selected range is highlighted.
Export always creates a new file and never modifies the source. It is saved next
to the source, or in your recordings folder when the source folder is not
writable. Progress and completion show in both the main window and the tray,
and closing the window is safe because the export continues in the tray.

The **Audio** card lowers the volume of the copy (0 to 100%) or mutes it, which
drops the audio track entirely. The preview plays at the same volume once you
press Play, and the waveform scales to match. Files without audio show
**No audio track** and the card is disabled.

The editor also carries the experimental **Motion blur** toggle, which blends
successive frames as the copy is encoded. It is frame blending, not true motion
blur: scrolling and window drags look smoother, content that does not move stays
sharp, and very fast motion shows as a few ghost copies rather than a streak.
Subtle, Smooth, and Strong blend roughly 30, 50, and 85 ms of footage, so the
look is the same at any frame rate (2, 3, and 5 frames at 60 fps). Recordings
are resampled to a constant frame rate first so idle gaps are not blended.

**Preview at playhead** renders two seconds from the playhead with the chosen
strength, using hardware decoding when available. **Split** shows the original
on the left and the blurred result on the right; **Blurred** shows the whole
frame. Changing the strength re-renders the preview. Blur is a per-export
choice rather than a persistent setting, so nothing is processed unless you ask
for it. The result is named
`recording-trim.mp4`, or `recording-trim-blur.mp4` when blur is on.

You can also open the editor directly:

```sh
remcorder --trim /path/to/video.mp4
```

## CLI

```sh
remcorderctl start
remcorderctl status
remcorderctl pause
remcorderctl resume
remcorderctl toggle-pause
remcorderctl stop
remcorderctl discard                  # stop and delete the file instead of keeping it
remcorderctl toggle
remcorderctl rename "demo take"       # rename the last recording; the extension is kept
remcorderctl --json status
remcorderctl --delay 3s start
remcorderctl --open stop              # open the recording when it stops
remcorderctl --open-dir stop          # open the recording's folder when it stops
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

## Daemon options

To use portal selection by default from the CLI, put the following in
`~/.config/remcorder/daemon.env` (create the directory if needed):

```ini
REMCORDER_DAEMON_ARGS=-capture portal
```

Restart with `systemctl --user restart remcorder.service`. The app can override
these defaults per recording. Available daemon options:

```text
-capture screen|portal|region|DP-1
-region 1280x720+320+180
-fps 60
-audio default_output
-codec h264|hevc|av1
-quality medium|high|very_high|ultra
-output-dir /path/to/recordings
-cursor=true|false
-keystrokes=true|false
-keystroke-hold 2.5
-keystroke-limit 12
```

Run `gpu-screen-recorder --list-monitors` and
`gpu-screen-recorder --list-audio-devices` to discover exact source names.

## Keystroke overlay

For terminal and editor tutorials, the daemon can publish the keys you press so
they stack side by side and fade out once you stop typing.

In the app, flip **Show keystrokes** in the settings panel, the keyboard button
on the recording pill, or the tray menu — it also works mid-recording. The row
clears and starts again from the left once it has faded; **Keys fade after**
picks the hold time (1s to 10s). **Placement** chooses where the chips live:

- **Above pill** — a strip attached to the recording pill; the strip itself lets
  clicks through, only the pill takes input.
- **Floating** — a separate strip with a small keyboard handle that you can drag
  anywhere on screen, independent of the pill.

Everything is sent to the daemon per recording, so no restart is needed.

For `remcorderctl start` and other scripted recordings the daemon's own flags
set the default instead:

```sh
mkdir -p ~/.config/remcorder
${EDITOR:-vi} ~/.config/remcorder/daemon.env
systemctl --user restart remcorder.service
```

Set `REMCORDER_DAEMON_ARGS=-keystrokes` in that file, or add `-keystrokes` to
its existing arguments before restarting the service.

`-keystroke-hold` sets how many seconds the row stays up after the last press,
and `-keystroke-limit` caps how many keys sit side by side before the oldest
scroll off. The standalone `remcorder-overlay.service` renders the same snapshot
for sessions without the app; running it alongside the app shows two copies.

Modifiers fold into the key they belong to, so a chord reads as one chip
(`Ctrl+D`), and a held key collapses into a repeat count (`j ×7`) rather than a
row of duplicates. Shift is folded into the glyph itself, so vim commands read
back the way you typed them: `:wq`, not `Shift+; w q`.

**How it reads the keyboard.** Wayland gives no client access to keys it is not
focused for, so the daemon reads the evdev devices under `/dev/input` directly.
That needs membership of the `input` group:

```sh
sudo usermod -aG input "$USER"   # log out and back in
```

Without it the daemon logs `keystroke overlay unavailable` and records normally.
Because it reads the devices rather than the focused window, it also keeps
working while a fullscreen application holds an input grab.

For the keystroke overlay, keys are only read while a recording is actually running — the devices are
opened on start and closed on stop or pause — and they are never written
anywhere except the runtime snapshot the overlay polls. Note that this means
every keystroke typed into *any* application is shown while recording, including
passwords, so stop the recording before typing one.

The annotation pen also reads input while the native app is running when enabled.

Labels assume a US layout. evdev reports physical key positions, so on AZERTY or
Dvorak the chips show the key you pressed rather than the character it produced.

If a remapper such as `keyd` is active, the overlay shows the remapped keys,
which is what the applications on screen actually receive.

**Always on top.** Wayland compositors ignore the "stay on top" hint a client
asks for, so the recording pill, the floating keystroke strip and the standalone
overlay are created as `wlr-layer-shell` overlay surfaces instead (via
LayerShellQt, a Plasma library that also works on Hyprland, Sway, niri and other
wlroots compositors). The compositor keeps them above every other window,
fullscreen ones included, and they never take keyboard focus. The pill starts
centred above the bottom edge and the strip just above it; drag either one to
move it. On X11 the ordinary window flags already keep them on top. GNOME's
Mutter does not support layer-shell, so there the windows fall back to plain
floating windows that other windows can cover.

The shipped KWin rules in
`~/.local/share/remcorder/kwin/remcorder-overlay.kwinrule`
(or `/usr/share/remcorder/kwin/remcorder-overlay.kwinrule` for the Arch package) are only a fallback
for sessions where layer-shell is unavailable; import them via *System Settings
→ Window Management → Window Rules → Import* if you need them.

## Region capture

Pick **Region** under Capture and drag a rectangle; the overlay dims every
display, follows the drag across monitors, and shows the live pixel size. Esc or
right-click cancels. The chosen rectangle is stored as `WxH+X+Y` and reused
until you reselect, so a keybound `remcorderctl toggle` keeps recording the same
area. `-region` is only honoured when the capture source is `region`, and the
daemon refuses to start a region recording without one.

Coordinates follow the session: Wayland compositors are addressed in logical
coordinates (like `slurp`), X11 in device pixels (like `slop`).

## Webcam bubble and click highlights

Enable **Webcam bubble** under **Overlays** to show your camera above the desktop.
Choose its shape, size, corner, and whether to mirror the picture. Drag it to
reposition it. Monitor capture includes the bubble; region capture includes it
only when it sits inside the selected area. A portal recording of an application
window may leave it out.

**Highlight clicks** uses KWin's mouse click effect while recording. It requires
KDE Plasma; it is not a general click highlighter for every compositor.

[Back to the README](../README.md)
