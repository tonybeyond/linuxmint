# mint/ — Scripts Linux Mint 22.x

Adaptation des configurations du dépôt [ubuntu2404](https://github.com/tonybeyond/ubuntu2404) pour **Linux Mint 22.x** (base Ubuntu 24.04 Noble), éditions **Cinnamon** et **XFCE**.

Différences volontaires vs Ubuntu :
- **Bash only** — pas de zsh/Oh My Zsh (ble.sh + Starship à la place)
- **WaveTerm** — pas de Ghostty (configs reprises de [debiantrixie](https://github.com/tonybeyond/debiantrixie/tree/main/configs))
- **NetBird** inclus
- Bloat Mint spécifique (hypnotix, mintwelcome…) au lieu du bloat GNOME

---

## Structure

```
mint/
├── config-mint.sh          # Bash (ble.sh/Starship/Nerd Font) · WaveTerm · NetBird
├── optimize-mint.sh        # Tuning système · nettoyage · applications
├── configs/
│   └── waveterm/           # settings.json · connections.json · waveai.json
│                           # (source : debiantrixie/configs/waveterm)
├── i3/
│   ├── install-i3.sh       # i3 + polybar + picom + rofi + dunst (style DTOS)
│   ├── config              # config i3 (Doom One, clavier ch-fr)
│   ├── polybar/            # config.ini · launch.sh · i3-layout.py
│   ├── picom/  rofi/  dunst/
└── README.md
```

---

## Usage

### 1. config-mint.sh — utilisateur normal, PAS root

```bash
# Aperçu sans modification
bash mint/config-mint.sh --dry-run

# Exécution réelle (sudo demandé au besoin)
bash mint/config-mint.sh
```

Installe et configure :

| Composant | Détail |
|-----------|--------|
| ble.sh | Autosuggestions + syntax highlighting bash → `~/.local/share/blesh` |
| Starship | Prompt 2 lignes (config identique ubuntu2404, symbole Mint) |
| Hack Nerd Font | `~/.local/share/fonts/HackNerdFont` |
| ~/.bashrc | Aliases eza/git/apt, fzf, historique étendu — **backup automatique**, idempotent (marqueur) |
| WaveTerm | Dernière release GitHub (.deb) + configs → `~/.config/waveterm/` avec **validation post-copie** |
| NetBird | Dépôt apt officiel (`pkgs.netbird.io`) + service systemd — **aucune credential**, auth manuelle via `netbird up` |

Post-exécution :
```bash
source ~/.bashrc
# Terminal → police "Hack Nerd Font Mono"
netbird up          # authentification interactive (ou --management-url pour self-hosted)
```

### 2. optimize-mint.sh — root

```bash
sudo bash mint/optimize-mint.sh --dry-run     # aperçu
sudo bash mint/optimize-mint.sh               # exécution
sudo bash mint/optimize-mint.sh --dns-cache   # + cache DNS systemd-resolved (opt-in)
```

#### Optimisations appliquées (toutes documentées dans le script)

| Domaine | Action | Pourquoi |
|---------|--------|----------|
| Mémoire | `swappiness=10`, `vfs_cache_pressure=50`, dirty ratios | Desktop : RAM d'abord, moins de micro-freezes |
| Réseau | BBR + fq, TCP Fast Open, buffers 16 Mo, MTU probing | Débit/latence sur WiFi/VPN (NetBird), liens ≥ 1 Gbps |
| inotify | Watches 524288 | IDE (Zed), sync, conteneurs |
| SSD | `fstrim.timer` activé | Maintien des perfs SSD dans le temps |
| I/O | udev : `none` (NVMe) / `mq-deadline` (SSD) / `bfq` (HDD) | Scheduler adapté par type de disque |
| Thermique | thermald **si CPU Intel** | Évite le throttling brutal |
| RAM | preload **si ≥ 8 Go** | Lancements d'apps plus rapides |
| Boot | `NetworkManager-wait-online` désactivé | Gain 5–15 s au boot, inutile en desktop |
| CPU governor | **Aucun override** (choix documenté) | intel_pstate/amd-pstate gèrent déjà dynamiquement sur Noble |
| DNS | systemd-resolved **uniquement avec `--dns-cache`** | Opt-in : peut interférer avec split-DNS NetBird |

#### Supprimé (justifié dans le script)

`hypnotix` (IPTV), `rhythmbox`, `thunderbird` (→ Betterbird), jeux GNOME, `mintwelcome`

**Jamais supprimé** : LibreOffice (mis à jour), Flatpak, warpinator, celluloid, timeshift. Le script **vérifie** LibreOffice et Flatpak après nettoyage et lève une erreur s'ils manquent.

#### Applications installées

| App | Méthode |
|-----|---------|
| Rnote, Flatseal, Zed, Blanket, Shortwave | Flatpak (Flathub) |
| Brave Origin | Repo apt officiel Brave (fallback `brave-browser`) |
| Betterbird | Script officiel du projet → `/opt/betterbird` + client mail par défaut (`xdg-settings`) |

> **Note Betterbird** : il n'existe **pas de PPA officiel**. Méthodes officielles : script d'installation du projet (utilisé ici, gère aussi les mises à jour en le relançant) ou Flatpak `eu.betterbird.Betterbird`. Le script bascule sur un message d'erreur avec l'alternative Flatpak en cas d'échec.


### 3. install-i3.sh — session i3 style DTOS (optionnel)

```bash
bash mint/i3/install-i3.sh --dry-run    # aperçu
bash mint/i3/install-i3.sh              # exécution (utilisateur normal, sudo au besoin)
```

Installe i3 (gaps natifs ≥ 4.22), Polybar, picom, rofi, dunst, nitrogen, flameshot,
xsecurelock + Mononoki Nerd Font, puis déploie les configs (backup automatique de
l'existant) et valide avec `i3 -C`. Session « i3 » disponible à l'écran de connexion.

#### Keybinds i3 (Super = touche Windows, clavier ch-fr)

Applications :

| Bind | Action |
|------|--------|
| `Super+Return` | WaveTerm (fallback Alacritty) |
| `Super+Shift+Return` | Alacritty |
| `Super+Space` | rofi (lanceur d'applications) |
| `Super+b` | Brave (brave-origin, fallback brave-browser) |
| `Super+e` | Nemo (fichiers) |

Fenêtres :

| Bind | Action |
|------|--------|
| `Super+h/j/k/l` ou `Super+←↓↑→` | Focus gauche/bas/haut/droite |
| `Super+Shift+h/j/k/l` ou `Super+Shift+←↓↑→` | Déplacer la fenêtre |
| `Super+Ctrl+h/j/k/l` | Redimensionner (largeur/hauteur ±5) |
| `Super+q` | Fermer la fenêtre |
| `Super+f` | Plein écran |
| `Super+t` | Flottant on/off |
| `Super+Tab` / `Super+Shift+Tab` | Fenêtre suivante / précédente |
| `Super` + glisser souris | Déplacer une fenêtre flottante |

Layouts :

| Bind | Action |
|------|--------|
| `Super+n` | Cycler split → tabbed → stacking |
| `Super+v` | Split vertical |
| `Super+g` | Split horizontal |

Workspaces :

| Bind | Action |
|------|--------|
| `Super+1..9` | Aller au workspace 1–9 |
| `Super+Shift+1..9` | Y envoyer la fenêtre (sans suivre) — via `bindcode`, voir note |

> **Note ch-fr** : `Super+Shift+1..9` est déclaré en `bindcode` (keycodes 10–18) et
> non en `bindsym` : sur QWERTZ suisse, `Shift+1..9` produit `+ " * ç % & / ( )` et
> un `bindsym $mod+Shift+1` ne se déclencherait jamais.

Système :

| Bind | Action |
|------|--------|
| `Super+Ctrl+r` | Recharger i3 (restart in-place) |
| `Super+Ctrl+q` | Quitter i3 (confirmation i3-nagbar) |
| `Super+Alt+l` | Verrouiller (xsecurelock) |
| `Print` | Screenshot (flameshot gui) |
| `XF86Audio↑/↓/Mute` | Volume ±5 % / muet (wpctl) |
| `XF86AudioPlay/Next/Prev` | Lecture/pause · piste (playerctl) |
| `XF86MonBrightness↑/↓` | Luminosité ±10 % (brightnessctl) |

---

## Robustesse

- **Idempotence** : chaque étape teste l'existant (marqueurs `.bashrc`, `dpkg -s`, `flatpak info`, fichiers de conf non écrasés). Relançable sans casse.
- **Logging** : horodaté, `~/.local/state/mint-setup/config-mint.log` (user) et `/var/log/mint-optimize.log` (root).
- **Échecs non critiques** : loggés, comptés, le script continue. Exit code 1 si ≥ 1 erreur.
- **Dry-run** : `--dry-run` sur les deux scripts.
- **Sécurité** : aucune credential hardcodée. NetBird : authentification laissée à l'utilisateur.
- **Rollback sysctl** : `sudo rm /etc/sysctl.d/99-mint-tuning.conf && sudo sysctl --system`
- **Rollback .bashrc** : backups `~/.bashrc.bak-YYYYMMDD-HHMMSS`

## Tests de validation

```bash
# Après config-mint.sh
bash -ic 'echo $BLE_VERSION'                       # ble.sh chargé
starship --version
ls ~/.config/waveterm/                             # 3 fichiers JSON
systemctl status netbird

# Après optimize-mint.sh + reboot
sysctl net.ipv4.tcp_congestion_control            # → bbr
cat /sys/block/nvme0n1/queue/scheduler            # → [none]
systemctl list-timers | grep fstrim               # actif
systemd-analyze                                    # boot plus court
```
