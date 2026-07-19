#!/usr/bin/env bash
# =============================================================================
# config-mint.sh — Configuration Linux Mint 22.x (base Ubuntu 24.04 Noble)
# ble.sh · Starship · Hack Nerd Font · WaveTerm · NetBird
# =============================================================================
# Cible : Linux Mint 22.x Cinnamon / XFCE
# Usage : bash config-mint.sh [--dry-run]
# À lancer en tant qu'utilisateur normal (PAS root) — sudo est demandé au besoin.
#
# Patterns repris de tonybeyond/ubuntu2404 (bash-setup.sh, post-install.sh) :
#   - logging horodaté, idempotence par marqueurs, backup .bashrc
#   - WaveTerm : dernière release GitHub + configs JSON déployées
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${HOME}/.local/state/mint-setup/config-mint.log"
DRY_RUN=false
ERROR_COUNT=0

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

mkdir -p "$(dirname "${LOG_FILE}")"

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()    { echo "[$(date +'%H:%M:%S')] ·     $*" | tee -a "${LOG_FILE}"; }
log_ok()      { echo "[$(date +'%H:%M:%S')] ✓     $*" | tee -a "${LOG_FILE}"; }
log_error()   { echo "[$(date +'%H:%M:%S')] ✗     $*" | tee -a "${LOG_FILE}" >&2; ((ERROR_COUNT++)) || true; }
log_section() { echo "" | tee -a "${LOG_FILE}"; echo "[$(date +'%H:%M:%S')] ════ $* ════" | tee -a "${LOG_FILE}"; }
log_dry()     { echo "[$(date +'%H:%M:%S')] [DRY] $*" | tee -a "${LOG_FILE}"; }

# run : exécute ou affiche selon --dry-run
run() {
  if $DRY_RUN; then
    log_dry "$*"
    return 0
  fi
  "$@"
}

# ── Garde-fous ────────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] || { echo "Lancer SANS sudo (utilisateur normal). sudo sera demandé au besoin."; exit 1; }

if ! grep -q 'ID=linuxmint' /etc/os-release 2>/dev/null; then
  log_error "Ce script cible Linux Mint. /etc/os-release ne contient pas ID=linuxmint."
  read -rp "Continuer quand même ? [y/N] " ans
  [[ "${ans,,}" == "y" ]] || exit 1
fi

MINT_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
log_info "=== config-mint — Linux Mint ${MINT_VERSION} — $(date) ==="
$DRY_RUN && log_info "MODE DRY-RUN : aucune modification ne sera appliquée"

# =============================================================================
# 1. OPTIMISATIONS BASH (ble.sh + Starship — PAS de zsh)
# =============================================================================
log_section "1/4 — Dépendances apt"

# gawk : requis par ble.sh · fzf/eza/bat : outillage CLI du .bashrc
APT_DEPS=(git curl wget fzf bash-completion gawk eza bat unzip make ca-certificates gnupg)
run sudo apt-get update -q
run sudo apt-get install -y "${APT_DEPS[@]}" \
  && log_ok "Dépendances apt OK" \
  || log_error "Certains paquets apt ont échoué — on continue (non critique)"

log_section "1/4 — ble.sh"
# ble.sh : autosuggestions + syntax highlighting natifs bash (équivalent zsh-autosuggestions)
if [[ -f "${HOME}/.local/share/blesh/ble.sh" ]]; then
  log_ok "ble.sh déjà installé (~/.local/share/blesh)"
else
  if [[ ! -d "${HOME}/ble.sh" ]]; then
    run git clone --recursive --depth 1 --shallow-submodules \
      https://github.com/akinomyoga/ble.sh.git "${HOME}/ble.sh" \
      || log_error "Clone ble.sh échoué"
  fi
  if [[ -d "${HOME}/ble.sh" ]] || $DRY_RUN; then
    run make -C "${HOME}/ble.sh" install PREFIX="${HOME}/.local" \
      && log_ok "ble.sh installé → ~/.local/share/blesh" \
      || log_error "Build ble.sh échoué (CRITIQUE pour la partie bash)"
  fi
fi

log_section "1/4 — Starship"
if command -v starship &>/dev/null; then
  log_ok "Starship déjà présent ($(starship --version | head -1))"
else
  # Installeur officiel — écrit dans /usr/local/bin (demande sudo lui-même)
  if $DRY_RUN; then
    log_dry "curl -sS https://starship.rs/install.sh | sh -s -- --yes"
  else
    curl -sS https://starship.rs/install.sh | sh -s -- --yes \
      && log_ok "Starship installé" || log_error "Installation Starship échouée"
  fi
fi

# Config Starship — identique au dépôt ubuntu2404, symbole OS adapté Mint
STARSHIP_TOML="${HOME}/.config/starship.toml"
if [[ -f "${STARSHIP_TOML}" ]]; then
  log_ok "starship.toml existant — non écrasé (idempotence)"
else
  run mkdir -p "${HOME}/.config"
  if ! $DRY_RUN; then
    cat > "${STARSHIP_TOML}" << 'TOML'
# Starship — deux lignes, info contextuelle (source : tonybeyond/ubuntu2404)
format = """
$os$username$hostname$directory$git_branch$git_status$python$nodejs$rust$golang$docker_context
$character"""

[os]
disabled = false
[os.symbols]
Mint = "󰣭 "
Ubuntu = " "

[username]
style_user  = "bold green"
style_root  = "bold red"
show_always = true
format      = "[$user]($style)@"

[hostname]
ssh_only = false
format   = "[$hostname](bold blue) "

[directory]
truncation_length = 3
style             = "bold cyan"

[git_branch]
format = "[$symbol$branch]($style) "
style  = "bold yellow"

[character]
success_symbol = "[❯](bold green)"
error_symbol   = "[❯](bold red)"
TOML
  fi
  log_ok "Config Starship créée (${STARSHIP_TOML})"
fi

log_section "1/4 — Hack Nerd Font"
FONT_DIR="${HOME}/.local/share/fonts/HackNerdFont"
if [[ -d "${FONT_DIR}" ]]; then
  log_ok "Hack Nerd Font déjà présente"
else
  run mkdir -p "${FONT_DIR}"
  if ! $DRY_RUN; then
    curl -fLo /tmp/Hack.zip \
      https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip \
      && unzip -o /tmp/Hack.zip -d "${FONT_DIR}" >/dev/null \
      && rm -f /tmp/Hack.zip \
      && fc-cache -f >/dev/null \
      && log_ok "Hack Nerd Font installée" \
      || log_error "Hack Nerd Font échouée (non critique)"
  else
    log_dry "download + unzip Hack.zip → ${FONT_DIR}"
  fi
fi

log_section "1/4 — Patch ~/.bashrc"
BASHRC="${HOME}/.bashrc"
MARKER="# ── mint bash tweaks"

if grep -q "${MARKER}" "${BASHRC}" 2>/dev/null; then
  log_ok "~/.bashrc déjà patché (marqueur trouvé) — skip"
elif $DRY_RUN; then
  log_dry "Backup + append bloc bash tweaks dans ~/.bashrc"
else
  cp "${BASHRC}" "${BASHRC}.bak-$(date +%Y%m%d-%H%M%S)"
  log_info "Backup : ${BASHRC}.bak-*"

  cat >> "${BASHRC}" << 'BASHRC_BLOCK'

# ── mint bash tweaks ──────────────────────────────────────────────────────────
# Source : tonybeyond/ubuntu2404 (adapté Mint, bash only — pas de zsh)

# ble.sh — autosuggestions + syntax highlighting (→ ou End pour accepter)
[[ $- == *i* ]] && [[ -f ~/.local/share/blesh/ble.sh ]] \
  && source ~/.local/share/blesh/ble.sh --noattach

# Starship prompt
command -v starship &>/dev/null && eval "$(starship init bash)"

# fzf — Ctrl+R historique, Ctrl+T fichiers, Alt+C dossiers
# Noble livre fzf < 0.48 (pas de `fzf --bash`) → fallback fichiers du paquet
if command -v fzf &>/dev/null; then
  if fzf --bash &>/dev/null; then
    eval "$(fzf --bash)"
  else
    [[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]] \
      && source /usr/share/doc/fzf/examples/key-bindings.bash
    [[ -f /usr/share/doc/fzf/examples/completion.bash ]] \
      && source /usr/share/doc/fzf/examples/completion.bash
  fi
fi
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --info=inline'

# Historique étendu
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"

# bash-completion
[[ -f /usr/share/bash-completion/bash_completion ]] \
  && source /usr/share/bash-completion/bash_completion

# ls → eza (icônes + couleurs + tri dossiers)
if command -v eza &>/dev/null; then
  alias ls='eza -al --color=always --group-directories-first --icons'
  alias la='eza -a  --color=always --group-directories-first --icons'
  alias ll='eza -l  --color=always --group-directories-first --icons'
  alias lt='eza -aT --color=always --group-directories-first --icons'
  # Override de l'alias stock Mint `l='ls -CF'` : sinon il chaîne dans
  # l'alias eza ci-dessus → `eza ... -CF` → "Unknown argument -C"
  alias l='eza --color=always --group-directories-first --icons'
fi

# apt
alias upall='sudo apt upgrade -y'
alias upcheck='sudo apt update'
alias cleanup='sudo apt autoremove --purge'

# Colorisation
alias grep='grep --color=auto'
alias ip='ip --color=auto'
alias diff='diff --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# Ops sécurisées
alias mkdir='mkdir -pv'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# Attacher ble.sh en fin de .bashrc (doit rester la DERNIÈRE ligne)
[[ ${BLE_VERSION-} ]] && ble-attach

# ── fin mint bash tweaks ──────────────────────────────────────────────────────
BASHRC_BLOCK

  log_ok "~/.bashrc patché"
fi

# =============================================================================
# 2. WAVETERM
# =============================================================================
log_section "2/4 — WaveTerm"

if command -v waveterm &>/dev/null; then
  log_ok "WaveTerm déjà présent"
else
  # Dernière release GitHub (pattern ubuntu2404/post-install.sh)
  WAVETERM_VER=$(curl -s https://api.github.com/repos/wavetermdev/waveterm/releases/latest \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))" 2>/dev/null \
    || echo "")
  if [[ -z "${WAVETERM_VER}" ]]; then
    log_error "Impossible de résoudre la version WaveTerm (API GitHub) — skip. Manuel : https://www.waveterm.dev/download"
  else
    WAVETERM_DEB="/tmp/waveterm-${WAVETERM_VER}.deb"
    WAVETERM_URL="https://github.com/wavetermdev/waveterm/releases/download/v${WAVETERM_VER}/waveterm-linux-amd64-${WAVETERM_VER}.deb"
    log_info "WaveTerm v${WAVETERM_VER} (~150 Mo)..."
    if $DRY_RUN; then
      log_dry "curl ${WAVETERM_URL} && sudo apt install ${WAVETERM_DEB}"
    elif curl -fL --connect-timeout 30 -o "${WAVETERM_DEB}" "${WAVETERM_URL}" 2>>"${LOG_FILE}"; then
      sudo apt-get install -y "${WAVETERM_DEB}" 2>>"${LOG_FILE}" \
        && log_ok "WaveTerm v${WAVETERM_VER} installé" \
        || log_error "dpkg WaveTerm échoué"
      rm -f "${WAVETERM_DEB}"
    else
      log_error "Téléchargement WaveTerm échoué"
    fi
  fi
fi

# Déploiement des configs (source : tonybeyond/debiantrixie/configs/waveterm)
# Emplacement vérifié : WaveTerm lit ~/.config/waveterm/ sur Linux (wavedir par défaut)
WAVETERM_CONF="${HOME}/.config/waveterm"
CONF_SRC="${SCRIPT_DIR}/configs/waveterm"

if [[ ! -d "${CONF_SRC}" ]]; then
  # Fallback : récupérer directement depuis le dépôt debiantrixie
  log_info "configs/waveterm absent localement — téléchargement depuis debiantrixie..."
  CONF_SRC="/tmp/waveterm-configs"
  run mkdir -p "${CONF_SRC}"
  for f in settings.json connections.json waveai.json; do
    if $DRY_RUN; then
      log_dry "curl raw.githubusercontent.com/tonybeyond/debiantrixie/main/configs/waveterm/${f}"
    else
      curl -fsSL -o "${CONF_SRC}/${f}" \
        "https://raw.githubusercontent.com/tonybeyond/debiantrixie/main/configs/waveterm/${f}" \
        || log_error "Download ${f} échoué"
    fi
  done
fi

run mkdir -p "${WAVETERM_CONF}"
DEPLOYED=0
for f in "${CONF_SRC}"/*.json; do
  [[ -e "$f" ]] || continue
  base=$(basename "$f")
  if [[ -f "${WAVETERM_CONF}/${base}" ]]; then
    log_ok "${base} déjà présent — non écrasé (backup manuel si besoin)"
  else
    run cp "$f" "${WAVETERM_CONF}/${base}" && ((DEPLOYED++)) || true
  fi
done

# Validation post-copie (exigence : vérifier que les fichiers existent)
if ! $DRY_RUN; then
  MISSING=()
  for f in settings.json connections.json waveai.json; do
    [[ -f "${WAVETERM_CONF}/${f}" ]] || MISSING+=("$f")
  done
  if [[ ${#MISSING[@]} -eq 0 ]]; then
    log_ok "Configs WaveTerm validées dans ${WAVETERM_CONF} (${DEPLOYED} déployée(s))"
  else
    log_error "Configs WaveTerm manquantes : ${MISSING[*]}"
  fi
fi

# =============================================================================
# 3. NETBIRD
# =============================================================================
log_section "3/4 — NetBird"

if command -v netbird &>/dev/null; then
  log_ok "NetBird déjà présent ($(netbird version 2>/dev/null || echo '?'))"
else
  # Dépôt apt officiel NetBird (https://docs.netbird.io/how-to/installation)
  if $DRY_RUN; then
    log_dry "Ajout keyring + dépôt apt pkgs.netbird.io, apt install netbird netbird-ui"
  else
    curl -fsSL https://pkgs.netbird.io/debian/public.key \
      | sudo gpg --dearmor --yes -o /usr/share/keyrings/netbird-archive-keyring.gpg \
      && echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' \
      | sudo tee /etc/apt/sources.list.d/netbird.list >/dev/null \
      && sudo apt-get update -q \
      && sudo apt-get install -y netbird netbird-ui \
      && log_ok "NetBird installé (CLI + UI)" \
      || log_error "Installation NetBird échouée"
  fi
fi

# Service systemd — le paquet installe et active netbird.service ; vérification
if ! $DRY_RUN && command -v netbird &>/dev/null; then
  if systemctl is-enabled netbird &>/dev/null; then
    log_ok "Service netbird enabled"
  else
    sudo systemctl enable --now netbird \
      && log_ok "Service netbird activé" \
      || log_error "Activation service netbird échouée"
  fi
  log_info "Authentification à faire manuellement : netbird up --management-url <URL> (aucune credential dans ce script)"
fi

# =============================================================================
# 4. RÉCAPITULATIF
# =============================================================================
log_section "4/4 — Récapitulatif"
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  config-mint terminé — ${ERROR_COUNT} erreur(s)                     "
echo "╠══════════════════════════════════════════════════════╣"
echo "║  • source ~/.bashrc (ou nouveau terminal)            ║"
echo "║  • Police terminal → Hack Nerd Font Mono             ║"
echo "║  • WaveTerm : configs dans ~/.config/waveterm/       ║"
echo "║  • NetBird : netbird up (auth interactive)           ║"
echo "║  • Log : ${LOG_FILE}"
echo "╚══════════════════════════════════════════════════════╝"

[[ ${ERROR_COUNT} -eq 0 ]] || exit 1
