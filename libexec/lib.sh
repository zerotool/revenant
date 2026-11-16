# shellcheck shell=bash
# Sourced by attach, reap and the revenant CLI (bash 3.2). A Ghostty process is identified by pid plus
# start time, so a recycled pid never makes a dead Ghostty look alive.

# Ghostty starts `command` with the bare launchd PATH, so look where package managers put tmux.
find_tmux() {
	local c
	for c in "${REVENANT_TMUX:-}" /opt/homebrew/bin/tmux /usr/local/bin/tmux /opt/local/bin/tmux /run/current-system/sw/bin/tmux "$(command -v tmux 2>/dev/null)"; do
		[[ -n $c && -x $c ]] && {
			echo "$c"
			return 0
		}
	done
	return 1
}

is_ghostty() { [[ -n $1 && $(ps -o comm= -p "$1" 2>/dev/null) == *ghostty ]]; }

owner_id() {
	local start
	start=$(LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null) || return 1
	echo "$1@${start// /}"
}

owner_alive() {
	[[ $1 == *@* ]] && is_ghostty "${1%%@*}" && [[ $(owner_id "${1%%@*}") == "$1" ]]
}

# Seconds since process $1 started.
uptime_s() {
	local e a b c d=0 h=0 m s
	e=$(ps -o etime= -p "$1" 2>/dev/null | tr -d ' ')
	[[ -n $e ]] || return 1
	[[ $e == *-* ]] && {
		d=${e%%-*}
		e=${e#*-}
	}
	IFS=: read -r a b c <<<"$e"
	if [[ -n $c ]]; then h=$a m=$b s=$c; else m=$a s=$b; fi
	echo $((10#$d * 86400 + 10#$h * 3600 + 10#$m * 60 + 10#$s))
}

# Sessions of a Ghostty that is gone wait for their restored tabs. Once the running Ghostty ($1) is
# past its restore window, nothing will claim them any more: a tab closed shortly before a quit, or
# one that Ghostty did not restore. $2... = tmux command.
gc_orphans() {
	local ghostty=$1 up
	shift
	up=$(uptime_s "$ghostty") || return 0
	((up >= ${REVENANT_RESTORE_WINDOW:-120})) || return 0
	"$@" list-sessions -F '#{session_id}|#{session_attached}|#{@revenant_owner}' 2>/dev/null |
		while IFS='|' read -r id attached owner; do
			# `if`, not an && chain: a false test must not become the loop's (and reap's) exit status,
			# or tmux prints "'reap …' returned 1" whenever the last listed session is not an orphan.
			if [[ $attached == 0 && -n $owner ]] && ! owner_alive "$owner"; then
				"$@" if-shell -F -t "$id" '#{==:#{session_attached},0}' "kill-session -t '$id'"
			fi
		done
}
