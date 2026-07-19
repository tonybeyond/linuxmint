#!/usr/bin/env bash
# =============================================================================
# optimize-mint.sh — Optimisations système + applications Linux Mint 22.x
# =============================================================================
# Cible : Linux Mint 22.x (base Ubuntu 24.04 Noble), Cinnamon / XFCE
# Usage : sudo bash optimize-mint.sh [--dry-run] [--dns-cache]
#
#   --dry-run    : affiche les actions sans les exécuter
#   --dns-cache  : active le cache DNS systemd-resolved (OPTIONNEL — Mint
#                  n'utilise pas resolved par défaut ; à tester avant adoption)
#
# Sections :
#   1. Tuning noyau (sysctl)          4. Nettoyage bloatware
#   2. SSD/NVMe + I/O scheduler       5. Applications (Flatpak + Betterbird)
#   3. Énergie + services             6. Post-install + récap
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
TARGET_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
LOG_FILE="/var/log/mint-optimize.log"
DRY_RUN=false
DNS_CACHE=false
ERROR_COUNT=0
declare -a SUMMARY_INSTALLED=() SUMMARY_REMOVED=() SUMMARY_TUNED=()

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --dns-cache) DNS_CACHE=true ;;
  esac
done

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()    { echo "[$(date +'%H:%M:%S')] ·     $*" | tee -a "${LOG_FILE}"; }
log_ok()      { echo "[$(date +'%H:%M:%S')] ✓     $*" | tee -a "${LOG_FILE}"; }
log_error()   { echo "[$(date +'%H:%M:%S')] ✗     $*" | tee -a "${LOG_FILE}" >&2; ((ERROR_COUNT++)) || true; }
log_section() { echo "" | tee -a "${LOG_FILE}"; echo "[$(date +'%H:%M:%S')] ════ $* ════" | tee -a "${LOG_FILE}"; }
log_dry()     { echo "[$(date +'%H:%M:%S')] [DRY] $*" | tee -a "${LOG_FILE}"; }

run() { if $DRY_RUN; then log_dry "$*"; return 0; fi; "$@"; }

is_installed() { dpkg -s "$1" &>/dev/null; }

as_user() { su -s /bin/bash -c "HOME=${TARGET_HOME} $*" "${TARGET_USER}"; }

# ── Garde-fous ────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || { echo "Requiert root : sudo bash optimize-mint.sh"; exit 1; }
[[ -n "${TARGET_USER}" ]] || { echo "Impossible de déterminer l'utilisateur cible (lancer via sudo)."; exit 1; }

grep -q 'ID=linuxmint' /etc/os-release 2>/dev/null \
  || log_error "AVERTISSEMENT : /etc/os-release ≠ linuxmint — script conçu pour Mint 22.x"

mkdir -p "$(dirname "${LOG_FILE}")"
log_info "=== optimize-mint — $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2) — user: ${TARGET_USER} ==="
$DRY_RUN && log_info "MODE DRY-RUN"

# =============================================================================
# 1. TUNING NOYAU (sysctl)
# =============================================================================
log_section "1/6 — Tuning noyau (sysctl)"

SYSCTL_FILE="/etc/sysctl.d/99-mint-tuning.conf"
if [[ -f "${SYSCTL_FILE}" ]]; then
  log_ok "${SYSCTL_FILE} déjà présent — non écrasé"
elif $DRY_RUN; then
  log_dry "Écriture ${SYSCTL_FILE} + sysctl --system"
else
  cat > "${SYSCTL_FILE}" << 'SYSCTL'
# ═══ mint-tuning — desktop/workstation ═══
# Chaque valeur est documentée. Rollback : supprimer ce fichier + sysctl --system

# ── Mémoire ──────────────────────────────────────────────────────────────────
# Swappiness bas : desktop avec RAM suffisante — privilégier la RAM au swap.
# Défaut Ubuntu = 60 (orienté serveur). 10 = swap seulement sous pression réelle.
vm.swappiness = 10

# Réduit l'agressivité de récupération du cache dentries/inodes.
# Défaut = 100. 50 = garde les métadonnées filesystem en cache plus longtemps
# → navigation fichiers et lancements d'apps plus rapides.
vm.vfs_cache_pressure = 50

# Writeback : limite les pages sales avant flush forcé.
# Évite les micro-freezes lors de grosses copies sur SSD/NVMe.
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

# ── Réseau ───────────────────────────────────────────────────────────────────
# BBR : congestion control moderne (meilleur débit/latence que cubic sur
# liens à latence variable — WiFi, VPN type NetBird). Requiert kernel ≥ 4.9.
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP Fast Open (client + serveur) : économise 1 RTT sur connexions répétées.
net.ipv4.tcp_fastopen = 3

# Buffers réseau élargis pour liens ≥ 1 Gbps (défauts pensés pour 100 Mbps).
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# MTU probing : évite les blackholes PMTU (utile derrière VPN/tunnels).
net.ipv4.tcp_mtu_probing = 1

# ── Inotify ──────────────────────────────────────────────────────────────────
# Watches élargis : IDE (Zed), sync clients, conteneurs épuisent le défaut (8192).
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
SYSCTL
  sysctl --system >/dev/null 2>&1 \
    && log_ok "sysctl appliqué (${SYSCTL_FILE})" \
    || log_error "sysctl --system a échoué"
  SUMMARY_TUNED+=("sysctl : swappiness=10, BBR+fq, tcp_fastopen, inotify élargi")
fi

# Vérification BBR effectif
if ! $DRY_RUN; then
  CC=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
  [[ "${CC}" == "bbr" ]] && log_ok "Congestion control actif : bbr" \
    || log_error "BBR non actif (actuel : ${CC}) — vérifier module tcp_bbr"
fi

# =============================================================================
# 2. SSD/NVMe — TRIM + I/O SCHEDULER
# =============================================================================
log_section "2/6 — SSD/NVMe"

# TRIM hebdomadaire : indispensable pour maintenir les perfs SSD dans le temps.
# fstrim.timer est présent par défaut sur Noble mais pas toujours actif.
if systemctl is-enabled fstrim.timer &>/dev/null; then
  log_ok "fstrim.timer déjà actif"
else
  run systemctl enable --now fstrim.timer \
    && { log_ok "fstrim.timer activé (TRIM hebdomadaire)"; SUMMARY_TUNED+=("fstrim.timer activé"); } \
    || log_error "Activation fstrim.timer échouée"
fi

# I/O scheduler : 'none' pour NVMe (le contrôleur gère mieux que le kernel),
# 'mq-deadline' pour SSD SATA (latence prévisible), 'bfq' pour HDD (équité).
UDEV_RULE="/etc/udev/rules.d/60-ioschedulers.rules"
if [[ -f "${UDEV_RULE}" ]]; then
  log_ok "Règle udev I/O scheduler déjà présente"
elif $DRY_RUN; then
  log_dry "Écriture ${UDEV_RULE} (none/mq-deadline/bfq selon type de disque)"
else
  cat > "${UDEV_RULE}" << 'UDEV'
# I/O schedulers par type de périphérique (mint-tuning)
# NVMe : none — file multi-queue native, pas de réordonnancement kernel utile
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
# SSD SATA (non-rotationnel) : mq-deadline — latence faible et stable
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# HDD (rotationnel) : bfq — équité entre process, meilleur desktop feel
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
UDEV
  udevadm control --reload-rules && udevadm trigger --subsystem-match=block \
    && log_ok "Schedulers I/O configurés (${UDEV_RULE})" \
    || log_error "udevadm reload échoué"
  SUMMARY_TUNED+=("I/O schedulers : none (NVMe) / mq-deadline (SSD) / bfq (HDD)")
fi

# =============================================================================
# 3. ÉNERGIE + SERVICES
# =============================================================================
log_section "3/6 — Énergie & services"

# thermald : gestion thermique proactive Intel — évite le throttling brutal.
# Sans effet sur AMD (le service reste simplement inactif).
if grep -q "GenuineIntel" /proc/cpuinfo; then
  if is_installed thermald; then
    log_ok "thermald déjà installé"
  else
    run apt-get install -y thermald \
      && { log_ok "thermald installé (CPU Intel détecté)"; SUMMARY_INSTALLED+=("thermald"); } \
      || log_error "thermald échoué"
  fi
else
  log_info "CPU non-Intel — thermald non installé"
fi

# CPU governor : sur kernels récents (intel_pstate/amd-pstate actifs par défaut
# sur Noble), 'powersave' avec pstate = déjà dynamique. On ne force PAS
# 'performance' en permanence (chauffe/conso sans gain desktop mesurable).
# → Aucune action ; documenté ici volontairement.
log_info "CPU governor : géré par intel_pstate/amd-pstate (aucun override — choix documenté)"

# preload : précharge en RAM les binaires fréquemment utilisés → lancements
# d'applications plus rapides. Pertinent si ≥ 8 Go RAM.
TOTAL_RAM_GB=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
if [[ ${TOTAL_RAM_GB} -ge 8 ]]; then
  if is_installed preload; then
    log_ok "preload déjà installé"
  else
    run apt-get install -y preload \
      && { log_ok "preload installé (${TOTAL_RAM_GB} Go RAM)"; SUMMARY_INSTALLED+=("preload"); } \
      || log_error "preload échoué"
  fi
else
  log_info "RAM ${TOTAL_RAM_GB} Go < 8 Go — preload non installé (contre-productif)"
fi

# Services désactivables sans risque sur un desktop Mint :
# - NetworkManager-wait-online : bloque le boot en attendant le réseau
#   (utile serveur, inutile desktop — gain de boot 5-15 s)
SERVICES_DISABLE=(NetworkManager-wait-online.service)
for svc in "${SERVICES_DISABLE[@]}"; do
  if systemctl is-enabled "$svc" &>/dev/null; then
    run systemctl disable "$svc" \
      && { log_ok "Désactivé : $svc"; SUMMARY_TUNED+=("service désactivé : $svc"); } \
      || log_error "Désactivation $svc échouée"
  else
    log_ok "$svc déjà inactif"
  fi
done

# DNS caching (OPTIONNEL — flag --dns-cache) :
# Mint n'active pas systemd-resolved par défaut (résolution via NetworkManager).
# Le cache local réduit la latence DNS mais peut interférer avec des setups
# VPN/split-DNS (NetBird). D'où l'opt-in explicite.
if $DNS_CACHE; then
  if systemctl is-active systemd-resolved &>/dev/null; then
    log_ok "systemd-resolved déjà actif"
  else
    run systemctl enable --now systemd-resolved \
      && run ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf \
      && { log_ok "Cache DNS systemd-resolved activé"; SUMMARY_TUNED+=("DNS cache : systemd-resolved"); } \
      || log_error "Activation systemd-resolved échouée"
  fi
else
  log_info "Cache DNS non activé (relancer avec --dns-cache pour l'activer)"
fi

# =============================================================================
# 4. NETTOYAGE BLOATWARE
# =============================================================================
log_section "4/6 — Nettoyage applications par défaut"

# Liste documentée — chaque suppression est justifiée :
#   hypnotix     : client IPTV Mint — inutile sans abonnement IPTV
#   rhythmbox    : lecteur audio — redondant (VLC/Shortwave couvrent l'usage)
#   thunderbird  : remplacé par Betterbird (section 5)
#   gnome-mahjongg/mines/sudoku : jeux préinstallés
#   mintwelcome  : écran de bienvenue — inutile après setup initial
# CONSERVÉS explicitement : LibreOffice, Flatpak, warpinator (partage LAN utile),
# celluloid (lecteur vidéo léger), timeshift (snapshots système — critique).
BLOAT=(hypnotix rhythmbox thunderbird gnome-mahjongg gnome-mines gnome-sudoku mintwelcome)

for pkg in "${BLOAT[@]}"; do
  if is_installed "$pkg"; then
    run apt-get remove -y "$pkg" \
      && { log_ok "Retiré : $pkg"; SUMMARY_REMOVED+=("$pkg"); } \
      || log_error "Suppression $pkg échouée"
  else
    log_info "$pkg absent — rien à faire"
  fi
done

run apt-get autoremove --purge -y >/dev/null && log_ok "autoremove OK" || true

# Garde-fous exigés : vérifier que LibreOffice et Flatpak sont intacts
is_installed libreoffice-core || is_installed libreoffice-writer \
  && log_ok "LibreOffice présent (conservé)" \
  || log_error "LibreOffice ABSENT — vérifier (ne devait pas être supprimé)"
command -v flatpak &>/dev/null \
  && log_ok "Flatpak présent (conservé)" \
  || log_error "Flatpak ABSENT — vérifier"

# =============================================================================
# 5. APPLICATIONS
# =============================================================================
log_section "5/6 — Applications"

# ── Flatpak (Flathub est préconfiguré sur Mint, on vérifie quand même) ───────
# Garde-fou : réinstalle le support Flatpak s'il manque (ne devrait jamais arriver sur Mint)
if ! command -v flatpak &>/dev/null; then
  run apt-get install -y flatpak && log_ok "Support Flatpak (ré)installé" \
    || log_error "Installation flatpak échouée — apps Flatpak sautées"
fi
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true

declare -A FLATPAKS=(
  [com.github.flxzt.rnote]="Rnote"
  [com.github.tchx84.Flatseal]="Flatseal"
  [dev.zed.Zed]="Zed"
  [com.rafaelmardojai.Blanket]="Blanket"
  [de.haeckerfelix.Shortwave]="Shortwave"
)

for app_id in "${!FLATPAKS[@]}"; do
  name="${FLATPAKS[$app_id]}"
  if flatpak info "$app_id" &>/dev/null; then
    log_ok "${name} déjà installé (flatpak)"
  else
    run flatpak install -y --noninteractive flathub "$app_id" \
      && { log_ok "${name} installé (flatpak)"; SUMMARY_INSTALLED+=("${name} (flatpak)"); } \
      || log_error "Flatpak ${name} échoué"
  fi
done

# ── Brave Origin ──────────────────────────────────────────────────────────────
# Repris de ubuntu2404/post-install.sh : version minimaliste (sans Leo/Rewards/
# VPN/Wallet), fallback brave-browser si brave-origin absent du repo.
if command -v brave-origin &>/dev/null || command -v brave-browser &>/dev/null; then
  log_ok "Brave déjà présent"
elif $DRY_RUN; then
  log_dry "Ajout keyring + repo Brave, apt install brave-origin (fallback brave-browser)"
else
  curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
    https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
    && curl -fsSLo /etc/apt/sources.list.d/brave-browser.sources \
      https://brave-browser-apt-release.s3.brave.com/brave-browser.sources \
    && apt-get update -q \
    || log_error "Ajout repo Brave échoué"
  if apt-get install -y brave-origin 2>>"${LOG_FILE}"; then
    log_ok "Brave Origin installé (sans Leo/Rewards/VPN/Wallet)"
    SUMMARY_INSTALLED+=("Brave Origin")
  elif apt-get install -y brave-browser 2>>"${LOG_FILE}"; then
    log_ok "Brave standard installé (brave-origin absent du repo — fallback)"
    SUMMARY_INSTALLED+=("Brave (fallback)")
  else
    log_error "Brave install (origin + fallback) FAILED"
  fi
fi

# ── Betterbird ────────────────────────────────────────────────────────────────
# Pas de PPA officiel Betterbird — méthode officielle = script d'installation
# du projet (tarball → /opt/betterbird + .desktop + MIME).
# Source : github.com/Betterbird/thunderbird-patches/install-on-linux/
if [[ -x /opt/betterbird/betterbird/betterbird ]] || command -v betterbird &>/dev/null; then
  log_ok "Betterbird déjà installé"
elif $DRY_RUN; then
  log_dry "Download + exécution install-betterbird.sh officiel (→ /opt/betterbird)"
else
  BB_SCRIPT="/tmp/install-betterbird.sh"
  if curl -fsSL -o "${BB_SCRIPT}" \
    "https://raw.githubusercontent.com/Betterbird/thunderbird-patches/main/install-on-linux/install-betterbird.sh"; then
    chmod +x "${BB_SCRIPT}"
    bash "${BB_SCRIPT}" 2>>"${LOG_FILE}" \
      && { log_ok "Betterbird installé (/opt/betterbird)"; SUMMARY_INSTALLED+=("Betterbird"); } \
      || log_error "Script Betterbird échoué — alternative : flatpak install flathub eu.betterbird.Betterbird"
    rm -f "${BB_SCRIPT}"
  else
    log_error "Download script Betterbird échoué"
  fi
fi

# Client mail par défaut (xdg) — pour l'utilisateur cible, pas root
if ! $DRY_RUN && [[ -f /usr/share/applications/eu.betterbird.Betterbird.desktop ]]; then
  as_user "xdg-settings set default-url-scheme-handler mailto eu.betterbird.Betterbird.desktop" 2>/dev/null \
    && log_ok "Betterbird défini comme client mail par défaut" \
    || log_error "xdg-settings mailto échoué (à faire manuellement : Préférences > Applications préférées)"
fi

# ── LibreOffice à jour ────────────────────────────────────────────────────────
run apt-get install --only-upgrade -y 'libreoffice*' 2>/dev/null \
  && log_ok "LibreOffice à jour" || log_info "LibreOffice : aucune mise à jour disponible"

# =============================================================================
# 6. POST-INSTALLATION + RÉCAPITULATIF
# =============================================================================
log_section "6/6 — Post-installation"

run apt-get update -q
run apt-get upgrade -y && log_ok "Système à jour" || log_error "apt upgrade échoué"
run apt-get autoclean >/dev/null || true

# Reconstruire la base locate si présente
if command -v updatedb &>/dev/null; then
  run updatedb && log_ok "updatedb reconstruit" || true
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  optimize-mint terminé — ${ERROR_COUNT} erreur(s)"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  INSTALLÉ :"
for i in "${SUMMARY_INSTALLED[@]:-aucun}"; do echo "║    + $i"; done
echo "║  SUPPRIMÉ :"
for i in "${SUMMARY_REMOVED[@]:-aucun}"; do echo "║    - $i"; done
echo "║  OPTIMISÉ :"
for i in "${SUMMARY_TUNED[@]:-aucun}"; do echo "║    ~ $i"; done
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Redémarrage recommandé (sysctl, schedulers, services)       ║"
echo "║  Log : ${LOG_FILE}"
echo "╚══════════════════════════════════════════════════════════════╝"

[[ ${ERROR_COUNT} -eq 0 ]] || exit 1
