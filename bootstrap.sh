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
#   - the WireGuard SERVER side (peer registration + firewall) -- it prints the pubkey
#   - interactive CC / Codex auth (gh is handled if GH_TOKEN is provided)
#   - ~/.claude/CLAUDE.local.md (per-host context stays local)
#
# Optional add-ons (off by default): --with-codex-swarm, and --with-memory
# --memory-embedding-url <url>. claude-memory only FUNCTIONS if the box can reach
# that URL -- for a VPS that means WG up + a server-side allow to the embed host.
set -euo pipefail

# ---- defaults -------------------------------------------------------------
DOTS_REPO="https://github.com/TKasperczyk/dots"
USER_NAME="quant"
WITH_GUI=1                       # headless sway + foot + wayvnc + fonts
WAYVNC_BIND="127.0.0.1"          # 127.0.0.1 (public box, SSH-tunnel) or 0.0.0.0 (LAN)
WITH_WG=0
WG_ADDRESS=""                    # this peer's VPN address, e.g. 10.10.0.5 (required with --with-wg)
WG_ENDPOINT=""                   # host:port of your WG server (required with --with-wg)
WG_SERVER_PUBKEY=""              # your WG server's public key (required with --with-wg)
WG_ALLOWED_IPS=""                # e.g. 10.0.0.0/24 (required with --with-wg)
WITH_MEMORY=0
MEMORY_EMBEDDING_URL=""          # e.g. http://embed-host:1234/v1 (required with --with-memory)
WITH_CODEX_SWARM=0

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)         USER_NAME="$2"; shift 2;;
    --dots-repo)    DOTS_REPO="$2"; shift 2;;
    --no-gui)       WITH_GUI=0; shift;;
    --wayvnc-bind)  WAYVNC_BIND="$2"; shift 2;;
    --with-wg)      WITH_WG=1; shift;;
    --wg-address)   WG_ADDRESS="$2"; WITH_WG=1; shift 2;;
    --wg-endpoint)      WG_ENDPOINT="$2"; shift 2;;
    --wg-server-pubkey) WG_SERVER_PUBKEY="$2"; shift 2;;
    --wg-allowed-ips)   WG_ALLOWED_IPS="$2"; shift 2;;
    --with-memory)          WITH_MEMORY=1; shift;;
    --memory-embedding-url) MEMORY_EMBEDDING_URL="$2"; WITH_MEMORY=1; shift 2;;
    --with-codex-swarm)     WITH_CODEX_SWARM=1; shift;;
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

setup_codex_swarm() {  # uv + register the codex-mcp-swarm MCP (PyPI package, run via uvx)
  [[ -x "$HOME/.local/bin/uv" ]] || curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
  local cc="$HOME/.local/bin/claude"
  "$cc" mcp remove codex-swarm -s user >/dev/null 2>&1 || true
  "$cc" mcp add codex-swarm -s user -- uvx --upgrade codex-mcp-swarm \
    -c model=gpt-5.5 -c reasoning_effort=xhigh -c approval_policy=never \
    -c sandbox_mode=danger-full-access --skip-git-repo-check
  echo "  codex-swarm registered (uv + MCP)"
}

setup_memory() {  # clone + build claude-memory; configure hooks/env/MCP (embeddings -> your server)
  [[ -z "$MEMORY_EMBEDDING_URL" ]] && { echo "  --with-memory needs --memory-embedding-url -- skipping"; return; }
  local dir="$HOME/Programming/claude-memory"
  [[ -d "$dir/.git" ]] || git clone -q https://github.com/TKasperczyk/claude-memory.git "$dir"
  ( cd "$dir" && pnpm install && pnpm exec tsc ) || { echo "  claude-memory build FAILED -- skipping config"; return; }
  local s="$HOME/.claude/settings.json" pre="node $dir/dist/hooks/pre-prompt.js" post="node $dir/dist/hooks/post-session.js"
  [[ -f "$s" ]] || echo '{}' > "$s"
  jq --arg url "$MEMORY_EMBEDDING_URL" --arg pre "$pre" --arg post "$post" '
      .autoMemoryEnabled = false
    | .env = ((.env // {}) + {CC_EMBEDDINGS_URL: $url})
    | .hooks.UserPromptSubmit = [{hooks:[{type:"command", command:$pre,  timeout:15}]}]
    | .hooks.PreCompact       = [{hooks:[{type:"command", command:$post, timeout:15}]}]
    | .hooks.SessionEnd       = [{hooks:[{type:"command", command:$post, timeout:15}]}]
  ' "$s" > "$s.tmp" && mv "$s.tmp" "$s"
  local cc="$HOME/.local/bin/claude"
  "$cc" mcp remove claude-memory -s user >/dev/null 2>&1 || true
  "$cc" mcp add claude-memory -s user -- node "$dir/dist/mcp-server.js"
  echo "  claude-memory built + configured (embeddings -> $MEMORY_EMBEDDING_URL)"
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

  [[ "$WITH_CODEX_SWARM" -eq 1 ]] && { log "codex-swarm mcp"; setup_codex_swarm; }
  [[ "$WITH_MEMORY" -eq 1 ]] && { log "claude-memory"; setup_memory; }

  log "nvim plugins (best-effort)"
  timeout 200 nvim --headless "+Lazy! install" +qa >/dev/null 2>&1 || echo "  (partial -- finishes on first launch)"
}

# ---- WireGuard (root; client only -- server side is manual) ---------------
setup_wg_root() {
  local missing=()
  [[ -z "$WG_ADDRESS" ]]       && missing+=(--wg-address)
  [[ -z "$WG_ENDPOINT" ]]      && missing+=(--wg-endpoint)
  [[ -z "$WG_SERVER_PUBKEY" ]] && missing+=(--wg-server-pubkey)
  [[ -z "$WG_ALLOWED_IPS" ]]   && missing+=(--wg-allowed-ips)
  if (( ${#missing[@]} )); then echo "  --with-wg needs: ${missing[*]} -- skipping WG"; return; fi
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

  >>> WireGuard client up at $WG_ADDRESS. It won't handshake until you register
      this peer on your WG server (with AllowedIPs $WG_ADDRESS/32):
        $pub
      Then add any per-peer firewall / containment rules on the server side.
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
  local pkgs="zsh neovim ripgrep fd-find unzip jq build-essential python3 eza zoxide fontconfig dbus-user-session gh wireguard-tools"
  [[ "$WITH_GUI" -eq 1 ]] && pkgs+=" sway foot wayvnc bemenu wl-clipboard grim slurp"
  apt-get install -y -qq $pkgs >/dev/null

  log "node.js"
  if [[ "$WITH_MEMORY" -eq 1 ]]; then   # claude-memory + pnpm need node:sqlite (Node >=22.5); Debian ships 20
    [[ -f /etc/apt/sources.list.d/nodesource.list ]] || curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
    apt-get install -y -qq nodejs >/dev/null   # NodeSource 24 (bundles npm)
    npm install -g pnpm >/dev/null 2>&1 || true
  else
    apt-get install -y -qq nodejs npm >/dev/null   # Debian Node 20 (fine without claude-memory)
  fi

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
    $(declare -f log install_font setup_wayvnc_local setup_codex_swarm setup_memory user_phase)
    DOTS_REPO='$DOTS_REPO' USER_NAME='$USER_NAME' WITH_GUI='$WITH_GUI' WAYVNC_BIND='$WAYVNC_BIND' WITH_MEMORY='$WITH_MEMORY' MEMORY_EMBEDDING_URL='$MEMORY_EMBEDDING_URL' WITH_CODEX_SWARM='$WITH_CODEX_SWARM' user_phase
  "
  log "done -- box provisioned"
}

# ---- entry ----------------------------------------------------------------
if [[ "$EUID" -eq 0 ]]; then root_phase; else user_phase; fi
