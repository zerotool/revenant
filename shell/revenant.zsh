# shellcheck disable=all
# (zsh, which shellcheck cannot parse.) revenant shell integration, sourced from ~/.zshrc by
# `revenant install`. Inside the revenant server, report cwd and title to Ghostty the way its own shell
# integration does outside tmux: new tabs keep the directory, tab titles stay meaningful. Command
# start/end (OSC 133 C/D) also go through, so Ghostty's notify-on-command-finish works inside tmux.
[[ -n ${TMUX:-} && -n ${REVENANT:-} ]] || return 0

revenant_precmd() {
  local code=$?
  if [[ -n ${revenant_running:-} ]]; then
    printf '\033Ptmux;\033\033]133;D;%d\007\033\\' "$code"
    unset revenant_running
  fi
  printf '\033Ptmux;\033\033]7;file://%s%s\007\033\\' "$HOST" "${PWD// /%20}"
  printf '\033]2;%s\007' "${(%):-%~}"
}

revenant_preexec() {
  revenant_running=1
  printf '\033Ptmux;\033\033]133;C\007\033\\'
  printf '\033]2;%s\007' "${1[1,80]}"
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec revenant_preexec
# First in line, so $? is still the exit code of the command and not of another precmd hook.
precmd_functions=(revenant_precmd ${precmd_functions:#revenant_precmd})
