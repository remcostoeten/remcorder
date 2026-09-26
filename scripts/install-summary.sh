#!/usr/bin/env bash
set -uo pipefail

prefix="${1:?usage: install-summary.sh <prefix>}"
bin_dir="$prefix/bin"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "$script_dir")"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    bold=$'\e[1m' dim=$'\e[2m' green=$'\e[32m' yellow=$'\e[33m' blue=$'\e[34m' cyan=$'\e[36m' reset=$'\e[0m'
else
    bold='' dim='' green='' yellow='' blue='' cyan='' reset=''
fi

function section() { printf '\n%s==>%s %s%s%s\n' "$blue" "$reset" "$bold" "$*" "$reset"; }
function ok() { printf '  %s✓%s %s\n' "$green" "$reset" "$*"; }
function warn() { printf '  %s!%s %s\n' "$yellow" "$reset" "$*"; }
function hint() { printf '    %s%s%s\n' "$dim" "$*" "$reset"; }
function cmd() { printf '    %s$%s %s%-48s%s %s%s%s\n' "$dim" "$reset" "$cyan" "$1" "$reset" "$dim" "$2" "$reset"; }

function short_path() {
    echo "${1/#$HOME/\~}"
}

function on_path() {
    [[ ":$PATH:" == *":$bin_dir:"* ]]
}

version="$(git -C "$repo_dir" describe --tags --always --dirty 2>/dev/null || echo unknown)"

printf '\n%s%s✓ Remcorder %s installed%s\n' "$bold" "$green" "$version" "$reset"

section "Installed"
ok "remcorder, remcorderd, remcorderctl  $(short_path "$bin_dir")"
ok "Desktop entry and icons              $(short_path "$prefix/share")"
ok "User services                        remcorder.service, remcorder-overlay.service"

section "Status"
if on_path; then
    ok "$(short_path "$bin_dir") is on your PATH"
else
    warn "$(short_path "$bin_dir") is not on your PATH"
    case "$(basename "${SHELL:-}")" in
        fish) hint "fish_add_path $(short_path "$bin_dir")" ;;
        zsh) hint "echo 'export PATH=\"$(short_path "$bin_dir"):\$PATH\"' >> ~/.zshrc" ;;
        *) hint "echo 'export PATH=\"$(short_path "$bin_dir"):\$PATH\"' >> ~/.bashrc" ;;
    esac
fi

daemon_enabled=0
if systemctl --user is-active --quiet remcorder.service; then
    ok "Daemon is running (restarted with the new build)"
    systemctl --user is-enabled --quiet remcorder.service && daemon_enabled=1
elif systemctl --user is-enabled --quiet remcorder.service; then
    daemon_enabled=1
    warn "Daemon is enabled but not running"
    hint "systemctl --user start remcorder.service"
else
    warn "Daemon is not enabled yet"
fi

section "Next steps"
if (( ! daemon_enabled )); then
    cmd "systemctl --user enable --now remcorder.service" "start the daemon now and at login"
fi
cmd "remcorder" "open the app (or find it in your app menu)"
cmd "remcorder --tray" "start minimised to the tray"
cmd "remcorderctl toggle" "start/stop recording; bind it to a shortcut"
cmd "make tray" "autostart the tray app at login"
cmd "make uninstall" "remove everything again"
echo
