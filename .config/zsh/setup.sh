#!/bin/zsh

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# Download and install zap
zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1
# Copy zshrc configuration
cp -r ${SCRIPT_DIR}/zshrc ${HOME}/.zshrc
