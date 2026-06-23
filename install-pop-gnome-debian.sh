#!/usr/bin/env bash
set -euo pipefail

# Pop!_OS GNOME customization for Debian/Ubuntu-based systems
# Usage: bash install-pop-gnome-debian.sh [--minimal]

MINIMAL=false
for arg in "$@"; do
    case "$arg" in
        --minimal) MINIMAL=true ;;
    esac
done

# --- Detect distro ---
if grep -qi ubuntu /etc/os-release 2>/dev/null; then
    DISTRO="ubuntu"
elif grep -qi debian /etc/os-release 2>/dev/null; then
    DISTRO="debian"
else
    echo "Unsupported distro. This script is for Debian/Ubuntu-based systems."
    exit 1
fi

# --- Add Pop repo if needed (packages not in repos) ---
if ! apt-cache show pop-shell &>/dev/null; then
    if [ "$DISTRO" = "ubuntu" ]; then
        echo "Adding System76 PPA..."
        sudo add-apt-repository -y ppa:system76/pop
        sudo apt update
    else
        echo "Pop packages not found in Debian repos."
        echo "Enable Debian backports or testing, or see:"
        echo "  https://salsa.debian.org/gnome-team/pop-shell"
        echo ""
        echo "Falling back to installing from Pop's Ubuntu repo (may have issues on Debian)..."
        sudo apt install -y curl gpg
        curl -fsSL https://repo.pop-os.org/repo.gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/pop.gpg
        echo "deb https://repo.pop-os.org/repo/ noble main" | sudo tee /etc/apt/sources.list.d/pop.list
        sudo apt update
    fi
fi

# --- Install GNOME if missing ---
if ! dpkg -l gnome-shell &>/dev/null; then
    if $MINIMAL; then
        echo "Installing minimal GNOME..."
        sudo apt install -y gnome-shell gdm3 gnome-control-center nautilus gnome-terminal gnome-tweaks
    else
        echo "Installing full GNOME..."
        sudo apt install -y gnome
    fi
fi

# --- Install Pop packages ---
sudo apt install -y \
    pop-shell \
    pop-gtk-theme \
    pop-icon-theme \
    pop-wallpapers \
    plank \
    fonts-fira-sans fonts-fira-code

# --- Enable display manager ---
if ! systemctl is-active display-manager &>/dev/null; then
    sudo systemctl enable gdm3 2>/dev/null || true
fi

# --- Post-install config ---
if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]] && command -v gsettings &>/dev/null; then
    echo "Applying theme settings..."
    gnome-extensions enable pop-shell@system76.com 2>/dev/null || true
    gsettings set org.gnome.desktop.interface gtk-theme "Pop" 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme "Pop" 2>/dev/null || true
    gsettings set org.gnome.shell.extensions.user-theme name "Pop" 2>/dev/null || true
    # --- Pop keybindings ---
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybindings \
        "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybindings.custom0:/ name "Terminal"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybindings.custom0:/ command "gnome-terminal"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybindings.custom0:/ binding "<Super>Return"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybindings.custom1:/ name "Files"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybindings.custom1:/ command "nautilus --new-window"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybindings.custom1:/ binding "<Super>e"

    # --- GNOME tweaks ---
    gsettings set org.gnome.desktop.interface enable-hot-corners false
    gsettings set org.gnome.mutter center-new-windows true
    gsettings set org.gnome.mutter dynamic-workspaces true
    gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
    gsettings set org.gnome.desktop.interface clock-show-weekday true
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"

    # --- Terminal: Fira Code + Pop colors ---
    TERM_PROFILE="$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \"'\" )"
    if [ -n "$TERM_PROFILE" ]; then
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$TERM_PROFILE/" font "Fira Code 11"
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$TERM_PROFILE/" use-system-font false
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$TERM_PROFILE/" audible-bell false
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$TERM_PROFILE/" visible-name "Pop"
    fi

    # --- Plank dock: autostart + config ---
    mkdir -p ~/.config/autostart
    cat > ~/.config/autostart/plank.desktop << 'PLANKEOF'
[Desktop Entry]
Type=Application
Name=Plank
Exec=plank
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
PLANKEOF
    dconf write /net/launchpad/plank/docks/dock1/position "'bottom'" 2>/dev/null || true
    dconf write /net/launchpad/plank/docks/dock1/theme "'Gtk+'" 2>/dev/null || true
    dconf write /net/launchpad/plank/docks/dock1/hide-mode "'intellihide'" 2>/dev/null || true
    dconf write /net/launchpad/plank/docks/dock1/icon-size 48 2>/dev/null || true

    echo "Done. Log out and back in for full effect."
else
    echo "No running display session detected."
    echo "Packages installed. After first boot into GNOME, run:"
    echo "  gnome-extensions enable pop-shell@system76.com"
    echo "  gsettings set org.gnome.desktop.interface gtk-theme Pop"
    echo "  gsettings set org.gnome.desktop.interface icon-theme Pop"
    echo "  gsettings set org.gnome.shell.extensions.user-theme name Pop"
fi
