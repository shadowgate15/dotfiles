alias l="ll -a"
alias zshrc="${EDITOR} ${ZSH_CONFIG_PATH}"

if command -v bat &> /dev/null; then
  alias cat="bat"
fi

[[ -f "${0:A:h}/aliases.local.zsh" ]] && source "${0:A:h}/aliases.local.zsh"
