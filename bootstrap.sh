#!/usr/bin/env bash
# bootstrap.sh -- provision a fresh Debian box into a headless CC/Codex dev env.
#
# Idempotent + parameterized. Run as root on a fresh box:
#   curl -fsSL https://raw.githubusercontent.com/TKasperczyk/dots/main/bootstrap.sh -o /tmp/b.sh
#   GH_TOKEN=$(gh auth token) bash /tmp/b.sh --user quant --wayvnc-bind 127.0.0.1
#
# Re-run any time (idempotent). Run as the target user to redo just the user phase.
#
# What it does NOT do (per-host / out-of-band, by design):
#   - create the server / cloud firewall (do that via the Hetzner API or Terraform)
#   - the WireGuard SERVER side on Hytta + ivory allow rule (it prints the commands)
#   - interactive CC / Codex auth (gh is handled if GH_TOKEN is provided)
#   - ~/.claude/CLAUDE.local.md (per-host context stays local)
set -euo pipefail

# ---- defaults -------------------------------------------------------------
DOTS_REPO="https://github.com/TKasperczyk/dots"
USER_NAME="quant"
WITH_GUI=1                       # headless sway + foot + wayvnc + fonts
WAYVNC_BIND="127.0.0.1"          # 127.0.0.1 (public box, SSH-tunnel) or 0.0.0.0 (LAN)
WITH_WG=0
WG_ADDRESS=""                    # e.g. 10.0.6.21  (required with --with-wg)
WG_ENDPOINT="hytta.tomaszkasperczyk.name:51821"
WG_SERVER_PUBKEY="D0AxqgmsdEboCxNjKkuhLcQ0L6eCCY57syW+CP2S3mc="
WG_ALLOWED_IPS="10.0.6.0/24,10.11.12.0/24"

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)         USER_NAME="$2"; shift 2;;
    --dots-repo)    DOTS_REPO="$2"; shift 2;;
    --no-gui)       WITH_GUI=0; shift;;
    --wayvnc-bind)  WAYVNC_BIND="$2"; shift 2;;
    --with-wg)      WITH_WG=1; shift;;
    --wg-address)   WG_ADDRESS="$2"; WITH_WG=1; shift 2;;
    --wg-endpoint)  WG_ENDPOINT="$2"; shift 2;;
    -h|--help)      usage; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

log() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

# ---- user phase (runs as $USER_NAME) --------------------------------------
install_font() {  # SauceCodePro Nerd Font, user-local (no sudo)
  fc-list 2>/dev/null | grep -qi "SauceCodePro Nerd Font Mono" && { echo "  font present"; return; }
  local d="$HOME/.local/share/fonts" t; mkdir -p "$d"; t=$(mktemp -d)
  curl -fsSL -o "$t/f.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/SourceCodePro.zip
  unzip -oq "$t/f.zip" -d "$d" 'SauceCodeProNerdFontMono-*' || unzip -oq "$t/f.zip" -d "$d"
  rm -rf "$t"; fc-cache -f >/dev/null 2>&1; echo "  font installed"
}

setup_wayvnc_local() {  # machine-local wayvnc unit + config (NOT symlinked -- bind differs per host)
  mkdir -p "$HOME/.config/wayvnc"
  cat > "$HOME/.config/wayvnc/config" <<EOF
use_relative_paths=false
address=$WAYVNC_BIND
enable_auth=false
EOF
  cat > "$HOME/.config/systemd/user/wayvnc-headless.service" <<EOF
[Unit]
Description=wayvnc on $WAYVNC_BIND:5901 attached to $USER_NAME headless Sway
After=sway-headless.service
Requires=sway-headless.service
BindsTo=sway-headless.service
PartOf=sway-headless.service

[Service]
Type=simple
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u)
Environment=WAYLAND_DISPLAY=wayland-1
ExecStartPre=/bin/sh -c 'i=0; until [ -S "\$XDG_RUNTIME_DIR/\$WAYLAND_DISPLAY" ] || [ \$i -ge 30 ]; do sleep 0.5; i=\$((i+1)); done'
ExecStart=/usr/bin/wayvnc -k pl $WAYVNC_BIND 5901
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF
}

user_phase() {
  local REPO="$HOME/Programming/dots"
  log "clone dots"
  [[ -d "$REPO/.git" ]] || git clone -q "$DOTS_REPO" "$REPO"
  git -C "$REPO" pull --ff-only -q 2>/dev/null || true

  log "zsh plugins (user-local, portable)"
  bash "$REPO/.local/bin/zsh-plugins-setup"

  log "symlinks"
  mkdir -p "$HOME/.config/systemd/user" "$HOME/.claude" "$HOME/.codex" "$HOME/.local/bin"
  ln -sfn "$REPO/.zshrc"                          "$HOME/.zshrc"
  ln -sfn "$REPO/.p10k.zsh"                        "$HOME/.p10k.zsh"
  ln -sfn "$REPO/.config/nvim"                     "$HOME/.config/nvim"
  ln -sfn "$REPO/.local/bin/zsh-plugins-setup"     "$HOME/.local/bin/zsh-plugins-setup"
  ln -sfn "$REPO/.claude/CLAUDE.md"                "$HOME/.claude/CLAUDE.md"
  ln -sfn "$REPO/.codex/AGENTS.md"                 "$HOME/.codex/AGENTS.md"
  if [[ "$WITH_GUI" -eq 1 ]]; then
    ln -sfn "$REPO/.config/sway"                                   "$HOME/.config/sway"
    ln -sfn "$REPO/.config/foot"                                   "$HOME/.config/foot"
    ln -sfn "$REPO/.config/systemd/user/sway-headless.service"     "$HOME/.config/systemd/user/sway-headless.service"
  fi

  if [[ "$WITH_GUI" -eq 1 ]]; then
    log "fonts"; install_font
    log "machine-local wayvnc ($WAYVNC_BIND)"; setup_wayvnc_local
  fi

  log "gh auth"
  if [[ -n "${GH_TOKEN:-}" ]]; then
    gh auth login --with-token <<<"$GH_TOKEN" && gh auth setup-git && echo "  gh authed"
  else
    echo "  no GH_TOKEN -- run 'gh auth login' later"
  fi

  if [[ "$WITH_GUI" -eq 1 ]]; then
    log "enable headless services"
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    systemctl --user daemon-reload
    systemctl --user enable --now sway-headless.service wayvnc-headless.service
  fi

  log "claude code"
  curl -fsSL https://claude.ai/install.sh | bash
  log "codex"
  sudo npm install -g @openai/codex >/dev/null && echo "  codex installed"

  log "nvim plugins (best-effort)"
  timeout 200 nvim --headless "+Lazy! install" +qa >/dev/null 2>&1 || echo "  (partial -- finishes on first launch)"
}

# ---- WireGuard (root; client only -- server side is manual) ---------------
setup_wg_root() {
  if [[ -z "$WG_ADDRESS" ]]; then echo "  --with-wg needs --wg-address; skipping"; return; fi
  umask 077; mkdir -p /etc/wireguard
  [[ -f /etc/wireguard/wg-home.key ]] || wg genkey > /etc/wireguard/wg-home.key
  local priv pub; priv=$(cat /etc/wireguard/wg-home.key); pub=$(wg pubkey < /etc/wireguard/wg-home.key)
  cat > /etc/wireguard/wg-home.conf <<EOF
[Interface]
Address = $WG_ADDRESS/32
PrivateKey = $priv
MTU = 1280

[Peer]
PublicKey = $WG_SERVER_PUBKEY
Endpoint = $WG_ENDPOINT
AllowedIPs = $WG_ALLOWED_IPS
PersistentKeepalive = 25
EOF
  chmod 600 /etc/wireguard/wg-home.conf
  systemctl enable --now wg-quick@wg-home || true
  cat <<EOF

  >>> WireGuard client up at $WG_ADDRESS -- won't handshake until you add it on Hytta:
        ssh hytta@10.0.6.1 "sudo wg set wg-home peer $pub allowed-ips $WG_ADDRESS/32"
      then persist the [Peer] block in /etc/wireguard/home-vpn/wg-home.conf, add any
      containment FORWARD rules, and (if the box needs LMS) the ivory INPUT allow.
EOF
}

# ---- root phase -----------------------------------------------------------
root_phase() {
  export DEBIAN_FRONTEND=noninteractive
  log "apt: base tooling"
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates gnupg git >/dev/null

  if [[ ! -f /etc/apt/sources.list.d/github-cli.list ]]; then
    log "apt: GitHub CLI repo"
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list
    apt-get update -qq
  fi

  log "apt: packages"
  local pkgs="zsh neovim ripgrep fd-find unzip jq build-essential nodejs npm eza zoxide fontconfig dbus-user-session gh wireguard-tools"
  [[ "$WITH_GUI" -eq 1 ]] && pkgs+=" sway foot wayvnc bemenu wl-clipboard grim slurp"
  apt-get install -y -qq $pkgs >/dev/null

  log "user: $USER_NAME"
  id "$USER_NAME" &>/dev/null || useradd -m -u 1000 -s /usr/bin/zsh "$USER_NAME"
  usermod -aG sudo "$USER_NAME"
  echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER_NAME"
  chmod 0440 "/etc/sudoers.d/$USER_NAME"
  if [[ -f /root/.ssh/authorized_keys ]]; then
    install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "/home/$USER_NAME/.ssh"
    install -m 600 -o "$USER_NAME" -g "$USER_NAME" /root/.ssh/authorized_keys "/home/$USER_NAME/.ssh/authorized_keys"
  fi
  loginctl enable-linger "$USER_NAME"

  [[ "$WITH_WG" -eq 1 ]] && { log "wireguard client"; setup_wg_root; }

  log "hand off to user phase as $USER_NAME"
  sudo --preserve-env=GH_TOKEN -H -u "$USER_NAME" bash -c "
    set -euo pipefail
    $(declare -f log install_font setup_wayvnc_local user_phase)
    DOTS_REPO='$DOTS_REPO' USER_NAME='$USER_NAME' WITH_GUI='$WITH_GUI' WAYVNC_BIND='$WAYVNC_BIND' user_phase
  "
  log "done -- box provisioned"
}

# ---- entry ----------------------------------------------------------------
if [[ "$EUID" -eq 0 ]]; then root_phase; else user_phase; fi
