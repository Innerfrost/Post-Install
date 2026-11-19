#!/usr/bin/env bash

# ==========================================
# ARCH POST-INSTALL v2.0
# Arch Linux / CachyOS
# ==========================================

set -o pipefail

VERSION="2.0.1"
DRY_RUN=true
INTERFACE="classic"
LOG_FILE="$HOME/arch-post.log"

SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# ==========================================
# 1. ARGUMENTS
# ==========================================

usage() {
    echo "Arch Post-Install v$VERSION"
    echo
    echo "Usage: bash arch-post.sh [OPTION]"
    echo
    echo "Options:"
    echo "  --dry-run    Preview actions (default)"
    echo "  --apply      Enable real installation"
    echo "  --help       Show help"
    echo "  --version    Show version"
}

if (($# > 1)); then
    echo "Too many arguments." >&2
    exit 2
fi

case "${1:-}" in
"" | --dry-run)
    DRY_RUN=true
    ;;
--apply)
    DRY_RUN=false
    ;;
--help | -h)
    usage
    exit 0
    ;;
--version)
    echo "Arch-Post v$VERSION"
    exit 0
    ;;
*)
    echo "Unknown option: $1" >&2
    usage
    exit 2
    ;;
esac

# ==========================================
# 2. OUTPUT
# ==========================================

print_header() {
    echo
    echo "========================================="
    echo "$1"
    echo "========================================="
}

print_success() {
    echo "✅ $1"
}

print_error() {
    echo "❌ $1" >&2
}

print_info() {
    echo "ℹ️ $1"
}

print_skip() {
    echo "⏭️ $1"
}

# ==========================================
# 3. LOGGING
# ==========================================

run_logged() {
    local -a command=("$@")
    local -a statuses

    # Authenticate before entering the output pipeline.
    if [[ "${command[0]}" == "sudo" ]]; then
        if ! sudo -v; then
            print_error "Sudo authentication failed!"
            return 1
        fi

        command=(sudo -n "${command[@]:1}")
    fi

    echo
    printf 'Running: '
    printf '%q ' "${command[@]}"
    echo

    # Preserve stdin for interactive commands.
    "${command[@]}" 2>&1 | tee -a "$LOG_FILE"

    statuses=("${PIPESTATUS[@]}")

    if ((statuses[0] != 0)); then
        print_error "Command failed: exit ${statuses[0]}"
        print_info "Check log: $LOG_FILE"
        return "${statuses[0]}"
    fi

    if ((statuses[1] != 0)); then
        print_error "Failed to write installation log!"
        return 1
    fi

    return 0
}

# ==========================================
# INTERACTIVE AUR LOGGING
# ==========================================

run_aur_logged() {
    local status

    if ! command -v script >/dev/null 2>&1; then
        print_error "The 'script' command is required!"
        print_info "It is provided by util-linux."
        return 1
    fi

    if ! sudo -v; then
        print_error "Sudo authentication failed!"
        return 1
    fi

    echo
    print_info "Starting interactive AUR operation..."

    script -q -e -f -a "$LOG_FILE" -- "$@"

    status=$?

    printf '[AUR] Exit status: %s\n' \
        "$status" >>"$LOG_FILE"

    if ((status != 0)); then
        print_error "AUR operation failed: exit $status"
        return "$status"
    fi

    return 0
}

# ==========================================
# 4. SYSTEM CHECKS
# ==========================================

check_system() {
    print_header "Checking operating system"

    if [[ ! -r /etc/os-release ]]; then
        print_error "Cannot read /etc/os-release!"
        return 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    local os_name="${PRETTY_NAME:-Unknown}"

    # Exclude Omarchy explicitly.
    if [[ "${ID:-}" == "omarchy" ]] ||
        [[ "${VARIANT_ID:-}" == "omarchy" ]] ||
        [[ "${os_name,,}" == *omarchy* ]] ||
        [[ -e /etc/omarchy-release ]] ||
        command -v omarchy-update >/dev/null 2>&1; then
        print_error "Omarchy is not supported!"
        return 1
    fi

    case "${ID:-}" in
    arch | cachyos) ;;
    *)
        print_error "Unsupported distribution: $os_name"
        return 1
        ;;
    esac

    if ((EUID == 0)); then
        print_error "Do not run this script as root!"
        return 1
    fi

    if ! command -v pacman >/dev/null 2>&1; then
        print_error "Pacman is unavailable!"
        return 1
    fi

    print_success "System check completed!"
    echo "OS: $os_name"
    echo "Architecture: $(uname -m)"

    return 0
}

check_dependencies() {
    local cmd
    local -a commands=(tee mktemp)

    if [[ "$DRY_RUN" == false ]]; then
        commands+=(sudo)
    fi

    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            print_error "Missing dependency: $cmd"
            return 1
        fi
    done

    if [[ "$DRY_RUN" == false ]]; then
        if ! touch "$LOG_FILE"; then
            print_error "Cannot write log: $LOG_FILE"
            return 1
        fi

        printf '\n--- Session: %s ---\n' \
            "$(date)" >>"$LOG_FILE"
    fi

    return 0
}

# ==========================================
# 5. SAFETY
# ==========================================

confirm_word() {
    local message="$1"
    local expected="$2"
    local answer

    echo
    echo "⚠️ $message"

    if ! read -r -p \
        "Type $expected to continue: " answer; then
        return 1
    fi

    if [[ "$answer" != "$expected" ]]; then
        print_skip "Operation cancelled."
        return 1
    fi

    return 0
}

confirm_apply() {
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi

    if [[ "$INTERFACE" == "modern" ]]; then
        if ! gum confirm \
            --affirmative "Continue" \
            --negative "Cancel" \
            "This operation will modify your system."; then
            return 1
        fi
    fi

    confirm_word \
        "LIVE INSTALLATION MODE!" \
        "YES"
}

# ==========================================
# 6. PACKAGE CATEGORIES
# ==========================================

ESSENTIALS=(
    base-devel
    git
    wget
    curl
    python
    python-pip
    zip
    unzip
    tree
)

TERMINAL=(
    btop
    kitty
    fish
    tmux
    yazi
    fzf
    vim
    bat
    neovim
    eza
    cmatrix
)

DEVELOPMENT=(
    nodejs
    npm
)

COMMUNICATION=(
    telegram-desktop
    discord
    qbittorrent
    bitwarden
)

MULTIMEDIA=(
    gimp
    krita
    vlc
    obs-studio
    flameshot
    kdenlive
    okular
    blender
)

NETWORKING=(
    gvfs-smb
    gvfs-nfs
    smbclient
    nfs-utils
    avahi
    nss-mdns
    rpcbind
    rsync
)

EXTRAS=(
    flatpak
    btrfs-assistant
)

AUR_PACKAGES=(
    google-chrome
    visual-studio-code-bin
    tabby-bin
    yandex-browser
    happ-desktop-bin
)

FLATPAK_PACKAGES=(
    org.onlyoffice.desktopeditors
    md.obsidian.Obsidian
)

# ==========================================
# 7. PACMAN
# ==========================================

show_packages() {
    printf '  - %s\n' "$@"
}

install_pacman() {
    local title="$1"
    shift

    local pkg
    local -a missing=()

    print_header "$title"

    for pkg in "$@"; do
        if pacman -Qq -- "$pkg" >/dev/null 2>&1; then
            print_skip "Already installed: $pkg"
        else
            missing+=("$pkg")
        fi
    done

    if ((${#missing[@]} == 0)); then
        print_info "All packages are already installed."
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "🧪 DRY RUN"
        echo "Would perform a full system upgrade"
        echo "and install the following packages:"
        show_packages "${missing[@]}"
        return 0
    fi

    echo
    print_info "Pacman will perform a full system upgrade."
    print_info "Review package changes before confirming."

    if run_logged sudo pacman -Syu \
        --needed "${missing[@]}"; then
        print_success "Package installation completed!"
        return 0
    fi

    print_error "Package installation failed!"
    return 1
}

install_category() {
    case "$1" in
    essentials)
        install_pacman \
            "System Essentials" "${ESSENTIALS[@]}"
        ;;
    terminal)
        install_pacman \
            "Terminal & CLI" "${TERMINAL[@]}"
        ;;
    development)
        install_pacman \
            "Development" "${DEVELOPMENT[@]}"
        ;;
    communication)
        install_pacman \
            "Internet & Communication" \
            "${COMMUNICATION[@]}"
        ;;
    multimedia)
        install_pacman \
            "Multimedia & Graphics" \
            "${MULTIMEDIA[@]}"
        ;;
    networking)
        install_pacman \
            "Networking & Storage" \
            "${NETWORKING[@]}"
        ;;
    extras)
        install_pacman \
            "System Extras" "${EXTRAS[@]}"
        ;;
    *)
        print_error "Unknown category!"
        return 1
        ;;
    esac
}

# ==========================================
# 8. AUR HELPERS
# ==========================================

install_aur_helper() {
    local helper="$1"
    local temp_dir
    local result=0

    if ! confirm_word \
        "Review AUR build scripts before execution." \
        "REVIEW"; then
        return 2
    fi

    install_pacman \
        "AUR build dependencies" \
        git base-devel || return 1

    temp_dir=$(mktemp -d -t arch-post-aur.XXXXXXXX) ||
        return 1

    if ! run_logged git clone \
        "https://aur.archlinux.org/${helper}.git" \
        "$temp_dir/$helper"; then
        result=1
    else
        print_header "Reviewing $helper PKGBUILD"

        if ! sed -n '1,$p' \
            "$temp_dir/$helper/PKGBUILD"; then
            result=1

        elif ! confirm_word \
            "Review and trust this PKGBUILD before building." \
            "BUILD"; then
            result=2

        elif ! (
            cd "$temp_dir/$helper" || exit 1
            run_aur_logged makepkg -si
        ); then
            result=1
        fi
    fi

    # Remove only the temporary directory created above.
    rm -rf -- "$temp_dir"

    if ((result != 0)); then
        return "$result"
    fi

    if ! command -v "$helper" >/dev/null 2>&1; then
        print_error "AUR helper installation failed!"
        return 1
    fi

    print_success "$helper installed successfully!"
}

choose_aur_helper() {
    local answer
    local has_yay=false
    local has_paru=false

    command -v yay >/dev/null 2>&1 && has_yay=true
    command -v paru >/dev/null 2>&1 && has_paru=true

    if [[ "$DRY_RUN" == true ]]; then
        print_info "DRY RUN: would use yay/paru."
        if [[ "$has_yay" == false &&
            "$has_paru" == false ]]; then
            print_info "Would offer to install an AUR helper."
        fi
        HELPER="yay"
        return 0
    fi

    if [[ "$has_yay" == true &&
        "$has_paru" == false ]]; then
        HELPER="yay"
        return 0
    fi

    if [[ "$has_paru" == true &&
        "$has_yay" == false ]]; then
        HELPER="paru"
        return 0
    fi

    echo
    echo "Choose your AUR helper:"
    echo "1) yay"
    echo "2) paru"
    echo "0) Cancel"

    if ! read -r -p "Selection [0-2]: " answer; then
        return 2
    fi

    case "$answer" in
    1) HELPER="yay" ;;
    2) HELPER="paru" ;;
    *) return 2 ;;
    esac

    if ! command -v "$HELPER" >/dev/null 2>&1; then
        install_aur_helper "$HELPER" || return $?
    fi
}

# ==========================================
# AUR PACKAGE SELECTION
# ==========================================

select_aur_packages() {
    local -a available=("$@")
    local -a numbers=()
    local answer selection number index pkg
    local duplicate

    SELECTED_AUR=()

    if ((${#available[@]} == 0)); then
        return 2
    fi

    # Modern UI: multiple selection
    if [[ "$INTERFACE" == "modern" ]]; then

        selection=$(gum choose \
            --no-limit \
            --header "Select AUR applications (Space/Tab + Enter)" \
            "${available[@]}") || return 2

        if [[ -z "$selection" ]]; then
            print_skip "No applications selected."
            return 2
        fi

        mapfile -t SELECTED_AUR <<<"$selection"

    # Classic UI: comma-separated package numbers
    else

        print_header "Select AUR Applications"

        for index in "${!available[@]}"; do
            printf '%d) %s\n' \
                "$((index + 1))" \
                "${available[$index]}"
        done

        echo
        echo "Enter numbers separated by commas."
        echo "Example: 1,3,5"
        echo "A) Select all"
        echo "0) Cancel"
        echo

        if ! read -r -p "Your selection: " answer; then
            return 2
        fi

        case "$answer" in
        a | A)
            SELECTED_AUR=("${available[@]}")
            ;;
        0 | "")
            print_skip "Selection cancelled."
            return 2
            ;;
        *)
            IFS=',' read -r -a numbers <<<"$answer"

            for number in "${numbers[@]}"; do

                # Remove whitespace.
                number="${number//[[:space:]]/}"

                if [[ ! "$number" =~ ^[0-9]+$ ]]; then
                    print_error "Invalid number: $number"
                    return 2
                fi

                index=$((10#$number))

                if ((index < 1 || \
                    index > ${#available[@]})); then
                    print_error "Out of range: $number"
                    return 2
                fi

                pkg="${available[$((index - 1))]}"

                # Prevent duplicate selections.
                duplicate=false

                local existing
                for existing in "${SELECTED_AUR[@]}"; do
                    if [[ "$existing" == "$pkg" ]]; then
                        duplicate=true
                        break
                    fi
                done

                if [[ "$duplicate" == false ]]; then
                    SELECTED_AUR+=("$pkg")
                fi
            done
            ;;
        esac
    fi

    if ((${#SELECTED_AUR[@]} == 0)); then
        print_skip "No applications selected."
        return 2
    fi

    echo
    print_info "Selected AUR applications:"
    show_packages "${SELECTED_AUR[@]}"

    return 0
}

# ==========================================
# AUR INSTALLATION
# ==========================================

install_aur_packages() {
    local pkg
    local failed=0
    local -a missing=()

    print_header "Installing AUR Applications"

    # Check installed packages.
    for pkg in "${AUR_PACKAGES[@]}"; do

        if pacman -Qq -- "$pkg" >/dev/null 2>&1; then
            print_skip "Already installed: $pkg"
        else
            missing+=("$pkg")
        fi
    done

    if ((${#missing[@]} == 0)); then
        print_info "All AUR applications are installed."
        return 0
    fi

    # Select packages before installation.
    select_aur_packages "${missing[@]}" || return 2

    # Strict dry-run.
    if [[ "$DRY_RUN" == true ]]; then

        choose_aur_helper

        echo
        echo "🧪 DRY RUN: Would install:"
        show_packages "${SELECTED_AUR[@]}"

        return 0
    fi

    # Choose an existing helper or offer installation.
    choose_aur_helper || return $?

    echo
    print_info "AUR packages are community-maintained."
    print_info "Review PKGBUILDs before installation."

    # Install only selected packages.
    for pkg in "${SELECTED_AUR[@]}"; do

        print_header "AUR: $pkg"

        if run_aur_logged \
            "$HELPER" -S --needed "$pkg"; then

            print_success "Installed: $pkg"

        else
            print_error "Failed: $pkg"
            ((failed += 1))
        fi
    done

    if ((failed > 0)); then
        print_error "$failed AUR installation(s) failed."
        return 1
    fi

    print_success "Selected AUR applications installed!"
    return 0
}

# ==========================================
# 9. FLATPAK
# ==========================================

choose_flatpak_scope() {
    local answer

    echo
    echo "Choose Flatpak installation scope:"
    echo "1) User installation (recommended)"
    echo "2) System installation"
    echo "0) Cancel"

    if ! read -r -p "Selection [0-2]: " answer; then
        return 2
    fi

    case "$answer" in
    1) FLATPAK_SCOPE="--user" ;;
    2) FLATPAK_SCOPE="--system" ;;
    *) return 2 ;;
    esac
}

install_flatpak_packages() {
    local app
    local -a missing=()

    print_header "Installing Flatpak Applications"

    for app in "${FLATPAK_PACKAGES[@]}"; do
        if command -v flatpak >/dev/null 2>&1 &&
            flatpak info "$app" >/dev/null 2>&1; then
            print_skip "Already installed: $app"
        else
            missing+=("$app")
        fi
    done

    if ((${#missing[@]} == 0)); then
        print_info "All Flatpak apps are installed."
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "🧪 DRY RUN"
        echo "Would configure Flatpak/Flathub"
        echo "and install:"
        show_packages "${missing[@]}"
        return 0
    fi

    choose_flatpak_scope || return $?

    if ! command -v flatpak >/dev/null 2>&1; then
        install_pacman \
            "Installing Flatpak" flatpak || return 1
    fi

    local flathub_url
    flathub_url="https://dl.flathub.org/repo/flathub.flatpakrepo"

    if [[ "$FLATPAK_SCOPE" == "--user" ]]; then

        run_logged flatpak remote-add \
            --user --if-not-exists \
            flathub "$flathub_url" || return 1

        run_logged flatpak install \
            --user -y flathub "${missing[@]}"

    else

        run_logged sudo flatpak remote-add \
            --system --if-not-exists \
            flathub "$flathub_url" || return 1

        run_logged sudo flatpak install \
            --system -y flathub "${missing[@]}"
    fi
}

# ==========================================
# 10. SYSTEM UPDATE
# ==========================================

update_system() {
    print_header "Updating System"

    if [[ "$DRY_RUN" == true ]]; then
        echo "🧪 DRY RUN:"
        echo "Would execute: sudo pacman -Syu"
        return 0
    fi

    if ! confirm_word \
        "A full system upgrade will be performed." \
        "UPDATE"; then
        return 2
    fi

    if run_logged sudo pacman -Syu; then
        print_success "System updated successfully!"
        return 0
    fi

    print_error "System update failed!"
    return 1
}

# ==========================================
# 11. SYSTEM CLEANUP
# ==========================================

cleanup_system() {
    local -a orphans=()

    print_header "System Cleanup"

    mapfile -t orphans < <(
        pacman -Qdtq 2>/dev/null || true
    )

    if ((${#orphans[@]} > 0)); then
        echo "Orphaned packages:"
        show_packages "${orphans[@]}"
    else
        print_info "No orphaned packages found."
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo
        echo "🧪 DRY RUN:"
        echo "Would offer to remove orphaned packages."
        echo "Would offer to prune old package cache."
        return 0
    fi

    if ((${#orphans[@]} > 0)); then

        if confirm_word \
            "Remove the orphaned packages listed above?" \
            "REMOVE"; then

            run_logged sudo pacman -Rns \
                -- "${orphans[@]}" || return 1
        else
            print_skip "Orphan removal skipped."
        fi
    fi

    if command -v paccache >/dev/null 2>&1; then

        if confirm_word \
            "Keep the latest three cached package versions?" \
            "CACHE"; then

            run_logged sudo paccache -rk 3 ||
                return 1
        else
            print_skip "Cache cleanup skipped."
        fi

    else
        print_info \
            "paccache is unavailable (pacman-contrib)."
    fi

    print_success "Cleanup operation completed!"
}

# ==========================================
# 12. INSTALL EVERYTHING
# ==========================================

install_everything() {
    print_header "Installing Everything"

    local pacman_status="NOT STARTED"
    local aur_status="NOT STARTED"
    local flatpak_status="NOT STARTED"
    local result=0
    local code

    local -a all_packages=(
        "${ESSENTIALS[@]}"
        "${TERMINAL[@]}"
        "${DEVELOPMENT[@]}"
        "${COMMUNICATION[@]}"
        "${MULTIMEDIA[@]}"
        "${NETWORKING[@]}"
        "${EXTRAS[@]}"
    )

    # Stage 1: Pacman
    if install_pacman \
        "All Official Packages" \
        "${all_packages[@]}"; then

        pacman_status="COMPLETED"
    else
        pacman_status="FAILED"
        print_error "Pacman installation failed!"
        return 1
    fi

    # Stage 2: AUR
    if install_aur_packages; then
        aur_status="COMPLETED"
    else
        code=$?

        if ((code == 2)); then
            aur_status="SKIPPED"
        else
            aur_status="FAILED"
            result=1
        fi
    fi

    # Stage 3: Flatpak
    # Continue even if AUR failed.
    if install_flatpak_packages; then
        flatpak_status="COMPLETED"
    else
        code=$?

        if ((code == 2)); then
            flatpak_status="SKIPPED"
        else
            flatpak_status="FAILED"
            result=1
        fi
    fi

    # Final report
    print_header "FULL INSTALLATION SUMMARY"

    echo "Pacman:  $pacman_status"
    echo "AUR:     $aur_status"
    echo "Flatpak: $flatpak_status"
    echo

    if ((result == 0)); then
        print_success "Installation stages finished."
        return 0
    fi

    print_error "Installation partially completed!"
    print_info "Check the log for failed operations."

    return 1
}

# ==========================================
# 13. GUM / INTERFACE
# ==========================================

ensure_gum() {
    if command -v gum >/dev/null 2>&1; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_info "Gum is not installed."
        print_info "Use --apply to install it."
        return 1
    fi

    if ! confirm_word \
        "Install Gum from Arch repositories?" \
        "GUM"; then
        return 1
    fi

    install_pacman \
        "Installing Gum" gum || return 1

    command -v gum >/dev/null 2>&1
}

select_interface() {
    local answer

    print_header "ARCH POST-INSTALL v$VERSION"

    echo "Choose your interface:"
    echo
    echo "1) ✨ Modern UI"
    echo "2) 🖥️ Classic UI"
    echo "0) Exit"
    echo

    while true; do

        if ! read -r -p \
            "Select an option [0-2]: " answer; then
            return 1
        fi

        case "$answer" in
        1)
            if ensure_gum; then
                INTERFACE="modern"
                return 0
            fi
            ;;
        2)
            INTERFACE="classic"
            return 0
            ;;
        0)
            exit 0
            ;;
        *)
            print_error "Invalid option!"
            ;;
        esac
    done
}

# ==========================================
# 14. MENUS
# ==========================================

show_classic_menu() {
    local mode

    if [[ "$DRY_RUN" == true ]]; then
        mode="DRY RUN"
    else
        mode="LIVE INSTALLATION"
    fi

    print_header "ARCH POST-INSTALL | $mode"

    echo " 1) System Essentials"
    echo " 2) Terminal & CLI"
    echo " 3) Development"
    echo " 4) Internet & Communication"
    echo " 5) Multimedia & Graphics"
    echo " 6) Networking & Storage"
    echo " 7) System Extras"
    echo
    echo " 8) AUR Applications"
    echo " 9) Flatpak Applications"
    echo
    echo "10) Update System"
    echo "11) Cleanup System"
    echo
    echo "12) Install Everything"
    echo "13) Switch Interface"
    echo " 0) Exit"
    echo
}

show_modern_menu() {
    local selection
    local mode

    if [[ "$DRY_RUN" == true ]]; then
        mode="DRY RUN"
    else
        mode="LIVE INSTALLATION"
    fi

    selection=$(gum choose \
        --header "ARCH POST-INSTALL | $mode" \
        "1) 📦 System Essentials" \
        "2) 🖥️ Terminal & CLI" \
        "3) 💻 Development" \
        "4) 🌐 Internet & Communication" \
        "5) 🎬 Multimedia & Graphics" \
        "6) 📡 Networking & Storage" \
        "7) 🛠️ System Extras" \
        "8) 📦 AUR Applications" \
        "9) 📥 Flatpak Applications" \
        "10) 🔄 Update System" \
        "11) 🧹 Cleanup System" \
        "12) 🚀 Install Everything" \
        "13) 🔀 Switch Interface" \
        "0) 🚪 Exit") || return 1

    CHOICE="${selection%%)*}"
}

run_choice() {
    case "$1" in
    1) install_category essentials ;;
    2) install_category terminal ;;
    3) install_category development ;;
    4) install_category communication ;;
    5) install_category multimedia ;;
    6) install_category networking ;;
    7) install_category extras ;;
    8) install_aur_packages ;;
    9) install_flatpak_packages ;;
    10) update_system ;;
    11) cleanup_system ;;
    12) install_everything ;;
    *)
        print_error "Unknown action!"
        return 1
        ;;
    esac
}

# ==========================================
# 15. MAIN
# ==========================================

main() {
    local choice
    local result

    check_system || return 1
    check_dependencies || return 1
    select_interface || return 0

    while true; do

        echo

        if [[ "$INTERFACE" == "modern" ]]; then

            if ! command -v gum >/dev/null 2>&1; then
                print_info "Gum unavailable."
                print_info "Switching to Classic UI."
                INTERFACE="classic"
                continue
            fi

            show_modern_menu || break
            choice="$CHOICE"

        else

            show_classic_menu

            if ! read -r -p \
                "Select an option [0-13]: " choice; then
                break
            fi
        fi

        case "$choice" in
        0)
            break
            ;;
        13)
            select_interface || break
            continue
            ;;
        1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12) ;;
        *)
            print_error "Invalid option!"
            continue
            ;;
        esac

        if ! confirm_apply; then
            ((SKIPPED_COUNT += 1))
            print_skip "Operation cancelled."
            continue
        fi

        if run_choice "$choice"; then
            ((SUCCESS_COUNT += 1))

            if [[ "$DRY_RUN" == true ]]; then
                print_success "Preview completed!"
            else
                print_success "Action completed!"
            fi

        else
            result=$?

            if ((result == 2)); then
                ((SKIPPED_COUNT += 1))
                print_skip "Operation skipped."
            else
                ((FAILED_COUNT += 1))
                print_error "Action failed!"
            fi
        fi

        if [[ "$INTERFACE" == "classic" ]]; then
            read -r -p \
                "Press Enter to return to menu..." _ ||
                break
        fi

    done

    echo
    print_header "SESSION SUMMARY"

    echo "Completed: $SUCCESS_COUNT"
    echo "Failed:    $FAILED_COUNT"
    echo "Skipped:   $SKIPPED_COUNT"

    if [[ "$DRY_RUN" == false ]]; then
        echo "Log: $LOG_FILE"
    fi

    ((FAILED_COUNT == 0))
}

main
