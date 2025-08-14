###############################################################################
#  Socket cleanup (local-bus)                                                  #
###############################################################################
SOCKET="/tmp/local-bus-$(whoami)-22"
if [ -S "$SOCKET" ] && ! lsof "$SOCKET" >/dev/null 2>&1; then
  rm -f "$SOCKET"
fi

###############################################################################
#  Powerlevel10k instant prompt (must stay near the very top)                 #
###############################################################################
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

###############################################################################
#  Basic environment                                                           #
###############################################################################
export PATH="$HOME/.local/bin:$PATH"
export EDITOR="vim"
export TERM="xterm-256color"

###############################################################################
#  Aliases                                                                     #
###############################################################################
alias ls='eza --icons=always --classify'
alias ainulindale='TERM=xterm-kitty kitty +kitten ssh 10.0.5.10'
alias vim='nvim'

###############################################################################
#  Oh-My-Zsh & plugins                                                         #
###############################################################################
source /usr/share/oh-my-zsh/oh-my-zsh.sh
source /usr/share/oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/oh-my-zsh/lib/key-bindings.zsh
source /usr/share/oh-my-zsh/plugins/vi-mode/vi-mode.plugin.zsh

###############################################################################
#  Prompt (Powerlevel10k)                                                      #
###############################################################################
source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh   # run `p10k configure` to edit

###############################################################################
#  History                                                                     #
###############################################################################
HISTFILE="$HOME/.zsh_history"
HISTSIZE=100000000
HISTFILESIZE=20000000
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

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

###############################################################################
#  zoxide                                                                      #
###############################################################################
eval "$(zoxide init --cmd cd zsh)"

###############################################################################
#  GitHub Copilot CLI                                                          #
###############################################################################
eval "$(gh copilot alias -- zsh)"

###############################################################################
#  nvm bash-completion                                                         #
###############################################################################
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"


# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
export PNPM_HOME="/home/luthriel/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
