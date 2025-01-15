[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"

export ZSH_CONFIG_PATH="${0:a:h}"

plug "${ZSH_CONFIG_PATH}/core/plugins.zsh"
plug "${ZSH_CONFIG_PATH}/core/exports.zsh"
plug "${ZSH_CONFIG_PATH}/core/aliases.zsh"

test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# Load and initialise completion system
autoload -Uz compinit
compinit
