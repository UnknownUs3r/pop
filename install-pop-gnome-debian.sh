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

# --- Install Pop themes (downloaded from GitHub, no repo needed) ---
sudo apt install -y curl wget fonts-firacode plank gnome-shell-extension-prefs unzip

# Fonts (Fira Sans not in Debian repos — download from GitHub)
mkdir -p ~/.local/share/fonts
curl -sL "https://github.com/google/fonts/raw/main/ofl/firasans/FiraSans-Regular.ttf" \
    -o ~/.local/share/fonts/FiraSans-Regular.ttf 2>/dev/null || true
curl -sL "https://github.com/google/fonts/raw/main/ofl/firasans/FiraSans-Bold.ttf" \
    -o ~/.local/share/fonts/FiraSans-Bold.ttf 2>/dev/null || true
fc-cache -f ~/.local/share/fonts 2>/dev/null || true

# Pop GTK/Shell/Sound themes from source
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
wget -q "https://github.com/pop-os/gtk-theme/archive/master.zip" -O gtk-theme.zip
unzip -q gtk-theme.zip
sudo cp -r gtk-theme-master/usr/share/themes/* /usr/share/themes/ 2>/dev/null || true
sudo cp -r gtk-theme-master/usr/share/gnome-shell/* /usr/share/gnome-shell/ 2>/dev/null || true
sudo cp -r gtk-theme-master/usr/share/sounds/* /usr/share/sounds/ 2>/dev/null || true
sudo cp -r gtk-theme-master/usr/share/icons/* /usr/share/icons/ 2>/dev/null || true
cd / && rm -rf "$TMPDIR"

# Pop Shell extension from GNOME Extensions website (works on any distro with GNOME 40+)
wget -q "https://extensions.gnome.org/extension-data/pop-shellsystem76.com.v1.shell-extension.zip" \
    -O /tmp/pop-shell.zip 2>/dev/null || true
if [ -f /tmp/pop-shell.zip ] && [ -s /tmp/pop-shell.zip ]; then
    mkdir -p ~/.local/share/gnome-shell/extensions/pop-shell@system76.com
    unzip -qo /tmp/pop-shell.zip -d ~/.local/share/gnome-shell/extensions/pop-shell@system76.com/ 2>/dev/null || true
    glib-compile-schemas ~/.local/share/gnome-shell/extensions/pop-shell@system76.com/schemas/ 2>/dev/null || true
    rm /tmp/pop-shell.zip
    echo "Pop Shell installed from GNOME Extensions."
else
    echo "Pop Shell download failed. Install manually at: https://extensions.gnome.org/extension/4338/pop-shell/"
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
