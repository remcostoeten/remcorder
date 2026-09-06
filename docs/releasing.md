# Releasing Remcorder

## Release materials

| File | Use |
| --- | --- |
| [`assets/readme-banner.png`](assets/readme-banner.png) | README header, 1600 × 480 |
| [`assets/social-preview.png`](assets/social-preview.png) | Repository social preview and announcement card, 1280 × 640 |
| [`assets/app.png`](assets/app.png) | Actual app window captured with clean settings on a virtual X11 display |
| [`assets/readme-banner.svg`](assets/readme-banner.svg) | Editable banner source |
| [`assets/social-preview.svg`](assets/social-preview.svg) | Editable social card source |
| [`../packaging/icons/remcorder-512.png`](../packaging/icons/remcorder-512.png) | Existing application icon; smaller and tray sizes are alongside it |
| [`release-notes.md`](release-notes.md) | Draft notes for the public release |

Artwork uses the existing application mark. The SVGs embed their images and can
be opened without external image files. Render sources and PNGs together with:

```sh
python3 scripts/render-release-assets.py
```

This needs Python 3, `rsvg-convert` (librsvg), and the Inter and JetBrains Mono
fonts used by the app. The script doesn't alter the application icons or screenshot.

The screenshot shows the real Qt app with default settings and an idle daemon.
It was captured under Xvfb with the software renderer and isolated XDG config,
data, and runtime directories. It demonstrates the interface, not capture
compatibility with a physical GPU or desktop. Refresh it after visible UI changes.

For the repository social preview, upload `social-preview.png` in the repository's
settings. Suggested repository description:

> Linux screen recorder with a Qt interface, tray controls, keyboard shortcuts, and a trim editor. Powered by gpu-screen-recorder.

Suggested topics: `linux`, `screen-recorder`, `qt6`, `qml`, `golang`, `wayland`.

## Before the public release

- Run `make check` on the revision being released.
- Test an installed package: record, pause, resume, stop, play the result, and export a trim.
- Check monitor and region capture on the desktops and GPUs you intend to support.
- Try portal capture, microphone audio, and tray behavior in a real desktop session.
- Check the optional overlays and their input permissions; avoid recording private input.
- Review the draft release notes and refresh the screenshot if the UI changed.
- Confirm repository visibility, then check the download links while signed out.

The local checks do not establish hardware capture compatibility. Record which
GPU, driver, desktop, and session type were used for the release smoke test.

## Cut a release

Use the project's `releaser` tool, configured in
[`releaser.config.json`](../releaser.config.json). It reads `pkgver` from the
PKGBUILD and updates the CMake version to match. Start from a clean `daddy`
branch in sync with origin:

```sh
releaser plan --bump patch
releaser --bump patch
```

The second command updates versions, commits, tags, and pushes. Choose the bump
for the intended release; don't edit `pkgver` or create the tag separately.
For an interrupted release, use `releaser status` and `releaser resume`.

The tag triggers the Release workflow. It runs checks, creates the source
archive, builds an Arch package, and uploads the package, source archive,
PKGBUILD, and SHA-256 checksums. Check that the workflow succeeds and the files
are downloadable before announcing the release. Add the reviewed release notes
to that release.

CI builds inside Arch Linux. Both workflows install LayerShellQt so that checks
exercise the overlay-enabled build and the release meets its package dependencies.
The release job's Git safe-directory setup and `GOFLAGS=-buildvcs=false` in the
PKGBUILD are required for the container's ownership and source-archive build.

## Announcement draft

> Remcorder is a screen recorder for Linux. It has a small Qt window, tray
> controls, and a CLI you can bind to keyboard shortcuts. Recording runs in a
> background service, so you can close the window and keep going. There are
> options for microphone audio, on-screen keystrokes, annotations, and a webcam
> bubble, plus a trim editor for cutting the finished clip.
>
> Source and installation: https://github.com/remcostoeten/remcorder

Attach `assets/social-preview.png` when posting. Release creation, repository
visibility, social-preview upload, and announcements are separate publishing steps.
