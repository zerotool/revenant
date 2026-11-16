#!/bin/bash
# Smoke test: lint, install/uninstall round trip, and the reap/gc logic on a throwaway tmux server.
# Touches nothing real: a temporary HOME, temporary config files, its own tmux socket.
# Usage: test/smoke.sh        Exit: 0 all passed · 1 a check failed
set -u
root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
t=$(mktemp -d)
socket=revenant-smoke-$$
failed=0
pass() { printf '  ✓ %s\n' "$*"; }
fail() {
	printf '  ✗ %s\n' "$*"
	failed=1
}
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
cleanup() {
	tmux -L "$socket" kill-server 2>/dev/null
	rm -rf "$t"
}
trap cleanup EXIT

echo "lint"
scripts=("$root/revenant" "$root"/libexec/{attach,reap,surface-id,lib.sh} "$root/shell/revenant.bash")
for f in "${scripts[@]}"; do
	check "bash 3.2 parses ${f#"$root"/}" "/bin/bash -n '$f'"
done
if command -v shellcheck >/dev/null; then
	if (cd "$root" && shellcheck -S warning -x "${scripts[@]}" test/smoke.sh) >"$t/sc" 2>&1; then
		pass "shellcheck (warnings and errors)"
	else
		fail "shellcheck"
		sed 's/^/      /' "$t/sc"
	fi
fi

echo "install / uninstall"
mkdir -p "$t/home/.local/bin"
printf 'font-size = 14\n' >"$t/ghostty.conf"
printf 'export EDITOR=vim\n' >"$t/zshrc"
cp "$t/ghostty.conf" "$t/ghostty.orig"
cp "$t/zshrc" "$t/zshrc.orig"
run() { HOME="$t/home" PATH="$t/home/.local/bin:$PATH" REVENANT_GHOSTTY_CONFIG="$t/ghostty.conf" REVENANT_RC="$t/zshrc" REVENANT_SHELL=zsh "$root/revenant" "$@"; }

run install --dry-run >"$t/out" 2>&1
check "dry run writes nothing" "cmp -s '$t/ghostty.conf' '$t/ghostty.orig' && cmp -s '$t/zshrc' '$t/zshrc.orig'"
run install >"$t/out" 2>&1
check "Ghostty config points at attach" "grep -qxF 'command = $root/libexec/attach' '$t/ghostty.conf'"
check "Ghostty config keeps the user's lines" "grep -qxF 'font-size = 14' '$t/ghostty.conf'"
check "zsh profile sources the integration" "grep -qF '$root/shell/revenant.zsh' '$t/zshrc'"
check "CLI linked onto PATH" "[[ \$(readlink '$t/home/.local/bin/revenant') == '$root/revenant' ]]"
check "backups written" "ls '$t'/ghostty.conf.revenant-backup-* >/dev/null 2>&1"
cp "$t/ghostty.conf" "$t/ghostty.once"
run install >"$t/out" 2>&1
check "second install changes nothing" "cmp -s '$t/ghostty.conf' '$t/ghostty.once' && grep -q 'already set' '$t/out'"
run uninstall >"$t/out" 2>&1
check "uninstall restores the Ghostty config" "cmp -s '$t/ghostty.conf' '$t/ghostty.orig'"
check "uninstall restores the profile" "cmp -s '$t/zshrc' '$t/zshrc.orig'"
check "uninstall removes the CLI link" "[[ ! -e '$t/home/.local/bin/revenant' ]]"

echo "package-manager install (REVENANT_ROOT)"
ln -s "$root" "$t/opt-revenant"
REVENANT_ROOT="$t/opt-revenant" run install >"$t/out" 2>&1
check "config keeps the stable root, not the resolved one" "grep -qxF 'command = $t/opt-revenant/libexec/attach' '$t/ghostty.conf'"
check "no CLI link: the package manager owns the PATH entry" "[[ ! -e '$t/home/.local/bin/revenant' ]]"
REVENANT_ROOT="$t/opt-revenant" run uninstall >"$t/out" 2>&1
check "uninstall restores the Ghostty config" "cmp -s '$t/ghostty.conf' '$t/ghostty.orig'"
check "--version prints the version" "'$root/revenant' --version | grep -qE '^revenant [0-9]+\.[0-9]+\.[0-9]+$'"

echo "bash integration"
for b in /bin/bash "$(command -v bash)"; do
	check "$($b -c 'echo bash $BASH_VERSION') hooks the prompt" \
		"TMUX=x REVENANT=1 PROMPT_COMMAND='echo hi' '$b' -c 'source \"$root/shell/revenant.bash\"; [[ \$PROMPT_COMMAND == __revenant_prompt* ]]'"
done

echo "reap and gc (tmux socket $socket)"
source "$root/libexec/lib.sh"
ghostty=$(pgrep -x ghostty | head -1)
if [[ -z $ghostty ]]; then
	echo "  - skipped: needs a running Ghostty"
else
	tmux_bin=$(find_tmux)
	tm=("$tmux_bin" -L "$socket")
	REVENANT_LIBEXEC="$root/libexec" "${tm[@]}" -f "$root/libexec/tmux.conf" new-session -d -s closed 'sleep 60'
	check "tmux.conf finds reap through REVENANT_LIBEXEC" "'${tm[0]}' -L '$socket' show-hooks -g client-detached | grep -qF '$root/libexec/reap'"
	"${tm[@]}" new-session -d -s ghost 'sleep 60' \; new-session -d -s plain 'sleep 60'
	"${tm[@]}" set-option -t closed @revenant_owner "$(owner_id "$ghostty")"
	"${tm[@]}" set-option -t ghost @revenant_owner "1@ThuJan100:00:001970"
	REVENANT_SOCKET=$socket "$root/revenant" status >"$t/out" 2>&1
	check "status shows a closing tab and a ghost" "grep -q 'closing' '$t/out' && grep -q 'ghost' '$t/out'"
	REVENANT_REAP_DELAY=1 REVENANT_RESTORE_WINDOW=0 "$root/libexec/reap" "$("${tm[@]}" display -p '#{socket_path}')"
	left=$("${tm[@]}" list-sessions -F '#{session_name}' 2>/dev/null | tr '\n' ' ')
	check "reap ends the closed tab and the ghost, keeps the rest (left: $left)" "[[ '$left' == 'plain ' ]]"
fi

((failed == 0)) && echo "all passed" || echo "FAILED"
exit "$failed"
