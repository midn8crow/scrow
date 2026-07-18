# =============================================================================
# ~/.zshrc - itsme Style Zsh Configuration
# =============================================================================

[[ -o interactive ]] || return

# -----------------------------------------------------------------------------
# ENVIRONMENT
# -----------------------------------------------------------------------------
export TERMINAL='kitty'
export EDITOR='nvim'
export VISUAL='nvim'
export MAKEFLAGS="-j$(nproc)"

# -----------------------------------------------------------------------------
# HISTORY
# -----------------------------------------------------------------------------
HISTSIZE=50000
SAVEHIST=25000
HISTFILE="$HOME/.zsh_history"

setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY

# -----------------------------------------------------------------------------
# AUTOCOMPLETE ENGINE
# -----------------------------------------------------------------------------
setopt EXTENDED_GLOB

if [[ -z "$LS_COLORS" ]] && command -v dircolors >/dev/null; then
  eval "$(dircolors -b)"
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*:descriptions' format '%B%F{yellow}%d%f%b'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'

local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
[[ -d "$cache_dir" ]] || mkdir -p "$cache_dir"
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$cache_dir/zcompcache"

autoload -Uz compinit
local zcompdump="${ZDOTDIR:-$HOME}/.zcompdump"
local dump_cache=($zcompdump(#qN.mh-24))

if (( ${#dump_cache} )); then
  compinit -C
else
  compinit
  touch "$zcompdump"
fi
unset cache_dir zcompdump dump_cache

# -----------------------------------------------------------------------------
# KEYBINDINGS & OPTIONS
# -----------------------------------------------------------------------------
setopt INTERACTIVE_COMMENTS
setopt GLOB_DOTS
setopt NO_CASE_GLOB
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS

bindkey -v
KEYTIMEOUT=1

autoload -U edit-command-line
zle -N edit-command-line
bindkey -M vicmd v edit-command-line

autoload -U history-search-end
zle -N history-beginning-search-backward-end history-search-end
zle -N history-beginning-search-forward-end history-search-end

for keymap in viins vicmd; do
  bindkey -M "$keymap" "${terminfo[kcuu1]:-^[[A}" history-beginning-search-backward-end
  bindkey -M "$keymap" "^[[A" history-beginning-search-backward-end
  bindkey -M "$keymap" "${terminfo[kcud1]:-^[[B}" history-beginning-search-forward-end
  bindkey -M "$keymap" "^[[B" history-beginning-search-forward-end
done

# Right arrow accepts autosuggestion
bindkey "^[[C" forward-word
bindkey "^[OC" forward-word

# -----------------------------------------------------------------------------
# ALIASES
# -----------------------------------------------------------------------------
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -I'
alias ln='ln -v'
alias sexman='sudo pacman'
alias fuck='paru'
alias s='paru -Ss'
alias df='df -hT'
alias diff='delta --side-by-side'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

if command -v eza >/dev/null; then
    alias ls='eza --icons --group-directories-first'
    alias ll='eza --icons --group-directories-first -l --git'
    alias la='eza --icons --group-directories-first -la --git'
    alias lt='eza --icons --group-directories-first --tree --level=2'
else
    alias ls='ls --color=auto'
    alias ll='ls -lh'
    alias la='ls -A'
fi

function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}

mkcd() {
  mkdir -p "$1" && cd "$1"
}

# -----------------------------------------------------------------------------
# PROMPT (Starship)
# -----------------------------------------------------------------------------
_starship_cache="$HOME/.starship-init.zsh"
_starship_bin="$(command -v starship)"
if [[ -n "$_starship_bin" ]]; then
  if [[ ! -f "$_starship_cache" || "$_starship_bin" -nt "$_starship_cache" ]]; then
    "$_starship_bin" init zsh --print-full-init >! "$_starship_cache"
  fi
  source "$_starship_cache"
fi

# fzf
_fzf_cache="$HOME/.fzf-init.zsh"
_fzf_bin="$(command -v fzf)"
if [[ -n "$_fzf_bin" ]]; then
  if "$_fzf_bin" --zsh >/dev/null 2>&1; then
    if [[ ! -f "$_fzf_cache" || "$_fzf_bin" -nt "$_fzf_cache" ]]; then
      "$_fzf_bin" --zsh >! "$_fzf_cache"
    fi
    source "$_fzf_cache"
  elif [[ -f "$HOME/.fzf.zsh" ]]; then
    source "$HOME/.fzf.zsh"
  fi
fi

# zoxide
_zoxide_cache="$HOME/.zoxide-init.zsh"
_zoxide_bin="$(command -v zoxide)"
if [[ -n "$_zoxide_bin" ]]; then
  if [[ ! -f "$_zoxide_cache" || "$_zoxide_bin" -nt "$_zoxide_cache" ]]; then
    "$_zoxide_bin" init zsh >! "$_zoxide_cache"
  fi
  source "$_zoxide_cache"
fi
if command -v zoxide >/dev/null; then
    alias cd='z'
fi

unset _starship_cache _starship_bin _fzf_cache _fzf_bin _zoxide_cache _zoxide_bin

# -----------------------------------------------------------------------------
# PLUGINS
# -----------------------------------------------------------------------------
# Autosuggestions (right arrow to accept)
if [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=60'
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# Syntax Highlighting (MUST be last)
if [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

alias sklauncher="~/application/jdk25/bin/java -jar ~/application/sklauncher/SKlauncher-3.2.18.jar"
