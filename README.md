# Post-Install

A collection of Bash post-installation scripts for Linux distributions.

Automate initial system setup, package installation, and configuration after a fresh Linux installation.

## Supported distributions

- **Ubuntu** — `ubuntu-post.sh`
- **Arch Linux / CachyOS** — `arch-post-v2.sh`
- **Fedora** — `fedora-post-v2.sh`

## Quick Start

Download and launch the interactive installer:

```bash
curl -fsSL https://raw.githubusercontent.com/Innerfrost/Post-Install/main/install.sh -o /tmp/post-install.sh && bash /tmp/post-install.sh
```

The installer displays a menu to select your Linux distribution.

The selected script is downloaded to:

```text
~/scripts/
```

**The downloaded post-install script is not executed automatically.**

Review the script before running it.

## Manual Download

You can also download individual scripts directly from the `scripts/` directory in this repository.

## Requirements

- Bash
- curl or wget
- Internet connection

Individual post-install scripts may require additional utilities and administrator privileges.

## Repository Structure

```text
Post-Install/
├── install.sh
├── README.md
└── scripts/
    ├── ubuntu-post.sh
    ├── arch-post-v2.sh
    └── fedora-post-v2.sh
```

## Safety

The installer checks the downloaded script's Bash syntax and avoids overwriting existing files.

Always review downloaded scripts before executing them.

## License

No license has been specified yet.
