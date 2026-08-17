#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config="$script_dir/packages.conf"

function detect_ids() {
    if [[ ! -r /etc/os-release ]]; then
        return
    fi
    # shellcheck disable=SC1091
    source /etc/os-release
    echo "${ID:-} ${ID_LIKE:-}"
}

function find_route() {
    local ids=" $1 "
    while IFS='|' read -r route_ids install packages; do
        route_ids="$(echo "$route_ids" | xargs)"
        [[ -z "$route_ids" || "$route_ids" == \#* ]] && continue
        local route_id
        for route_id in $route_ids; do
            if [[ "$ids" == *" $route_id "* ]]; then
                printf '%s|%s\n' "$(echo "$install" | xargs)" "$(echo "$packages" | xargs)"
                return
            fi
        done
    done < "$config"
}

function have() {
    command -v "$1" >/dev/null 2>&1
}

function verify() {
    local missing=0

    function report() {
        echo "missing: $1" >&2
        echo "         $2" >&2
        missing=1
    }

    have cmake || report cmake "install CMake 3.21+"
    have go || report go "install Go 1.26+"
    have g++ || have clang++ || report "C++ compiler" "install g++ or clang++"
    have ffmpeg || report ffmpeg "needed for the motion-blur and trim features"
    have pactl || report pactl "needed for the microphone meter and gain (PipeWire/PulseAudio utils)"
    have gpu-screen-recorder || report gpu-screen-recorder \
        "not packaged on most distros; see https://git.dec05eba.com/gpu-screen-recorder/ or Flathub (com.dec05eba.gpu_screen_recorder)"
    "$script_dir/remcorder-overlay" --which >/dev/null 2>&1 \
        || report "Qt 6 QML runner" "install the Qt 6 declarative package (qml6/qml-qt6)"

    if (( missing )); then
        echo >&2
        echo "Some prerequisites are missing; install them and re-run this script." >&2
        exit 1
    fi
    echo "All prerequisites are present."
}

ids="$(detect_ids | xargs)"
route="$(find_route "$ids" || true)"

if [[ -n "$route" ]]; then
    install_command="${route%%|*}"
    packages="${route#*|}"
    echo "Detected distro IDs: $ids"
    echo "Installing via: $install_command $packages"
    # shellcheck disable=SC2086
    $install_command $packages
else
    echo "No package route for distro IDs '$ids' in $config." >&2
    echo "Add one, or install the equivalents of the listed packages manually." >&2
fi

verify
