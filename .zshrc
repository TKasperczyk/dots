###############################################################################
#  Powerlevel10k instant prompt (must stay at the very top)                   #
###############################################################################
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

###############################################################################
#  Socket cleanup (local-bus)                                                  #
###############################################################################
SOCKET="/tmp/local-bus-$(whoami)-22"
if [ -S "$SOCKET" ] && ! lsof "$SOCKET" >/dev/null 2>&1; then
  rm -f "$SOCKET"
fi

###############################################################################
#  Basic environment                                                           #
###############################################################################
export PATH="$HOME/.local/bin:$PATH"
export EDITOR="nvim"
export TERM="xterm-256color"

###############################################################################
#  Aliases                                                                     #
###############################################################################
alias ls='eza --icons=always --classify'
alias vim='nvim'

###############################################################################
#  Oh-My-Zsh & plugins                                                         #
###############################################################################
source /usr/share/oh-my-zsh/oh-my-zsh.sh
source /usr/share/oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

###############################################################################
#  Edit command in nvim with Ctrl+e                                            #
###############################################################################
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^e' edit-command-line

###############################################################################
#  zsh-vi-mode + history substring search                                     #
###############################################################################
function zvm_after_init() {
  # History prefix search (type partial cmd → Esc → k/j to filter)
  source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
  HISTORY_SUBSTRING_SEARCH_PREFIXED=1
  # Wrap history search to clear autosuggestion ghost text first.
  # history-substring-search loads after zsh-autosuggestions, so its widgets
  # never get wrapped — stale POSTDISPLAY bleeds into the displayed buffer.
  function _hist_substr_up_no_ghost() { POSTDISPLAY=; zle history-substring-search-up; }
  function _hist_substr_down_no_ghost() { POSTDISPLAY=; zle history-substring-search-down; }
  zle -N _hist_substr_up_no_ghost
  zle -N _hist_substr_down_no_ghost
  bindkey -M vicmd 'k' _hist_substr_up_no_ghost
  bindkey -M vicmd 'j' _hist_substr_down_no_ghost

  # Clipboard-aware yank
  function zvm_vi_yank() {
    zle vi-yank
    if [[ -n "$SSH_TTY" || -n "$SSH_CLIENT" || -n "$SSH_CONNECTION" ]]; then
      printf '\033]52;c;%s\a' "$(printf '%s' "$CUTBUFFER" | base64 -w0)"
    else
      printf '%s' "$CUTBUFFER" | wl-copy 2>/dev/null
    fi
  }
  zle -N zvm_vi_yank
  bindkey -M vicmd 'y' zvm_vi_yank
  bindkey -M visual 'y' zvm_vi_yank

  # Re-bind Ctrl+E for edit-command-line (vi-mode overrides it)
  bindkey '^e' edit-command-line
}
source /usr/share/zsh/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh

###############################################################################
#  Prompt (Powerlevel10k)                                                      #
###############################################################################
source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh   # run `p10k configure` to edit

# Host-specific p10k overrides
case "${HOST:-$(cat /etc/hostname 2>/dev/null)}" in
  p4-workstation)
    # Work VM: orange/yellow theme with λ icon
    typeset -g POWERLEVEL9K_OS_ICON_CONTENT_EXPANSION='λ'
    typeset -g POWERLEVEL9K_OS_ICON_FOREGROUND=208  # orange
    typeset -g POWERLEVEL9K_DIR_FOREGROUND=220  # yellow
    ;;
esac

###############################################################################
#  History                                                                     #
###############################################################################
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000000
SAVEHIST=100000000

setopt BANG_HIST \
       EXTENDED_HISTORY \
       INC_APPEND_HISTORY \
       SHARE_HISTORY \
       HIST_EXPIRE_DUPS_FIRST \
       HIST_IGNORE_DUPS \
       HIST_IGNORE_ALL_DUPS \
       HIST_FIND_NO_DUPS \
       HIST_IGNORE_SPACE \
       HIST_SAVE_NO_DUPS \
       HIST_REDUCE_BLANKS \
       HIST_VERIFY \
       HIST_BEEP

###############################################################################
#  zoxide                                                                      #
###############################################################################
if [[ $- == *i* ]]; then
  eval "$(zoxide init --cmd cd zsh)"
fi

###############################################################################
#  Tool integrations                                                           #
###############################################################################
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"

export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

export PATH="$PATH:$HOME/.lmstudio/bin"

###############################################################################
#  Host-local overrides                                                        #
###############################################################################
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# pnpm
export PNPM_HOME="/home/luthriel/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
