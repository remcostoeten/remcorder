# Remcorder public release — draft

Remcorder is a screen recorder for Linux built around gpu-screen-recorder.
Use the Qt app, keep it in the tray, or bind the CLI to your own shortcuts.
A separate background service keeps recording when the window closes.

## Included

- Monitor, region, and portal capture, with frame rate, codec, and quality controls.
- Desktop audio and microphone input, with a live meter and gain control.
- Pause and resume, start delays, sound cues, and a floating recording pill.
- Optional keystrokes, screen annotations, webcam bubble, and KWin click highlights.
- A recording library and saved-file actions for opening, renaming, and trimming clips.
- Trim exports that preserve the original, with an experimental motion-blur option.
- An Arch Linux package, source installation, and systemd user services.

## Installation

Download the Arch `.pkg.tar.zst` asset and install it with `sudo pacman -U`,
then enable the daemon with `systemctl --user enable --now remcorder.service`.
Launch **Remcorder** from your application menu.

For other distributions, follow the source instructions in the repository README.

## Known limits

- GPU, driver, and desktop support depend on gpu-screen-recorder.
- Wayland overlays need LayerShellQt and layer-shell support to stay on top.
- Keystrokes and annotations need input-device permissions. Keystroke labels assume a US layout.
- Keystrokes from any application can appear in the recording, including passwords.
- Click highlights require KWin. Motion blur is experimental.
- A portal capture of one application window may exclude desktop overlays.

Please include your distribution, desktop, GPU, driver, and session type when
reporting a problem.
