#!/usr/bin/env bash
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(dirname "$script_dir")"
config="$script_dir/packages.conf"

assume_yes=0
check_only=0
failures=0
warnings=0

function usage() {
    cat <<EOF
Usage: scripts/pre-reqs.sh [options]

Installs Remcorder's build and runtime dependencies with your distro's package
manager, then checks that every tool is present and new enough.

Options:
  -y, --yes     Don't ask for confirmation (for CI and scripted installs)
  -c, --check   Only check prerequisites; install nothing
  -h, --help    Show this help
EOF
}

while (( $# )); do
    case "$1" in
        -y|--yes) assume_yes=1 ;;
        -c|--check) check_only=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    bold=$'\e[1m' dim=$'\e[2m' red=$'\e[31m' green=$'\e[32m' yellow=$'\e[33m' blue=$'\e[34m' reset=$'\e[0m'
else
    bold='' dim='' red='' green='' yellow='' blue='' reset=''
fi

function section() { printf '\n%s==>%s %s%s%s\n' "$blue" "$reset" "$bold" "$*" "$reset"; }
function info() { printf '    %s\n' "$*"; }
function ok() { printf '  %s✓%s %s\n' "$green" "$reset" "$*"; }
function warn() { printf '  %s!%s %s\n' "$yellow" "$reset" "$*"; warnings=$((warnings + 1)); }
function fail() { printf '  %s✗%s %s\n' "$red" "$reset" "$*"; failures=$((failures + 1)); }
function hint() { printf '    %s%s%s\n' "$dim" "$*" "$reset"; }
function die() { printf '\n%s✗ %s%s\n' "$red" "$*" "$reset" >&2; exit 1; }

function trim() {
    local value="$*"
    value="${value#"${value%%[![:space:]]*}"}"
    echo "${value%"${value##*[![:space:]]}"}"
}

function have() {
    command -v "$1" >/dev/null 2>&1
}

function ask() {
    local question="$1" default="${2:-y}" answer
    if (( assume_yes )); then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        [[ "$default" == y ]]
        return
    fi
    local choices="[Y/n]"
    [[ "$default" == n ]] && choices="[y/N]"
    read -r -p "$(printf '  %s?%s %s %s ' "$yellow" "$reset" "$question" "$choices")" answer
    answer="${answer:-$default}"
    [[ "${answer,,}" == y* ]]
}

function as_root() {
    if (( EUID == 0 )); then
        "$@"
    elif have sudo; then
        sudo "$@"
    elif have doas; then
        doas "$@"
    else
        die "Need root to run '$*', but neither sudo nor doas is installed."
    fi
}

function version_at_least() {
    local have_version="$1" want_version="$2"
    [[ "$(printf '%s\n%s\n' "$want_version" "$have_version" | sort -V | head -n1)" == "$want_version" ]]
}

function required_qt() {
    sed -nE 's/.*find_package\(Qt6[[:space:]]+([0-9.]+).*/\1/p' "$repo_dir/CMakeLists.txt" | head -n1
}

function required_cmake() {
    sed -nE 's/.*cmake_minimum_required\(VERSION[[:space:]]+([0-9.]+).*/\1/p' "$repo_dir/CMakeLists.txt" | head -n1
}

function required_go() {
    sed -nE 's/^go[[:space:]]+([0-9.]+).*/\1/p' "$repo_dir/go.mod" | head -n1
}

function detect_distro() {
    distro_ids=""
    distro_name="unknown"
    distro_id=""
    [[ -r /etc/os-release ]] || return 0
    {
        read -r distro_id
        read -r distro_ids
        read -r distro_name
    } < <(
        # shellcheck disable=SC1091
        source /etc/os-release
        echo "${ID:-}"
        trim "${ID:-} ${ID_LIKE:-}"
        echo "${PRETTY_NAME:-${NAME:-unknown}}"
    )
}

function find_route() {
    local ids=" $distro_ids "
    local route_ids manager packages route_id
    while IFS='|' read -r route_ids manager packages; do
        route_ids="$(trim "$route_ids")"
        [[ -z "$route_ids" || "$route_ids" == \#* ]] && continue
        for route_id in $route_ids; do
            if [[ "$ids" == *" $route_id "* ]]; then
                route_manager="$(trim "$manager")"
                read -r -a route_packages <<< "$packages"
                return 0
            fi
        done
    done < "$config"
    return 1
}

function pm_refresh() {
    case "$route_manager" in
        apt) as_root apt-get update -qq ;;
        dnf) as_root dnf -q makecache >/dev/null ;;
        zypper) as_root zypper --non-interactive --quiet refresh ;;
        pacman) [[ -n "$(pacman -Sl 2>/dev/null | head -n1)" ]] || as_root pacman -Sy ;;
    esac
}

function pm_installed() {
    case "$route_manager" in
        pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
        apt) [[ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" == "install ok installed" ]] ;;
        dnf|zypper) rpm -q --whatprovides "$1" >/dev/null 2>&1 ;;
    esac
}

function pm_available() {
    case "$route_manager" in
        pacman) pacman -Si "$1" >/dev/null 2>&1 ;;
        apt) [[ -n "$(apt_candidate_version "$1")" ]] ;;
        dnf) [[ -n "$(dnf -q repoquery --available "$1" 2>/dev/null)" ]] ;;
        zypper) zypper --non-interactive --quiet search --match-exact "$1" >/dev/null 2>&1 ;;
    esac
}

function pm_install() {
    case "$route_manager" in
        pacman) as_root pacman -S --needed --noconfirm "$@" ;;
        apt) as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        dnf) as_root dnf install -y "$@" ;;
        zypper) as_root zypper --non-interactive install "$@" ;;
    esac
}

function apt_candidate_version() {
    apt-cache policy "$1" 2>/dev/null | sed -nE '/Candidate: \(none\)/d; s/.*Candidate: ([0-9]+:)?([0-9.]+).*/\2/p'
}

function preflight_qt_version() {
    [[ "$route_manager" == apt ]] || return 0
    local candidate want
    candidate="$(apt_candidate_version qt6-base-dev)"
    want="$(required_qt)"
    [[ -n "$candidate" && -n "$want" ]] || return 0
    if ! version_at_least "$candidate" "$want"; then
        fail "$distro_name ships Qt $candidate; Remcorder needs Qt $want or newer."
        hint "Use Debian 13+, Ubuntu 25.04+, or a distro with a newer Qt. Nothing was installed."
        exit 1
    fi
}

function offer_rpmfusion() {
    [[ "$distro_id" == fedora ]] || return 0
    pm_installed ffmpeg && return 0
    pm_available ffmpeg && return 0
    warn "Fedora's own ffmpeg-free lacks the libx264 encoder that trim and motion blur use."
    if ask "Enable RPM Fusion (free) to get the full ffmpeg?"; then
        local release
        release="$(rpm -E %fedora)"
        if as_root dnf install -y \
            "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$release.noarch.rpm"; then
            ok "RPM Fusion enabled"
            as_root dnf -q makecache >/dev/null
            if pm_installed ffmpeg-free; then
                as_root dnf swap -y ffmpeg-free ffmpeg --allowerasing \
                    || warn "Couldn't swap ffmpeg-free for ffmpeg; run 'sudo dnf swap ffmpeg-free ffmpeg --allowerasing'"
            fi
        else
            warn "Couldn't enable RPM Fusion; falling back to ffmpeg-free"
        fi
    fi
}

function resolve_packages() {
    to_install=()
    unavailable=()
    local entry candidate chosen already
    for entry in "${route_packages[@]}"; do
        chosen=""
        already=""
        IFS='/' read -r -a candidates <<< "$entry"
        for candidate in "${candidates[@]}"; do
            if pm_installed "$candidate"; then
                already="$candidate"
                break
            fi
        done
        if [[ -n "$already" ]]; then
            printf '  %s✓%s %s %s(installed)%s\n' "$green" "$reset" "$already" "$dim" "$reset"
            continue
        fi
        for candidate in "${candidates[@]}"; do
            if pm_available "$candidate"; then
                chosen="$candidate"
                break
            fi
        done
        if [[ -n "$chosen" ]]; then
            printf '  %s+%s %s\n' "$blue" "$reset" "$chosen"
            to_install+=("$chosen")
        else
            printf '  %s✗%s %s %s(not in your repositories)%s\n' "$red" "$reset" "${entry//\// or }" "$dim" "$reset"
            unavailable+=("$entry")
        fi
    done
}

function install_packages() {
    section "Checking packages ($route_manager)"
    info "Refreshing package index…"
    pm_refresh || warn "Couldn't refresh the package index; results may be stale"

    preflight_qt_version
    offer_rpmfusion

    resolve_packages

    if (( ${#unavailable[@]} )); then
        warn "${#unavailable[@]} package(s) aren't in your repositories: ${unavailable[*]}"
        hint "The checks below will show whether anything important is actually missing."
    fi

    if (( ! ${#to_install[@]} )); then
        ok "All packages already installed"
        return
    fi

    section "Installing ${#to_install[@]} package(s)"
    info "${to_install[*]}"
    if ! ask "Install them now?"; then
        warn "Skipped package installation"
        return
    fi
    if pm_install "${to_install[@]}"; then
        ok "Packages installed"
        return
    fi

    warn "Batch install failed; retrying one package at a time"
    local package output line
    for package in "${to_install[@]}"; do
        if output="$(pm_install "$package" 2>&1)"; then
            ok "$package"
        else
            fail "$package failed to install:"
            while IFS= read -r line; do
                hint "$line"
            done < <(printf '%s\n' "$output" | grep -v '^[[:space:]]*$' | tail -n 4)
        fi
    done
}

function offer_gpu_screen_recorder() {
    have gpu-screen-recorder && return 0
    [[ "$distro_id" == fedora ]] || return 0
    section "gpu-screen-recorder"
    info "Fedora doesn't package it; a community COPR (brycensranch/gpu-screen-recorder-git) does."
    if ask "Enable the COPR and install gpu-screen-recorder?"; then
        if as_root dnf copr enable -y brycensranch/gpu-screen-recorder-git \
            && as_root dnf install -y gpu-screen-recorder; then
            ok "gpu-screen-recorder installed"
        else
            warn "COPR install failed"
        fi
    fi
}

function in_input_group() {
    [[ " $(id -nG "$1" 2>/dev/null) " == *" input "* ]]
}

function target_user() {
    echo "${SUDO_USER:-${USER:-$(id -un)}}"
}

function offer_input_group() {
    local user
    user="$(target_user)"
    [[ "$user" == root ]] && return 0
    getent group input >/dev/null || return 0
    in_input_group "$user" && return 0
    section "Keystroke overlay access"
    info "The keystroke overlay reads /dev/input, which needs '$user' in the 'input' group."
    if ask "Add '$user' to the input group?"; then
        if as_root usermod -aG input "$user"; then
            ok "Added '$user' to input (log out and back in for it to apply)"
        else
            warn "Couldn't add '$user' to input"
        fi
    fi
}

function qt_version() {
    local tool
    if have pkg-config && pkg-config --exists Qt6Core 2>/dev/null; then
        pkg-config --modversion Qt6Core
        return
    fi
    for tool in qmake6 qmake-qt6 /usr/lib/qt6/bin/qmake /usr/lib64/qt6/bin/qmake; do
        if have "$tool"; then
            "$tool" -query QT_VERSION
            return
        fi
    done
}

function find_qmllint() {
    local tool
    for tool in qmllint6 qmllint-qt6 qmllint /usr/lib/qt6/bin/qmllint /usr/lib64/qt6/bin/qmllint; do
        if have "$tool"; then
            echo "$tool"
            return
        fi
    done
}

function check_versioned() {
    local label="$1" have_version="$2" want_version="$3" missing_hint="$4"
    if [[ -z "$have_version" ]]; then
        fail "$label not found"
        hint "$missing_hint"
    elif version_at_least "$have_version" "$want_version"; then
        ok "$label $have_version"
    else
        fail "$label $have_version is too old (need $want_version+)"
        hint "$missing_hint"
    fi
}

function verify() {
    section "Build tools"

    local cmake_version="" go_version="" want_go
    have cmake && cmake_version="$(cmake --version | sed -nE '1s/.* ([0-9][0-9.]*).*/\1/p')"
    check_versioned CMake "$cmake_version" "$(required_cmake)" "Install CMake $(required_cmake) or newer."

    if have g++; then
        ok "C++ compiler: g++ $(g++ -dumpfullversion 2>/dev/null)"
    elif have clang++; then
        ok "C++ compiler: $(clang++ --version | head -n1)"
    else
        fail "No C++ compiler"
        hint "Install g++ or clang++."
    fi

    want_go="$(required_go)"
    have go && go_version="$(go env GOVERSION 2>/dev/null | sed -E 's/^go//; s/[^0-9.].*//')"
    if [[ -z "$go_version" ]]; then
        fail "Go not found"
        hint "Install Go $want_go or newer."
    elif version_at_least "$go_version" "$want_go"; then
        ok "Go $go_version"
    elif version_at_least "$go_version" 1.21 && [[ "$(go env GOTOOLCHAIN)" != local* ]]; then
        ok "Go $go_version (will download go$want_go on first build; needs network)"
    else
        fail "Go $go_version is too old (need $want_go+)"
        hint "Install a newer Go from https://go.dev/dl/."
    fi

    check_versioned "Qt" "$(qt_version)" "$(required_qt)" \
        "Install Qt $(required_qt)+ development packages (Debian 13+, Ubuntu 25.04+, Fedora, Arch, Tumbleweed)."

    local qmllint
    qmllint="$(find_qmllint)"
    if [[ -n "$qmllint" ]]; then
        ok "qmllint ($qmllint)"
    else
        fail "qmllint not found (make check/install run it)"
        hint "Install your distro's Qt 6 declarative tools package."
    fi

    section "Runtime"

    if have gpu-screen-recorder; then
        ok "gpu-screen-recorder"
    else
        fail "gpu-screen-recorder not found; Remcorder can't record without it"
        hint "Build it from https://git.dec05eba.com/gpu-screen-recorder/about/ (the Flatpak alone doesn't provide the CLI)."
    fi

    local runner
    if runner="$("$script_dir/remcorder-overlay" --which 2>/dev/null)"; then
        ok "Qt 6 QML runner ($runner)"
    else
        fail "No Qt 6 QML runner (qml6, qml-qt6, or qml)"
        hint "Install your distro's Qt 6 declarative tools package."
    fi

    if ! have ffmpeg; then
        warn "ffmpeg not found; trim and motion blur won't work"
    elif [[ "$(ffmpeg -hide_banner -encoders 2>/dev/null)" == *libx264* ]]; then
        ok "ffmpeg (with libx264)"
    else
        warn "ffmpeg has no libx264 encoder; trim and motion blur will fail"
        case " $distro_ids " in
            *" fedora "*) hint "Enable RPM Fusion and run 'sudo dnf swap ffmpeg-free ffmpeg --allowerasing'." ;;
            *" suse "*|*" opensuse "*) hint "Install ffmpeg from the Packman repository: https://en.opensuse.org/Additional_package_repositories#Packman" ;;
        esac
    fi

    if have pactl; then
        ok "pactl"
    else
        warn "pactl not found; the microphone meter and gain won't work"
    fi

    local user
    user="$(target_user)"
    if [[ "$user" == root ]] || in_input_group "$user"; then
        ok "Input access for the keystroke overlay"
    else
        warn "'$user' isn't in the input group; the keystroke overlay won't see key presses"
        hint "sudo usermod -aG input $user, then log out and back in."
    fi
}

function summary() {
    echo
    if (( failures )); then
        printf '%s%s✗ %d required prerequisite(s) missing%s' "$bold" "$red" "$failures" "$reset"
        (( warnings )) && printf ', %d warning(s)' "$warnings"
        printf '\n  Fix the items marked ✗ above and re-run %s.\n' "scripts/pre-reqs.sh"
        exit 1
    fi
    if (( warnings )); then
        printf '%s%s✓ Ready to build%s, with %d warning(s) above.\n' "$bold" "$green" "$reset" "$warnings"
    else
        printf '%s%s✓ All prerequisites are present.%s\n' "$bold" "$green" "$reset"
    fi
    printf '  Next: %smake install%s\n' "$bold" "$reset"
}

detect_distro
printf '%sRemcorder prerequisites%s\n' "$bold" "$reset"
info "System: $distro_name ${dim}($distro_ids)${reset}"

if (( ! check_only )); then
    if find_route; then
        info "Package manager: $route_manager"
        install_packages
        offer_gpu_screen_recorder
        offer_input_group
    else
        section "Packages"
        warn "No package list for '$distro_ids' in scripts/packages.conf"
        hint "Install the equivalents of the Arch or Debian list there by hand, or add a route."
    fi
fi

warnings=0
verify
summary
