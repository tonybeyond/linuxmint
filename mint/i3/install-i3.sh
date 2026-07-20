#!/usr/bin/env bash
# =============================================================================
# install-i3.sh — i3 style DTOS/Doom One sur Linux Mint 22.x
# Adapté de tonybeyond/fedoraqtile — 100% paquets apt Noble (pas de pipx/PPA)
# Usage : bash install-i3.sh [--dry-run]   (utilisateur normal, sudo au besoin)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${HOME}/.local/state/mint-setup/install-i3.log"
DRY_RUN=false; ERROR_COUNT=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
mkdir -p "$(dirname "${LOG_FILE}")"

log_ok()    { echo "[$(date +'%H:%M:%S')] ✓ $*" | tee -a "${LOG_FILE}"; }
log_info()  { echo "[$(date +'%H:%M:%S')] · $*" | tee -a "${LOG_FILE}"; }
log_error() { echo "[$(date +'%H:%M:%S')] ✗ $*" | tee -a "${LOG_FILE}" >&2; ((ERROR_COUNT++)) || true; }
run() { if $DRY_RUN; then echo "[DRY] $*" | tee -a "${LOG_FILE}"; return 0; fi; "$@"; }

[[ $EUID -ne 0 ]] || { echo "Lancer SANS sudo."; exit 1; }

# ── 1. Paquets (tous vérifiés présents dans Noble/universe) ───────────────────
PKGS=(
  i3 i3status                       # WM (gaps natifs ≥ 4.22) — i3status en secours
  polybar                           # barre DTOS
  picom                             # compositor (ombres/blur/coins arrondis)
  rofi                              # launcher
  dunst                             # notifications
  nitrogen                          # wallpaper
  flameshot                         # screenshots
  xsecurelock                       # verrouillage
  playerctl brightnessctl           # media/luminosité
  network-manager-gnome blueman     # nm-applet + bluetooth applet
  pavucontrol                       # mixer (click-right volume polybar)
  papirus-icon-theme                # icônes rofi
  alacritty                         # terminal fallback
  x11-xserver-utils                 # xsetroot/xrandr
  fonts-font-awesome                # glyphes de secours polybar
  unzip curl
)
run sudo apt-get update -q
run sudo apt-get install -y "${PKGS[@]}" \
  && log_ok "Paquets apt installés (${#PKGS[@]})" \
  || log_error "Certains paquets ont échoué — vérifier le log"

# ── 2. Mononoki Nerd Font (même police que fedoraqtile) ───────────────────────
FONT_DIR="${HOME}/.local/share/fonts/MononokiNerdFont"
if [[ -d "${FONT_DIR}" ]]; then
  log_ok "Mononoki Nerd Font déjà présente"
elif $DRY_RUN; then
  log_info "[DRY] download Mononoki.zip → ${FONT_DIR}"
else
  mkdir -p "${FONT_DIR}"
  curl -fLo /tmp/Mononoki.zip \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Mononoki.zip \
    && unzip -o /tmp/Mononoki.zip -d "${FONT_DIR}" >/dev/null \
    && rm -f /tmp/Mononoki.zip && fc-cache -f >/dev/null \
    && log_ok "Mononoki Nerd Font installée" \
    || log_error "Police échouée (la barre affichera des carrés sans elle)"
fi

# ── 3. Déploiement configs (backup si existant, jamais d'écrasement aveugle) ──
declare -A CONFIGS=(
  ["${SCRIPT_DIR}/config"]="${HOME}/.config/i3/config"
  ["${SCRIPT_DIR}/polybar/config.ini"]="${HOME}/.config/polybar/config.ini"
  ["${SCRIPT_DIR}/polybar/launch.sh"]="${HOME}/.config/polybar/launch.sh"
  ["${SCRIPT_DIR}/polybar/i3-layout.py"]="${HOME}/.config/polybar/i3-layout.py"
  ["${SCRIPT_DIR}/picom/picom.conf"]="${HOME}/.config/picom/picom.conf"
  ["${SCRIPT_DIR}/rofi/config.rasi"]="${HOME}/.config/rofi/config.rasi"
  ["${SCRIPT_DIR}/dunst/dunstrc"]="${HOME}/.config/dunst/dunstrc"
)
for src in "${!CONFIGS[@]}"; do
  dst="${CONFIGS[$src]}"
  [[ -f "$src" ]] || { log_error "Source manquante : $src"; continue; }
  run mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" ]] && ! $DRY_RUN; then
    cp "$dst" "${dst}.bak-$(date +%Y%m%d-%H%M%S)"
    log_info "Backup : ${dst}.bak-*"
  fi
  run cp "$src" "$dst" && log_ok "Déployé : ${dst/#$HOME/\~}"
done
run chmod +x "${HOME}/.config/polybar/launch.sh" "${HOME}/.config/polybar/i3-layout.py"

# ── 4. Validation ─────────────────────────────────────────────────────────────
if ! $DRY_RUN; then
  i3 -C -c "${HOME}/.config/i3/config" >/dev/null 2>&1 \
    && log_ok "Config i3 valide (i3 -C)" \
    || log_error "Config i3 INVALIDE — lancer : i3 -C -c ~/.config/i3/config"
  [[ -f /usr/share/xsessions/i3.desktop ]] \
    && log_ok "Session i3 disponible à l'écran de connexion" \
    || log_error "i3.desktop absent de /usr/share/xsessions"
fi

echo ""
echo "── Terminé (${ERROR_COUNT} erreur(s)) ──"
echo "1. Déconnexion → écran de login → engrenage → session « i3 »"
echo "2. Wallpaper : lancer nitrogen une fois, choisir l'image (persistant ensuite)"
echo "3. Binds identiques à qtile : Super+Return terminal · Super+Space rofi"
echo "   Super+1..9 workspaces · Super+q fermer · Super+Ctrl+r reload"
echo "Log : ${LOG_FILE}"
[[ ${ERROR_COUNT} -eq 0 ]] || exit 1
