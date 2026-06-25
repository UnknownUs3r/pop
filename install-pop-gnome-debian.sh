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

# --- Check sudo access ---
if [[ $EUID -ne 0 ]]; then
    if ! groups | grep -q '\bsudo\b' 2>/dev/null; then
        echo "User '$USER' is not in the sudo group."
        echo "Run this command as root, then re-run the script:"
        echo "  usermod -aG sudo $USER"
        echo ""
        echo "Or run this script as root directly:"
        echo "  su -c 'bash $0'"
        exit 1
    fi
fi

# --- Add /usr/sbin to PATH (Debian doesn't include it for normal users) ---
if [[ ":$PATH:" != *":/usr/sbin:"* ]]; then
    export PATH="$PATH:/usr/sbin:/sbin"
fi
# Persist for future shells
if ! grep -q '/usr/sbin' ~/.bashrc 2>/dev/null; then
    echo 'export PATH="$PATH:/usr/sbin:/sbin"' >> ~/.bashrc 2>/dev/null || true
fi

# --- Detect distro ---
if grep -qi ubuntu /etc/os-release 2>/dev/null; then
    DISTRO="ubuntu"
elif grep -qi debian /etc/os-release 2>/dev/null; then
    DISTRO="debian"
else
    echo "Unsupported distro. This script is for Debian/Ubuntu-based systems."
    exit 1
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

# --- Install Pop packages (direct .deb download, no repo key needed) ---
sudo apt install -y curl fonts-firacode plank gnome-shell-extension-prefs
# fonts-fira-sans not in Debian repos — download from Google Fonts
if ! dpkg -l fonts-fira-sans &>/dev/null; then
    mkdir -p ~/.local/share/fonts
    curl -sL "https://github.com/google/fonts/raw/main/ofl/firasans/FiraSans-Regular.ttf" \
        -o ~/.local/share/fonts/FiraSans-Regular.ttf 2>/dev/null || true
    curl -sL "https://github.com/google/fonts/raw/main/ofl/firasans/FiraSans-Bold.ttf" \
        -o ~/.local/share/fonts/FiraSans-Bold.ttf 2>/dev/null || true
    fc-cache -f ~/.local/share/fonts 2>/dev/null || true
fi
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
for pkg in pop-shell pop-gtk-theme pop-icon-theme pop-wallpapers; do
    url=$(curl -s "http://apt.pop-os.org/release/dists/jammy/main/binary-amd64/Packages.gz" \
        | gunzip -c 2>/dev/null \
        | awk -v pkg="$pkg" '$1 == "Package:" && $2 == pkg { f=1 } f && /^Filename:/ { print $2; exit }')
    if [ -n "$url" ]; then
        curl -sLO "http://apt.pop-os.org/release/$url"
    fi
done
if ls *.deb 1>/dev/null 2>&1; then
    sudo dpkg -i *.deb 2>&1 || true
    sudo apt install -f -y 2>&1 || true
else
    echo "WARNING: No .deb files were downloaded. Packages may not be available for your architecture."
fi
cd / && rm -rf "$TMPDIR"
# Verify extensions landed
for ext in /usr/share/gnome-shell/extensions/pop-shell@system76.com ~/.local/share/gnome-shell/extensions/pop-shell@system76.com; do
    if [ -d "$ext" ]; then
        sudo glib-compile-schemas "$ext/schemas/" 2>/dev/null || true
        echo "Pop Shell found at: $ext"
        break
    fi
done
if [ ! -d /usr/share/gnome-shell/extensions/pop-shell@system76.com ] && \
   [ ! -d ~/.local/share/gnome-shell/extensions/pop-shell@system76.com ]; then
    echo "ERROR: Pop Shell extension was not installed. Pop packages may not be compatible with this Debian version."
fi

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
    TERM_PROFILE="$(gsettings get org.gnome.Terminal.ProfilesList default)"
    TERM_PROFILE="${TERM_PROFILE//"'"}"
    if [ -n "$TERM_PROFILE" ]; then
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$TERM_PROFILE/" font "Fira Code 11"
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$TERM_PROFILE/" use-system-font false
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$TERM_PROFILE/" audible-bell false
        gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$TERM_PROFILE/" visible-name "Pop"
    fi

    # --- Plank dock: autostart + config ---
    mkdir -p ~/.config/autostart
    printf '%s\n' \
        '[Desktop Entry]' \
        'Type=Application' \
        'Name=Plank' \
        'Exec=plank' \
        'Hidden=false' \
        'NoDisplay=false' \
        'X-GNOME-Autostart-enabled=true' \
        > ~/.config/autostart/plank.desktop
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
