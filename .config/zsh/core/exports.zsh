if command -v nvim &> /dev/null; then
  export EDITOR="nvim"
fi

if command -v bat &> /dev/null; then
  export PAGER="bat"
fi
