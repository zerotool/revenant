# shellcheck shell=bash disable=SC1003
# revenant shell integration for bash, sourced from your login profile by `revenant install`.
# Inside the revenant server, report cwd and title to Ghostty the way its own shell integration does
# outside tmux. On bash 4.4+ command start/end (OSC 133 C/D) also go through, so Ghostty's
# notify-on-command-finish works inside tmux; macOS's stock bash 3.2 gets cwd and titles only.
[[ -n ${TMUX:-} && -n ${REVENANT:-} ]] || return 0

__revenant_osc133=
((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4))) && __revenant_osc133=1

__revenant_prompt() {
	local code=$?
	# Command end. Every prompt but the first follows a command line; a D after an empty line has no
	# C before it, and Ghostty ignores it.
	[[ -n $__revenant_osc133 && -n ${__revenant_seen:-} ]] && printf '\033Ptmux;\033\033]133;D;%d\007\033\\' "$code"
	__revenant_seen=1
	printf '\033Ptmux;\033\033]7;file://%s%s\007\033\\' "$HOSTNAME" "${PWD// /%20}"
	printf '\033]2;%s\007' "${PWD/#$HOME/\~}"
	return "$code"
}

# First in line, so $? is still the exit code of the command. PROMPT_COMMAND may be an array (5.1+).
if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == "declare -a"* ]]; then
	PROMPT_COMMAND=(__revenant_prompt "${PROMPT_COMMAND[@]}")
else
	# shellcheck disable=SC2128,SC2178
	PROMPT_COMMAND="__revenant_prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi

# PS0 prints after a command line is read and before it runs: mark the start, title the tab with it.
if [[ -n $__revenant_osc133 ]]; then
	__revenant_ps0() {
		local _ cmd
		read -r _ cmd <<<"$(HISTTIMEFORMAT='' history 1)"
		printf '\033Ptmux;\033\033]133;C\007\033\\'
		printf '\033]2;%s\007' "${cmd:0:80}"
	}
	# shellcheck disable=SC2016
	PS0='$(__revenant_ps0)'"${PS0:-}"
fi
