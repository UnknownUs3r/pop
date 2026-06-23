#!/usr/bin/env bash
set -euo pipefail

# Pop!_OS GNOME customization for Arch-based systems
# Works during fresh install (chroot) or on a running desktop
# Usage: bash install-pop-gnome.sh [--minimal]

MINIMAL=false
for arg in "$@"; do
    case "$arg" in
        --minimal) MINIMAL=true ;;
    esac
done

# --- Install packages (safe everywhere) ---

# Check for AUR helper
if command -v paru &>/dev/null; then
    AUR="paru"
elif command -v yay &>/dev/null; then
    AUR="yay"
else
    echo "Installing paru (AUR helper)..."
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    (cd /tmp/paru && makepkg -si --noconfirm)
    AUR="paru"
fi

# If GNOME isn't installed, pull it in
if ! pacman -Q gnome-shell &>/dev/null; then
    if $MINIMAL; then
        echo "GNOME not detected — installing minimal GNOME..."
        sudo pacman -S --needed --noconfirm \
            gnome-shell gdm gnome-control-center nautilus \
            gnome-terminal gnome-tweaks
    else
        echo "GNOME not detected — installing full gnome group..."
        sudo pacman -S --needed --noconfirm gnome
    fi
fi

# Install Pop packages
$AUR -S --noconfirm \
    pop-shell \
    pop-gtk-theme \
    pop-icon-theme \
    pop-wallpapers \
    plank \
    ttf-fira-sans \
    ttf-fira-code

# Enable display manager (GDM) if none is active
if ! systemctl is-active display-manager &>/dev/null; then
    sudo systemctl enable gdm 2>/dev/null || true
fi

# --- Post-install config (only works inside a running GNOME session) ---

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
    echo "No running display session detected (chroot / tty?)."
    echo "Packages installed. After first boot into GNOME, run:"
    echo "  gnome-extensions enable pop-shell@system76.com"
    echo "  gsettings set org.gnome.desktop.interface gtk-theme Pop"
    echo "  gsettings set org.gnome.desktop.interface icon-theme Pop"
    echo "  gsettings set org.gnome.shell.extensions.user-theme name Pop"
fi
