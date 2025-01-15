plug "zsh-users/zsh-autosuggestions"
plug "zsh-users/zsh-completions"
plug "zap-zsh/supercharge"
plug "zap-zsh/exa"
plug "wintermi/zsh-rust"
plug "hlissner/zsh-autopair"
plug "wintermi/zsh-brew"
plug "chivalryq/git-alias"
plug "zap-zsh/completions"
plug "zap-zsh/fzf"
plug "greymd/docker-zsh-completion"
plug "lukechilds/zsh-better-npm-completion"
plug "ptavares/zsh-direnv"

export VI_MODE_ESC_INSERT="jj" && plug "zap-zsh/vim"

export NVM_COMPLETION=true && \
  export NVM_NO_USE=true && \
  export NVM_AUTO_USE=true && \
  plug "lukechilds/zsh-nvm"

if command -v nx &> /dev/null; then
  plug "jscutlery/nx-completion"
fi

# Theme
plug "romkatv/powerlevel10k"

[[ -f "${0:A:h}/plugins.local.zsh" ]] && source "${0:A:h}/plugins.local.zsh"

_load_local_plugins() {
  setopt NULL_GLOB

  for plugin (${ZSH_CONFIG_PATH}/plugins/*.zsh) plug "$plugin"

  unsetopt NULL_GLOB
}

_load_local_plugins

# Syntax highlighting
plug "zsh-users/zsh-syntax-highlighting"

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
