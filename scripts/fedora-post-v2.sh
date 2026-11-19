#!/usr/bin/env bash
# Fedora Post-Install for traditional, DNF5-based Fedora installations.
set -o pipefail

VERSION=2.0.0
mode=dry-run
mode_option=
ui=auto
log_file=
failed=0
completed=0
skipped=0
previewed=0
issues=()

tools=(git wget curl python3 python3-pip zip unzip vim bat neovim eza tree nodejs)
terminal=(btop kitty zsh fzf cmatrix yazi)
desktop=(telegram-desktop discord qbittorrent flameshot okular kate)
media=(gimp krita vlc obs-studio kdenlive blender)
network=(gvfs-smb gvfs-nfs samba-client nfs-utils avahi nss-mdns rpcbind rsync)
storage=(restic rclone btrfs-assistant flatpak)
apps=(org.onlyoffice.desktopeditors md.obsidian.Obsidian com.bitwarden.desktop com.visualstudio.code)
flathub_url=https://dl.flathub.org/repo/flathub.flatpakrepo

usage() {
    cat <<'EOF'
Fedora-Post v2.0.0
Usage: bash fedora-post-v2.sh [--dry-run | --apply] [--classic | --modern]

  --dry-run   Show commands without executing them (default)
  --apply     Enable changes after explicit confirmation
  --classic   Use the numbered menu
  --modern    Use gum when installed and running in a terminal
  --version   Show version
  --help      Show help

Run as a regular user. RPM operations use sudo; Flatpak changes use --user.
Logs are stored under $XDG_STATE_HOME/fedora-post (default ~/.local/state).
Exit status: 0 = no failures, 1 = operation failed, 2 = startup/usage error.
EOF
}

die() {
    printf '%s\n' "$*" >&2
    exit 2
}

while (($#)); do
    case "$1" in
    --dry-run | --apply)
        [[ -z $mode_option || $mode == "${1#--}" ]] || die 'Choose only one run mode.'
        mode=${1#--}
        mode_option=1
        ;;
    --classic | --modern) ui=${1#--} ;;
    --version)
        printf 'Fedora-Post v%s\n' "$VERSION"
        exit 0
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *) die "Unknown option: $1" ;;
    esac
    shift
done

say() {
    printf '%s\n' "$*"
    printf '[%(%F %T)T] %s\n' -1 "$*" >>"$log_file" ||
        die 'Could not write to the log.'
}

record() {
    local status=$1 label=$2
    case "$status" in
    FAILED)
        ((failed += 1))
        issues+=("$label")
        ;;
    DONE) ((completed += 1)) ;;
    SKIPPED) ((skipped += 1)) ;;
    PREVIEW) ((previewed += 1)) ;;
    esac
    say "$status | $label"
    return 0
}

summary() {
    say ''
    say "Completed: $completed | Previewed: $previewed | Skipped: $skipped | Failed: $failed"
    local issue
    for issue in "${issues[@]}"; do
        say "  - $issue"
    done
    say "Log: $log_file"
}

confirm() {
    local answer
    [[ $mode == dry-run ]] && return 0
    printf '%s Type YES to continue: ' "$1"
    IFS= read -r answer && [[ $answer == YES ]]
}

run_step() {
    local label=$1
    shift
    local command_line
    local -a statuses
    printf -v command_line '%q ' "$@"
    say "$ $command_line"
    if [[ $mode == dry-run ]]; then
        record PREVIEW "$label"
        return 0
    fi

    # Keep stdin available for sudo and package-manager transaction prompts.
    "$@" 2>&1 | tee -a "$log_file"
    statuses=("${PIPESTATUS[@]}")
    if ((statuses[1] != 0)); then
        die 'Could not capture command output. Check the transaction before retrying.'
    fi
    if ((statuses[0] != 0)); then
        record FAILED "$label (exit ${statuses[0]})"
        ((statuses[0] == 130)) && exit 130
        return 1
    fi
    record DONE "$label"
}

action() {
    local label=$1
    shift
    if confirm "$label?"; then
        run_step "$label" "$@"
    else
        record SKIPPED "$label (confirmation declined)"
        return 1
    fi
}

install_rpms() {
    local label=$1 package
    shift
    local -a pending=()
    for package in "$@"; do
        if rpm -q --quiet "$package"; then
            record SKIPPED "$package (already installed)"
        else
            pending+=("$package")
        fi
    done
    (("${#pending[@]}")) || return 0

    say "$label: ${pending[*]}"
    case " ${pending[*]} " in
    *' yazi '*) say 'Yazi may require the optional lihaohong/yazi COPR.' ;;
    esac
    case " ${pending[*]} " in
    *' discord '*) say 'The Discord RPM may require RPM Fusion Nonfree.' ;;
    esac
    if ! confirm "Install these RPM packages?"; then
        record SKIPPED "$label (confirmation declined)"
        return
    fi

    # Individual transactions keep unavailable packages from blocking the rest.
    for package in "${pending[@]}"; do
        if rpm -q --quiet "$package"; then
            record SKIPPED "$package (installed as a dependency)"
        else
            run_step "$package" sudo dnf5 --setopt=assumeyes=False install "$package" || :
        fi
    done
}

rpmfusion() {
    local variant=$1 package="rpmfusion-$1-release"
    if rpm -q --quiet "$package"; then
        record SKIPPED "$package (release package already installed)"
        return
    fi
    action "Install RPM Fusion $variant repository configuration" \
        sudo dnf5 --setopt=assumeyes=False install \
        "https://mirrors.rpmfusion.org/$variant/fedora/$package-$fedora_release.noarch.rpm"
}

dnf_plugin_action() {
    local label=$1
    shift
    if ! confirm "$label?"; then
        record SKIPPED "$label (confirmation declined)"
        return
    fi
    # COPR and config-manager are provided by the DNF5 plugin package.
    if ! rpm -q --quiet dnf5-plugins; then
        run_step 'Install DNF5 plugins' sudo dnf5 --setopt=assumeyes=False install dnf5-plugins ||
            {
                record SKIPPED "$label (DNF5 plugins unavailable)"
                return
            }
    fi
    run_step "$label" sudo dnf5 "$@"
}

flatpak_available() {
    if command -v flatpak >/dev/null; then
        return 0
    fi
    if [[ $mode == dry-run ]]; then
        say 'Flatpak must be installed before these commands can run.'
        return 0
    fi
    record FAILED 'Flatpak is unavailable. Install the flatpak RPM in the Storage category.'
    return 1
}

install_apps() {
    flatpak_available || return
    local app remotes=
    local -a pending=()
    for app in "${apps[@]}"; do
        if command -v flatpak >/dev/null &&
            { flatpak info --user "$app" >/dev/null 2>&1 ||
                flatpak info --system "$app" >/dev/null 2>&1; }; then
            record SKIPPED "$app (already installed)"
        else
            pending+=("$app")
        fi
    done
    (("${#pending[@]}")) || return 0

    if command -v flatpak >/dev/null; then
        remotes=$(flatpak remotes --user --columns=name) || {
            record FAILED 'Could not list user Flatpak remotes'
            return
        }
    fi
    if [[ $'\n'$remotes$'\n' != *$'\n'flathub$'\n'* ]]; then
        if [[ $mode == apply ]]; then
            record SKIPPED 'Flatpak apps (add Flathub from the menu first)'
            return
        fi
        say 'The following commands require the Flathub user remote.'
    fi
    say "Flatpak apps: ${pending[*]}"
    if ! confirm 'Install these Flatpak apps for this user?'; then
        record SKIPPED 'Flatpak apps (confirmation declined)'
        return
    fi
    for app in "${pending[@]}"; do
        run_step "$app" flatpak install --user --app flathub "$app" || :
    done
}

ffmpeg_action() {
    if rpm -q --quiet ffmpeg; then
        record SKIPPED 'Full FFmpeg is already installed'
    elif rpm -q --quiet ffmpeg-free; then
        action 'Replace ffmpeg-free with FFmpeg (DNF may propose dependency removals)' \
            sudo dnf5 --setopt=assumeyes=False swap ffmpeg-free ffmpeg --allowerasing
    else
        action 'Install full FFmpeg from RPM Fusion' \
            sudo dnf5 --setopt=assumeyes=False install ffmpeg
    fi
}

choices=(
    '1) Development and CLI tools'
    '2) Terminal and shell'
    '3) Desktop apps'
    '4) Graphics and media apps'
    '5) Network and file sharing'
    '6) Storage, backup and Flatpak'
    '7) Install all RPM categories'
    '8) Install Flatpak apps'
    '9) Add Flathub for this user'
    '10) Install RPM Fusion Free repository'
    '11) Install RPM Fusion Nonfree repository'
    '12) Enable COPR lihaohong/yazi'
    '13) Enable Fedora Cisco OpenH264'
    '14) Install full FFmpeg'
    '15) Upgrade Fedora Multimedia group'
    '16) Install Intel media driver'
    '17) Upgrade Fedora RPM packages'
    '18) Update user Flatpaks'
    '19) Remove unneeded RPM dependencies'
    '20) Clean DNF cache'
    '21) Remove unused user Flatpak runtimes'
    '0) Finish and show report'
)

choose_action() {
    local item result
    if [[ $ui == modern ]]; then
        item=$(gum choose --header "Fedora-Post $VERSION / $mode" "${choices[@]}")
        result=$?
        if ((result == 130)); then
            return 130
        fi
        if ((result != 0)) || [[ -z $item ]]; then
            return 1
        fi
        choice=${item%%)*}
    else
        printf '\n'
        printf '  %s\n' "${choices[@]}"
        printf 'Select an action: '
        IFS= read -r choice || return 1
    fi
}

main() {
    # The system checks precede logging and any privileged operation.
    [[ -r /etc/os-release ]] || die 'Could not identify the operating system.'
    local ID=
    . /etc/os-release
    [[ $ID == fedora ]] || die 'This script requires Fedora Linux.'
    [[ ! -e /run/ostree-booted ]] || die 'This script requires a traditional DNF5-based Fedora installation.'
    ((EUID != 0)) || die 'Run the script as a regular user.'
    command -v rpm >/dev/null && command -v dnf5 >/dev/null ||
        die 'Both rpm and dnf5 are required.'
    if [[ $mode == apply ]]; then
        [[ -t 0 && -t 1 ]] || die '--apply requires an interactive terminal.'
        command -v sudo >/dev/null || die 'sudo is required for --apply.'
    fi
    fedora_release=$(rpm -E '%fedora')
    [[ $fedora_release =~ ^[0-9]+$ ]] || die 'Could not determine the Fedora release.'

    umask 077
    local log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/fedora-post"
    mkdir -p -- "$log_dir" || die 'Could not create the log directory.'
    log_file=$(mktemp -- "$log_dir/run-$(date +%F-%H%M%S)-XXXXXXXX.log") ||
        die 'Could not create the run log.'
    trap 'summary' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if [[ $ui != classic ]]; then
        if [[ -t 0 && -t 1 && -n $TERM && $TERM != dumb ]] && command -v gum >/dev/null; then
            ui=modern
        else
            ui=classic
        fi
    fi
    say "Fedora-Post v$VERSION | Fedora $fedora_release | $mode | $ui UI"
    say "Log: $log_file"
    if [[ $mode == apply ]]; then
        confirm 'Enable changes for this session?' || return 0
    fi

    local choice result
    while :; do
        choose_action
        result=$?
        ((result == 130)) && exit 130
        ((result == 0)) || break
        case "$choice" in
        0) break ;;
        1) install_rpms 'Development and CLI tools' "${tools[@]}" ;;
        2) install_rpms 'Terminal and shell' "${terminal[@]}" ;;
        3) install_rpms 'Desktop apps' "${desktop[@]}" ;;
        4) install_rpms 'Graphics and media apps' "${media[@]}" ;;
        5) install_rpms 'Network and file sharing' "${network[@]}" ;;
        6) install_rpms 'Storage, backup and Flatpak' "${storage[@]}" ;;
        7) install_rpms 'All RPM categories' "${tools[@]}" "${terminal[@]}" \
            "${desktop[@]}" "${media[@]}" "${network[@]}" "${storage[@]}" ;;
        8) install_apps ;;
        9) flatpak_available && action 'Add the Flathub user remote' \
            flatpak remote-add --user --if-not-exists flathub "$flathub_url" ;;
        10) rpmfusion free ;;
        11) rpmfusion nonfree ;;
        12) dnf_plugin_action 'Trust and enable third-party COPR lihaohong/yazi' \
            --assumeyes copr enable lihaohong/yazi ;;
        13) dnf_plugin_action 'Enable Fedora Cisco OpenH264' \
            config-manager setopt fedora-cisco-openh264.enabled=1 ;;
        14) ffmpeg_action ;;
        15) action 'Upgrade the Multimedia group (RPM Fusion Free required)' \
            sudo dnf5 --setopt=assumeyes=False --setopt=install_weak_deps=False \
            --exclude=PackageKit-gstreamer-plugin group upgrade multimedia ;;
        16)
            say 'This optional VA-API driver is for supported Intel GPUs and requires RPM Fusion Nonfree.'
            install_rpms 'Intel media driver' intel-media-driver
            ;;
        17) action 'Upgrade Fedora RPM packages' sudo dnf5 --setopt=assumeyes=False upgrade --refresh ;;
        18) flatpak_available && action 'Update user Flatpaks' flatpak update --user ;;
        19) action 'Review removal of unneeded RPM dependencies' \
            sudo dnf5 --setopt=assumeyes=False autoremove ;;
        20) action 'Clean all DNF caches' sudo dnf5 clean all ;;
        21) flatpak_available && action 'Review removal of unused user Flatpak runtimes' \
            flatpak uninstall --user --unused ;;
        *) printf 'Invalid selection.\n' ;;
        esac
    done
    ((failed == 0))
}

main
