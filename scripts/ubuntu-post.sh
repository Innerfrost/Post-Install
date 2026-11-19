#!/bin/bash

# Detect errors in command pipelines
set -o pipefail

# Configuration
DRY_RUN=true

case "${1:-}" in
"")
    # Default: safe test mode
    ;;
--dry-run)
    DRY_RUN=true
    ;;
--apply)
    DRY_RUN=false
    ;;
--help | -h)
    echo "Ubuntu Post-Install"
    echo ""
    echo "Usage: bash ubuntu-post.sh [OPTION]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Preview actions (default)"
    echo "  --apply      Allow real installation"
    echo "  --help       Show this help"
    exit 0
    ;;
*)
    echo "❌ Unknown option: $1" >&2
    exit 2
    ;;
esac

# Logs.
LOG_FILE="$HOME/ubuntu-post.log"
# exec > >(tee -a "$LOG_FILE") 2>&1

# Install Gum if missing
ensure_gum() {
    if command -v gum >/dev/null 2>&1; then
        return 0
    fi

    print_error "Gum is not installed!"

    if [[ "$DRY_RUN" == true ]]; then
        echo "🧪 DRY RUN: Cannot install Gum."
        echo "Use --apply to allow installation."
        return 1
    fi

    if ! read -r -p "Install Gum now? (y/N): " answer; then
        return 1
    fi

    case "$answer" in
    y | Y)
        print_header "Installing Gum"

        if ! run_logged sudo apt-get update; then
            print_error "Failed to update APT!"
            return 1
        fi

        if ! run_logged sudo apt-get install -y gum; then
            print_error "Failed to install Gum!"
            return 1
        fi

        if command -v gum >/dev/null 2>&1; then
            print_success "Gum installed successfully!"
            return 0
        fi

        print_error "Gum verification failed!"
        return 1
        ;;
    *)
        echo "Installation cancelled."
        return 1
        ;;
    esac
}

# Interface selection
select_interface() {
    echo ""
    print_header "UBUNTU POST-INSTALL"
    echo ""
    echo "Choose your interface:"
    echo ""
    echo "1) ✨ Modern UI"
    echo "2) 🖥️ Classic UI"
    echo "0) Exit"
    echo ""

    while true; do
        if ! read -r -p "Select an option [0-2]: " interface_choice; then
            echo ""
            return 1
        fi

        case "$interface_choice" in
        1)
            if ensure_gum; then
                INTERFACE="modern"
                return 0
            else
                echo "Returning to interface selection..."
            fi
            ;;
        2)
            INTERFACE="classic"
            return 0
            ;;
        0)
            echo "👋 Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid option! Choose 0-2."
            ;;
        esac
    done
}

# Main menu.
show_menu() {
    echo "========================================="
    echo "          UBUNTU POST-INSTALL"
    if [[ "$DRY_RUN" == true ]]; then
        echo "          🧪 MODE: DRY RUN"
    else
        echo "          ⚠️ MODE: LIVE INSTALLATION"
    fi
    echo "========================================="
    echo ""
    echo "1) Install base packages"
    echo "2) Install Docker & Docker Compose"
    echo "3) Configure Fish Shell"
    echo "4) Update system"
    echo "5) Cleanup system"
    echo ""
    echo "6) Install everything"
    echo "7) Switch interface"
    echo "0) Exit"
    echo ""
}

print_header() {
    echo "========================================="
    echo "$1"
    echo "========================================="
}

print_success() {
    echo "========================================="
    echo "✅ $1"
    echo "========================================="
}

print_error() {
    echo "❌ $1" >&2
}

# Run command and save output to log
run_logged() {
    local -a statuses

    # Authenticate before redirecting stdin
    if [[ "${1:-}" == "sudo" ]]; then
        if ! sudo -v; then
            print_error "Sudo authentication failed!"
            return 1
        fi

        # Detach stdin to avoid sudo-rs TTY/pipeline issue
        "$@" </dev/null 2>&1 | tee -a "$LOG_FILE"
        statuses=("${PIPESTATUS[@]}")
    else
        "$@" 2>&1 | tee -a "$LOG_FILE"
        statuses=("${PIPESTATUS[@]}")
    fi

    if [[ "${statuses[0]}" -ne 0 ]]; then
        print_error "Command failed with exit code ${statuses[0]}!"
        return "${statuses[0]}"
    fi

    if [[ "${statuses[1]}" -ne 0 ]]; then
        print_error "Failed to write installation log!"
        return 1
    fi

    return 0
}

# Show spinner for background operations
show_spinner() {
    local title="$1"
    shift

    if [[ "$INTERFACE" == "modern" ]]; then
        gum spin \
            --spinner dot \
            --title "$title" \
            -- "$@"
    else
        "$@"
    fi
}

# Check operating system
check_system() {
    print_header "Checking operating system"

    if [[ ! -r /etc/os-release ]]; then
        print_error "Cannot read operating system information!"
        return 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    if [[ "$ID" != "ubuntu" ]]; then
        print_error "This installer supports Ubuntu only!"
        return 1
    fi

    print_success "System check completed!"
    echo "OS: $PRETTY_NAME"
    echo "Architecture: $(uname -m)"
    echo ""

    return 0
}

# Check required dependencies
check_dependencies() {
    print_header "Checking dependencies"

    local missing=()
    local commands=(apt-get tee mktemp)

    # Real installation requires additional tools
    if [[ "$DRY_RUN" == false ]]; then
        commands+=(sudo)
    fi

    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if ((${#missing[@]} > 0)); then
        print_error "Missing required commands:"
        printf '  - %s\n' "${missing[@]}"
        return 1
    fi

    print_success "Required dependencies are available!"
    return 0
}

# Confirm real installation
confirm_apply() {
    echo ""

    if [[ "$INTERFACE" == "modern" ]]; then

        if ! gum confirm \
            --affirmative "Continue" \
            --negative "Cancel" \
            "⚠️ This operation will modify your system. Continue?"; then

            print_error "Operation cancelled!"
            return 1
        fi

    else

        echo "⚠️ WARNING: LIVE INSTALLATION MODE!"
        echo "This operation will modify your system."
        echo ""

    fi

    # Final confirmation for both interfaces
    if ! read -r -p "Type YES to confirm: " answer; then
        print_error "Unable to read confirmation!"
        return 1
    fi

    if [[ "$answer" == "YES" ]]; then
        return 0
    else
        print_error "Operation cancelled!"
        return 1
    fi
}

# Installing minimum packages.
Main=(
    curl
    htop
    wget
    git
    fish
    tree
    jq
    python3
    python3-pip
    iputils-ping
    dnsutils
    net-tools
    ca-certificates
    fastfetch
)

# Update system
update_system() {
    print_header "Updating system"

    # Strict dry-run
    if [[ "$DRY_RUN" == true ]]; then
        echo "🧪 DRY RUN: Would update APT package lists."
        echo "🧪 DRY RUN: Would preview available upgrades."
        echo "🧪 DRY RUN: Would upgrade installed packages."
        return 0
    fi

    # Update package lists
    if ! run_logged sudo apt-get update; then
        print_error "Failed to update package lists!"
        return 1
    fi

    # Preview available upgrades
    print_header "Previewing system upgrades"

    if ! run_logged sudo apt-get -s upgrade; then
        print_error "Failed to preview upgrades!"
        return 1
    fi

    echo ""
    echo "⚠️ Review the packages listed above."
    echo ""

    # Confirm system upgrade
    if ! read -r -p "Type UPDATE to continue (or press Enter to cancel): " answer; then
        print_error "Unable to read confirmation!"
        return 1
    fi

    if [[ "$answer" != "UPDATE" ]]; then
        echo "System update cancelled."
        return 2
    fi

    # Upgrade installed packages
    if ! run_logged sudo apt-get upgrade -y; then
        print_error "System upgrade failed!"
        return 1
    fi

    print_success "System updated successfully!"
    return 0
}

# Install base packages
install_packages() {
    print_header "Installing main packages."

    if [[ "$DRY_RUN" == true ]]; then
        echo "🧪 DRY RUN: Would update APT and install:"
        printf '  - %s\n' "${Main[@]}"
        return 0
    fi

    if ! run_logged sudo apt-get update; then
        print_error "Failed to update package lists!"
        return 1
    fi

    if run_logged sudo apt-get install -y "${Main[@]}"; then
        print_success "Packages installed successfully!"
        return 0
    else
        print_error "Failed to install packages!"
        return 1
    fi
}

# Install Docker
install_docker() {
    print_header "Installing Docker & Docker Compose"

    if [[ "$DRY_RUN" == true ]]; then
        echo "🧪 DRY RUN: Would check Docker installation."
        echo "🧪 DRY RUN: Would install Docker if missing."
        echo "🧪 DRY RUN: Would check Docker group permissions."
        return 0
    fi

    # Check if Docker is already installed
    if command -v docker >/dev/null 2>&1; then
        print_success "Docker is already installed!"
    else
        print_header "Installing Docker"

        # Check Docker installer dependency
        if ! command -v curl >/dev/null 2>&1; then
            print_error "Curl is required to install Docker!"
            echo "Please install base packages first."
            return 1
        fi

        # Create temporary installer file
        local docker_installer
        docker_installer=$(mktemp) || {
            print_error "Failed to create temporary file!"
            return 1
        }

        # Download Docker installer
        if ! curl -fsSL https://get.docker.com -o "$docker_installer"; then
            print_error "Failed to download Docker installer!"
            rm -f -- "$docker_installer"
            return 1
        fi

        # Install Docker
        echo ""
        echo "🐳 Starting Docker installation..."
        echo "ℹ️ This process may take several minutes."
        echo "ℹ️ Package installation may produce little output."
        echo "ℹ️ Installation log: $LOG_FILE"
        echo ""

        local start_time=$SECONDS

        if ! run_logged sudo sh "$docker_installer"; then
            print_error "Docker installation failed!"
            echo "Check the installation log: $LOG_FILE"
            rm -f -- "$docker_installer"
            return 1
        fi

        echo ""
        echo "✅ Docker installer finished in $((SECONDS - start_time)) seconds."

        # Remove temporary installer
        rm -f -- "$docker_installer"

        # Verify Docker installation
        if ! command -v docker >/dev/null 2>&1; then
            print_error "Docker installation verification failed!"
            return 1
        fi

        print_success "Docker installed successfully!"
    fi

    # Verify Docker daemon
    print_header "Checking Docker Engine"

    if ! sudo docker info >/dev/null 2>&1; then
        print_error "Docker Engine is not running or unavailable!"

        # Check whether the Docker service exists
        if ! systemctl cat docker.service >/dev/null 2>&1; then
            print_error "Docker service was not found!"
            return 1
        fi

        echo ""
        echo "Docker is installed, but the Engine is unavailable."

        if ! read -r -p "Try to start Docker Engine? (y/N): " answer; then
            print_error "Unable to read answer!"
            return 1
        fi

        case "$answer" in
        y | Y)
            local -a docker_units=(docker.service)

            if systemctl cat docker.socket >/dev/null 2>&1; then
                docker_units=(docker.socket docker.service)
            fi

            if ! run_logged sudo systemctl start "${docker_units[@]}"; then
                print_error "Failed to start Docker Engine!"
                return 1
            fi
            ;;
        *)
            echo "Docker Engine startup cancelled."
            return 1
            ;;
        esac

        # Verify Docker again after starting the service
        if ! sudo docker info >/dev/null 2>&1; then
            print_error "Docker Engine is still unavailable!"
            echo "Check the service logs:"
            echo "  sudo journalctl -u docker.service -n 50"
            return 1
        fi
    fi

    print_success "Docker Engine is working!"

    # Verify Docker Compose
    print_header "Checking Docker Compose"

    if ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose is missing or unavailable!"
        echo "Install the Docker Compose plugin:"
        echo "  sudo apt-get install docker-compose-plugin"
        return 1
    fi

    print_success "Docker Compose is available!"

    # Create Docker group if needed
    if ! getent group docker >/dev/null; then
        if ! run_logged sudo groupadd docker; then
            print_error "Failed to create Docker group!"
            return 1
        fi
    fi

    # Check current user group membership
    if id -nG "$USER" | grep -Eq '(^| )docker( |$)'; then
        print_success "User is already in the Docker group!"
        return 0
    fi

    # Configure Docker group permissions
    echo ""
    echo "⚠️ Docker group membership grants root-level privileges."
    echo ""

    if ! read -r -p "Add current user to Docker group? (y/N): " answer; then
        print_error "Unable to read answer!"
        return 1
    fi

    case "$answer" in
    y | Y)
        if run_logged sudo usermod -aG docker "$USER"; then
            print_success "User added to Docker group!"
            echo "ℹ️ Log out and back in to activate group membership."
        else
            print_error "Failed to configure Docker permissions!"
            return 1
        fi
        ;;
    *)
        echo "Skipping Docker group configuration."
        ;;
    esac

    print_success "Docker configuration completed!"
    return 0
}

# Configure Fish shell
configure_fish() {
    print_header "Configuring Fish Shell"

    # Strict dry-run
    if [[ "$DRY_RUN" == true ]]; then
        echo "🧪 DRY RUN: Would check the current shell."
        echo "🧪 DRY RUN: Would configure Fish if needed."
        return 0
    fi

    # Check if Fish is installed
    if ! command -v fish >/dev/null 2>&1; then
        print_error "Fish is not installed!"
        echo "Please install base packages first."
        return 1
    fi

    # Get Fish path
    local fish_path
    fish_path=$(command -v fish)

    # Get user's configured login shell
    local current_shell
    current_shell=$(getent passwd "$USER" | cut -d: -f7)

    if [[ -z "$current_shell" ]]; then
        print_error "Unable to determine current login shell!"
        return 1
    fi

    # Skip configuration if Fish is already the default
    if [[ "$current_shell" == "$fish_path" ]]; then
        print_success "Fish is already the default shell!"
        return 0
    fi

    # Configure Fish
    if chsh -s "$fish_path"; then
        print_success "Fish configured successfully!"
        echo "ℹ️ Log out and back in to activate Fish."
        return 0
    else
        print_error "Failed to configure Fish!"
        return 1
    fi
}

# Cleanup system
cleanup_system() {
    print_header "Cleaning system"

    # Strict dry-run
    if [[ "$DRY_RUN" == true ]]; then
        echo "🧪 DRY RUN: Would preview unused packages."
        echo "🧪 DRY RUN: Would remove unused packages."
        echo "🧪 DRY RUN: Would clean APT cache."
        return 0
    fi

    # Preview packages before removal
    print_header "Previewing packages to remove"

    if ! run_logged sudo apt-get -s autoremove; then
        print_error "Failed to preview package removal!"
        return 1
    fi

    echo ""
    echo "⚠️ Review the packages listed above carefully."
    echo ""

    # Ask for explicit confirmation
    if ! read -r -p "Type REMOVE to continue (or press Enter to cancel): " answer; then
        print_error "Unable to read confirmation!"
        return 1
    fi

    if [[ "$answer" != "REMOVE" ]]; then
        echo "⏭️ Cleanup skipped by user."
        return 2
    fi

    # Remove unused packages
    if ! run_logged sudo apt-get autoremove -y; then
        print_error "Failed to remove unused packages!"
        return 1
    fi

    # Clean APT cache
    if ! run_logged sudo apt-get clean; then
        print_error "Failed to clean APT cache!"
        return 1
    fi

    print_success "Cleanup completed successfully!"
    return 0
}

# Install everything
install_all() {
    print_header "Starting full installation"

    # Update system first
    update_system
    local result=$?

    if [[ "$result" -eq 2 ]]; then
        echo "⏭️ Full installation cancelled by user."
        return 2
    elif [[ "$result" -ne 0 ]]; then
        print_error "System update failed!"
        return 1
    fi

    # Install components
    install_packages || return 1
    install_docker || return 1
    configure_fish || return 1

    # Handle cleanup separately
    cleanup_system
    result=$?

    if [[ "$result" -eq 2 ]]; then
        echo "⏭️ Cleanup skipped by user."
        return 2
    elif [[ "$result" -ne 0 ]]; then
        print_error "Cleanup failed!"
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        print_success "Simulation completed successfully!"
    else
        print_success "Full installation completed!"
    fi

    return 0
}

# Verify operating system
check_system || exit 1

check_dependencies || exit 1

# Select interface before starting the main menu
select_interface || exit 1

# Main loop
while true; do
    echo ""

    if [[ "$INTERFACE" == "modern" ]]; then

        if ! command -v gum >/dev/null 2>&1; then
            print_error "Gum is not installed!"
            echo "Switching to Classic UI."
            INTERFACE="classic"
            continue
        fi

        echo ""

        # Set interface header based on execution mode
        if [[ "$DRY_RUN" == true ]]; then
            mode_header="🧪 UBUNTU POST-INSTALL | DRY RUN"
        else
            mode_header="⚠️ UBUNTU POST-INSTALL | LIVE INSTALLATION"
        fi

        selection=$(gum choose \
            --header "$mode_header" \
            "1) 📦 Install base packages" \
            "2) 🐳 Install Docker & Docker Compose" \
            "3) 🐟 Configure Fish Shell" \
            "4) 🔄 Update system" \
            "5) 🧹 Cleanup system" \
            "6) 🚀 Install everything" \
            "7) 🔀 Switch interface" \
            "0) 🚪 Exit") || exit 0

        choice="${selection%%)*}"

    else

        show_menu

        if ! read -r -p "Select an option [0-7]: " choice; then
            echo ""
            print_error "Unable to read input!"
            exit 1
        fi

    fi

    echo ""

    # Confirm system modifications
    if [[ "$DRY_RUN" == false && "$choice" =~ ^[1-6]$ ]]; then
        if ! confirm_apply; then
            continue
        fi
    fi

    case "$choice" in
    1)
        install_packages || print_error "Package installation failed!"
        ;;
    2)
        install_docker || print_error "Docker installation failed!"
        ;;
    3)
        configure_fish || print_error "Fish configuration failed!"
        ;;
    4)
        update_system
        result=$?

        if [[ "$result" -eq 1 ]]; then
            print_error "System update failed!"
        elif [[ "$result" -eq 2 ]]; then
            echo "⏭️ System update skipped."
        fi
        ;;
    5)
        cleanup_system
        result=$?

        if [[ "$result" -eq 1 ]]; then
            print_error "System cleanup failed!"
        elif [[ "$result" -eq 2 ]]; then
            echo "⏭️ System cleanup skipped."
        fi
        ;;
    6)
        install_all
        result=$?

        if [[ "$result" -eq 1 ]]; then
            print_error "Full installation failed!"
        elif [[ "$result" -eq 2 ]]; then
            echo "⏭️ Full installation not fully completed (operation skipped)."
        fi
        ;;
    7)
        select_interface || exit 1
        continue
        ;;
    0)
        echo "👋 Goodbye!"
        exit 0
        ;;
    *)
        print_error "Invalid option! Choose 0-7."
        ;;
    esac

    echo ""

    if ! read -r -p "Press Enter to return to menu..." _; then
        exit 1
    fi
done
