# Contributing

Bug reports and small, focused pull requests are welcome. For a larger change,
open an issue first so we can agree on the scope.

## Build and run

Follow the [source installation instructions](README.md#from-source) to install
dependencies. The prerequisite script installs packages; review its package list
before running it.

```sh
make check
make
./remcorderd
```

In a second terminal, run `./build/remcorder`. If the installed user service is
already running, use that instead of starting another daemon. Neither opening
the app nor starting the daemon begins a recording.

## Source layout

| Directory | Contents |
| --- | --- |
| `app/` | Qt C++ backend and QML interface |
| `cmd/remcorderd/` | Recording daemon |
| `cmd/remcorderctl/` | CLI client |
| `internal/` | Recorder engine, control protocol, and keyboard input |
| `overlay/` | Standalone QML recording indicator |
| `packaging/` | Arch package, desktop entries, icons, and KWin rules |
| `systemd/` | User service units |
| `tests/` | Qt annotation tests |

## Before opening a pull request

Branch from `daddy` and keep each PR about one change. Explain the problem,
what changes for the user, and how you checked it. Include a screenshot for
visible UI changes and mention the desktop/compositor you tested on.

Run `make check` before submitting. For changes to annotations, also run:

```sh
cmake -S . -B build -DREMCORDER_BUILD_TESTS=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

Follow the surrounding code style. Use names and structure to explain code;
reserve comments for workarounds and public helper documentation. Don't leave
empty error handlers. Use a conventional commit subject such as
`fix(app): keep the selected microphone after restart`.

Keep generated builds and recordings out of Git. Update the user guide when
controls or command-line options change.

## Reporting a bug

Include the Remcorder version, distribution, GPU and driver, desktop/compositor,
and whether you use Wayland or X11. Describe the steps, what you expected, and
what happened. Useful diagnostics:

```sh
remcorderctl --json status
journalctl --user -u remcorder.service -b --no-pager -n 100
```

Check logs and screenshots for private paths or captured keystrokes before posting.
