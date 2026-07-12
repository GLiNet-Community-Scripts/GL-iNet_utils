#!/bin/sh
# GL.iNet Router Toolkit
# Author: phantasm22
# License: GPL-3.0
# Version: 2026-07-12
#
# ── Versioning (bump the line above before every push to GitHub) ─────────────
# The self-updater compares this value as a plain string (test's \> operator),
# so incrementing it is exactly what tells installed copies a newer release
# exists. Forget to bump it and nobody gets the update.
# Format: YYYY-MM-DD  (e.g. 2026-07-04). For multiple releases on the same day as
# the previous version, append _HH:MM in 24-hour time (e.g. 2026-07-04_14:30)
# so each still sorts as newer. It MUST stay lexically sortable — a later
# date/time has to string-compare greater than an earlier one.
# ────────────────────────────────────────────────────────────────────────────
#
# This script provides system utilities for GL.iNet routers including:
# - Hardware information display with pagination
# - AdGuardHome management (UI updates, storage limits, lists)
# - System tweaks (zram, SSH keys, package management)
# - Benchmarking tools (network speed tests, CPU stress test)
# - System configuration viewer
# - Self-update mechanism to fetch latest script from GitHub
# - User-friendly interface with color coding and emojis
# - Robust error handling and input validation
# - Designed for OpenWrt-based GL.iNet routers, tested on various models
# Note: Some features may require specific hardware capabilities or firmware versions.

# =============================================================================
# UI / UX STANDARDS  (read before changing any prompt, menu, or message)
# =============================================================================
# Governance principle
# --------------------
# Clarity first, concision second. Every prompt and selectable label names the
# specific thing it acts on ("Delete this backup?" not "Confirm"). Use plain,
# conversational language and the fewest words that keep the action
# unambiguous - cut filler, never cut comprehension. Generic verbs ("OK", bare
# "Confirm", "Submit") and cryptic abbreviations are prohibited, as is padding
# that adds no information.
#
# "Choose" vs "Enter command"
#   "Choose [...]:"   one input is definitive/terminal (a choice).
#   "Enter command:"  inputs mutate pending on-screen state in a loop until a
#                     separate [C] Confirm (a command is a subset of choice).
#
# Vocabulary (locked)
#   [C] Confirm   [0] Exit / Main menu / Back / Cancel (by depth/context)
#   [?] Help      multi-select: [A] All  [N] None  [#] Toggle
#   pager: [P] Prev  [N] Next         [X] is never used.
#
# [0] label by depth
#   root -> Exit ;  depth-1 child -> Main menu ;  depth-2+ -> Back ;
#   pending/discard screen -> Cancel  (tie-break: does [0] discard pending state?)
#
# Prompt & flow rules
# 1. Disclose-then-ask, in exactly two parts: a disclosure and a terse prompt.
#    The disclosure (consequence of the non-default answer) is carried by status
#    message(s) - one or more, each properly iconed (ℹ️ info / ⚠️ warning) - OR
#    folded into the prompt line itself; never spread across a status line PLUS
#    separate UNPREFIXED body text. Each status line STATES, it never asks; the
#    one question is the terse prompt, phrased with a specific action verb (not a
#    generic "Continue/Yes"), especially for destructive actions. Don't re-ask
#    what the disclosure already said (no "Are you sure?"). Spacing depends on
#    what the disclosure IS - read => tight, scan => separated: inline PROSE (a
#    warning/explanation that is the decision's context) hugs the prompt, no blank
#    above it (Gestalt proximity); multiple independent warnings get one blank
#    BETWEEN them but still hug the prompt. A reviewable BLOCK the user scans - a
#    list, table, or change-summary - is its own region: separate it from the
#    action/prompt with one blank line or a divider (Gestalt common region; the
#    modal body-vs-footer pattern, same as a menu's options => "Choose").
# 2. Yes = the action; the capitalized default marks the safe side
#    (destructive => [y/N], expected/safe => [Y/n]). Never invert (no Yes=no-op).
# 3. Wording is the behavioral contract. Transition framing ("Enable it?") =>
#    N is a no-op (keep current). Declarative framing ("Should this persist?")
#    => N enforces the opposite (removes). Code MUST match the words. Prefer
#    transition framing for stateful toggles; never let N silently destroy.
# 4. State-first, valid transitions only. Show current state, then offer only
#    reachable transitions: for binary state, a single adaptive label that names
#    the concrete next action ("Enable X" when off / "Disable X" when on); an
#    action set (e.g. AGH Service Health [D]/[R]/[0]) for multi-state. Never force
#    the user to act twice to reach a state, and never label an item "Toggle" -
#    the label must state what it will do now. ([#] Toggle stays reserved for the
#    multi-select selection key, a different meaning.)
# 5. Check before you ask. Never present a [y/N] for an action already satisfied
#    or currently impossible. Refuse early and quietly when impossible;
#    warn-and-explain when already satisfied. No silent greying-out of menu
#    items without explanation.
# 6. Idempotent, truthful results. Report the ACTUAL delta ("Enabled" /
#    "Already set - no change" / "Removed" only when something was removed),
#    never a blanket success message.
# 7. Context-appropriate status. Every status/info/success/warning line must be
#    a direct response to the user's preceding action or answer. Never emit a
#    status about a topic the user didn't act on (no orphaned status). If a
#    state is worth surfacing absent a related action, fold it into the relevant
#    action's output rather than printing it standalone.
# 8. Ambient-state, not re-asked. For low-harm, easily reversible state, show
#    the state as status and expose the change as a named action: ask at most
#    once at the natural decision point, never re-ask once satisfied, always
#    offer a visible reversal. Forced/repeated confirmation is reserved for
#    destructive or irreversible actions.
# 9. Dwell mechanism. Match how a screen waits to its information value. User-
#    paced ("Press any key") for anything the user must READ - help, reports,
#    status/lists, and action results whose detail won't survive the return to a
#    cleared menu; also for any error needing user action. Timed auto-clear
#    (toast) ONLY for self-evident feedback that returns to a screen already
#    showing the situation: wrong-key validation (~1s) and content-bearing
#    no-op/cancel notices (~2s). Never zero-dwell - a message must never flash
#    and vanish with no pause.
# 10. Vertical spacing. One blank line is the unit of separation between
#     components (a section and the next prompt, a result and its footer).
#     Separators are leading-owned: the element BELOW emits the gap (a menu's
#     "\nChoose", press_any_key's leading "\n", a section's leading blank);
#     content never carries trailing blanks at a boundary - that is what causes
#     accidental double blanks. press_any_key is the single source of truth for
#     footer spacing (one blank); callers MUST NOT prepend printf "\n" before it.
#     Double blank lines are reserved for major in-screen section dividers only,
#     never at a component boundary. A printf "\n" is context-dependent: after
#     `read -r` (Enter echoed a newline) it is a BLANK line; after read_single_char
#     / `read -rsn1` / a bare prompt (no echoed newline) it is the line TERMINATOR,
#     not a blank - don't add a second expecting a gap. The single-source rule
#     generalizes beyond press_any_key: any function that emits its OWN leading
#     blank (press_any_key, agh_apply_and_restart) is the sole source of that
#     blank - callers MUST NOT emit a blank immediately before calling it.
#
# Help screens
#   Navigation menus get a [?] Help entry; pickers / numbered-selection /
#   binary-state / action screens do NOT (out of scope by rule). Help content is
#   generic and idempotent (no option numbers).
#
# Menu & picker input
#   Input mode is decided at the FUNCTIONAL-GROUP level, by constraint:
#     - A group containing any live/refreshing screen (or a paged VIEW like the
#       Hardware Info / Display Settings pagers) is KEY-ONLY - a single keypress
#       (read_single_char, or read -t for refresh); a blocking read would freeze
#       the redraw.
#     - Otherwise the group is KEY + ENTER (read -r) if any member can present a
#       multi-character token: an item number that reaches >=10, or a multi-char
#       command like "CL". ALL members of that group then use key+Enter for
#       consistency, even fixed <=9-item screens within it.
#     - A standalone fixed-<=9 single-char screen MAY be key-only, but never when
#       grouped with a line-based sibling. Text/value entry is always key+Enter.
#     - All major navigation menus are key+Enter.
#   The input prompt is separated from the options/action-bar block by ONE blank
#   line (Gestalt common region: options are a content region, the prompt is the
#   action). Wording is "Choose [<keys>]:" - the bracket lists valid keys, with
#   the item token from picker_range(): the live count as a range ("1-10"), but
#   just "1" for a single item (a range only when there IS a range - never
#   "1-1"), and never a literal "#".
#
# Rendering note
#   Trailing "\033[K" (erase-to-EOL) is load-bearing on in-place redraw screens
#   (fan / status / spinner). Do NOT remove it there.
#
# Progress indicators
#   spin_run (gear/⚙) = indeterminate wait - duration unknown until the command
#   finishes (opkg, openssl, a dd test whose throughput we're measuring).
#   countdown_run (hourglass/⏳) = determinate wait - the caller already knows
#   and told the user the total duration (e.g. a fixed-length stress test); it
#   counts down instead of spinning. Pick by determinacy, not by "which looks
#   nicer" - showing a spinner when the duration is already known withholds
#   information the user was already given.
#
# Table & List Alignment
#   Column justification is decided per-column by a 3-part test - right-justify
#   ONLY if all three hold, else left-justify:
#     1. Values are NOT normalized to near-constant width (i.e. not auto-scaled
#        across units specifically to keep text length ~constant regardless of
#        magnitude - that scaling defeats the entire mechanism right-justify
#        relies on: comparing magnitude by digit position).
#     2. No other element in the row (a bar, icon, or color) already shows
#        relative magnitude.
#     3. The reader's task is genuinely comparing/summing many values, not
#        reading one row as a self-contained status card about one entity.
#   Fails any of the three -> left-justify uniformly (Docker/kubectl-style: all
#   columns left, including numeric-looking ones - this is the default for our
#   small device-comparison leaderboards and toggle/checkbox lists).
#   A column's header MUST share its data row's exact format string (or at
#   minimum identical field-width declarations) wherever feasible - a
#   hand-typed separate header string WILL drift from computed data over time;
#   this is the root cause behind every alignment bug found in this audit.
#   Never center a column header. Screen/section TITLES (print_centered_header)
#   are a different UI element (a heading, not a table column) and are exempt.
#   Boolean/toggle indicators use tight brackets: [Y] [N] [✓] [ ] - content
#   flush against both brackets, no internal space padding. Under a column
#   header, a checkbox/toggle IS centered within its field (the one explicit
#   exception to "never center") - it is a symbol/glyph, not text or a
#   magnitude to compare, and the header word above it stays left-justified
#   per the normal text rule; the two don't need to share a visual midpoint,
#   just the same declared field width.
#   Placeholder/null-value markers (e.g. "---") that mean "not applicable"
#   rather than a real value ARE exempt from the column's justification and
#   may be centered within their field - they are not content being compared,
#   they are a symbol of incomparability, and distinct treatment aids scanning.
#   Centering with an odd remainder (can't split the padding evenly): give the
#   extra space to the right, so content sits one space left of true-center,
#   never right of it.
#   Out of scope: output piped directly from an external command (df, dd) that
#   has its own native formatting; vertical Label: Value blocks (System
#   Information, STATUS panels) which aren't row/column tables at all.
#
# Naming
#   Functions: lowercase snake_case, NO leading underscore, descriptive verb-led
#   (check_*, get_*, is_*, manage_*, show_*, install_*). A leading "_" is reserved
#   for internal runtime STATE variables only (_S_* mode symbols, _TERM_PROFILE).
#   Comments describe the code AS-IS, not its history - changelogs/diffs carry that.
# =============================================================================

# -----------------------------
# Color & Emoji
# -----------------------------
RESET="\033[0m"
CYAN="\033[36m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
GREY="\033[90m"
BOLD="\033[1m"
BLUE="\033[38;5;153m"

SPLASH="
   _____ _          _ _   _      _   
  / ____| |        (_) \\ | |    | |  
 | |  __| |  ______ _|  \\| | ___| |_ 
 | | |_ | | |______| | . \` |/ _ \\ __|
 | |__| | |____    | | |\\  |  __/ |_ 
  \\_____|______|   |_|_| \\_|\\___|\\__|

         GL.iNet Router Toolkit
"

# -----------------------------
# Global Variables
# -----------------------------
AGH_INIT="/etc/init.d/adguardhome"
AGH_DISABLED=0  # 0 = Available, 1 = Missing/Uninstalled
SPIN_LOG="/tmp/.glnet-op.$$"   # scratch log captured from spin_run output
opkg_updated=0
SCRIPT_URL="https://raw.githubusercontent.com/phantasm22/GL-iNet_utils/refs/heads/main/glinet_utils.sh"
CHANGELOG_URL="${SCRIPT_URL%glinet_utils.sh}CHANGELOG.md"
TMP_NEW_SCRIPT="/tmp/glinet_utils_new.sh"
case "$0" in
    /*)  SCRIPT_PATH="$0" ;;
    */*) SCRIPT_PATH="$(pwd)/$0" ;;
    *)   SCRIPT_PATH="$(command -v "$0" 2>/dev/null)" ;;
esac
[ -z "$SCRIPT_PATH" ] && SCRIPT_PATH="$(pwd)/$0"
INSTALL_PROMPTED=0    # Set to 1 after user responds to install prompt; reset by each new version
STARTUP_NOTICE=0      # Set by the install-skip so the update-check spinner runs 2s longer (readable)
INSTALL_PATH="/usr/sbin/glinet_utils"
OUTPUT_PREF="auto"    # "auto"|"full"|"compat" — saved in script; "auto" = detect each run
OUTPUT_MODE="full"    # Runtime: "full"|"compat"; set by detect_output_mode
_TERM_PROFILE="mac"   # Runtime: "mac"|"wt"|"ttyd"; set by detect_output_mode (full mode only)

# ─────────────────────────────────────────────────────────────────────────────
# Terminal Output Mode Detection
#
# OUTPUT_PREF   "auto"|"full"|"compat"  — persisted in script
# OUTPUT_MODE   "full"|"compat"         — runtime mode
# _TERM_PROFILE "mac"|"wt"|"ttyd"       — full-mode sub-profile (internal)
#
# Detection flow (auto mode):
#   TERM=xterm/screen/linux/vt*/ansi/putty* → compat (legacy/PuTTY terminals)
#   Otherwise → ensure stty (install coreutils-stty if missing), then probe:
#     Probe 1: ✅ advance=1 → ttyd  (xterm.js: all emoji narrow)
#     Probe 1: ✅ advance=2 → Probe 2: ⚠️+VS16 advance
#       advance=1 → mac  (keycaps ✓, 2sp after ambig+VS symbols)
#       advance=2 → wt   (keycaps ✗, 1sp after ambig+VS symbols)
#
# The probe REQUIRES a real stty (ESC[6n raw read); busybox does not ship one.
# ensure_stty installs coreutils-stty silently on first run. If a real
# (coreutils) stty can't be obtained, output falls back to Compatible mode.
#
# NO_COLOR strips ANSI colors but does not change mode or symbols.
# Two display modes: Full and Compatible.
# ─────────────────────────────────────────────────────────────────────────────

# Ensure a real (coreutils) `stty` is available for the cursor-advance probe.
# busybox's own stty applet can't drive the probe reliably, so we require the
# coreutils build and install it silently (no prompt) with a small spinner on
# first run. Returns 0 if a coreutils stty is present afterwards, 1 otherwise —
# the caller then falls back to Compatible mode.
ensure_stty() {
    stty --version 2>&1 | grep -qi coreutils && return 0

    local log="/tmp/.stty-install.$$" pid spin='-\|/' c
    ( opkg update && opkg install coreutils-stty ) >"$log" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        c=${spin%"${spin#?}"}                  # first character
        spin=${spin#?}$c                       # rotate frames
        printf '\rSetting up terminal support... %s' "$c" >/dev/tty
        usleep 100000 2>/dev/null || sleep 1
    done
    wait "$pid"
    printf '\r\033[K' >/dev/tty                # erase the spinner line
    rm -f "$log"
    stty --version 2>&1 | grep -qi coreutils
}

# Cursor advance probe: prints sym at col 1, queries cursor via ESC[6n,
# returns number of columns advanced. Cleans up after itself. Falls back to 2
# (which resolves to the Windows Terminal profile) if stty/the probe is absent.
probe_advance() {
    local sym="$1" col saved stty_bin tmpf="/tmp/.probe.$$"
    stty_bin=$(command -v stty 2>/dev/null) || { printf '2'; return; }
    saved=$("$stty_bin" -g 2>/dev/null)       || { printf '2'; return; }
    "$stty_bin" raw -echo min 0 time 2 2>/dev/null
    printf '\r%s\033[6n' "$sym" >/dev/tty
    dd if=/dev/tty bs=20 count=1 >"$tmpf" 2>/dev/null
    "$stty_bin" "$saved" 2>/dev/null
    printf '\r\033[K' >/dev/tty
    col=$(sed 's/.*\[\([0-9]*\);\([0-9]*\)R.*/\2/' "$tmpf" 2>/dev/null)
    rm -f "$tmpf"
    case "$col" in
        [0-9]*) printf '%d' $((col - 1)) ;;
        *)      printf '2' ;;
    esac
}

detect_output_mode() {

    # ── Step 1: Determine base mode ──────────────────────────────────────────
    if [ "$OUTPUT_PREF" = "compat" ]; then
        OUTPUT_MODE="compat"
    elif [ "$OUTPUT_PREF" = "full" ]; then
        OUTPUT_MODE="full"
    else
        # "auto" (or any unrecognised value) → detect from environment
        OUTPUT_MODE="full"
        case "${TERM:-dumb}" in
            dumb|unknown|""|xterm|screen|linux|vt100|vt220|ansi|putty*)
                OUTPUT_MODE="compat" ;;
        esac
        [ "${GL_COMPAT+x}" ] && OUTPUT_MODE="compat"   # env var power-user override (force Compatible)
    fi

    # ── Step 2: NO_COLOR — strip ANSI colors only, keep symbols/mode ─────────
    if [ "${NO_COLOR+x}" ]; then
        RESET=""; CYAN=""; GREEN=""; RED=""; YELLOW=""
        GREY=""; BOLD=""; BLUE=""
    fi

    # ── Step 3: Probe terminal sub-profile (full mode only) ──────────────────
    # The probe needs a real (coreutils) stty; busybox's applet can't drive it.
    # ensure_stty installs coreutils-stty on first run; if one can't be obtained
    # we fall back to Compatible mode (one consistent set), not a mixed profile.
    _TERM_PROFILE="mac"
    if [ "$OUTPUT_MODE" = "full" ]; then
        if ensure_stty; then
            _wide=$(probe_advance '✅')
            if [ "$_wide" = "1" ]; then
                _TERM_PROFILE="ttyd"            # xterm.js: all emoji adv=1
            else
                _ambig=$(probe_advance '⚠️')
                [ "$_ambig" = "2" ] && _TERM_PROFILE="wt"
            fi
        else
            OUTPUT_MODE="compat"               # can't probe without a real stty -> use the consistent Compatible set
        fi
    fi

    # ── Step 4: Set symbol variables ─────────────────────────────────────────
    if [ "$OUTPUT_MODE" = "full" ]; then

        # Wide emoji (✅ ❌ ⏳): adv=2 on mac/wt, adv=1 on ttyd — 1sp correct for all
        # (⏳ is wide-by-default, NOT ambig+VS like ⚠️ ℹ️ ⚙️ — it takes 1sp even
        # in the default profile where those take 2sp)
        _S_OK="✅ "
        _S_ERR="❌ "
        _S_ON="✅"; _S_OFF="❌"           # status icons (emoji already carry color)

        case "$_TERM_PROFILE" in
            ttyd)
                # xterm.js: all emoji adv=1 — 1 trailing space after everything
                _S_WARN="⚠️ ";  _S_INFO="ℹ️ ";  _S_ACT="⚙️ ";  _S_TIME="⏳ "
                N1="1️⃣"; N2="2️⃣"; N3="3️⃣"; N4="4️⃣"; N5="5️⃣"
                N6="6️⃣"; N7="7️⃣"; N8="8️⃣"; N9="9️⃣"; N0="0️⃣"
                NQ="❓"; NCL="🆑"
                ;;
            wt)
                # Windows Terminal: ambig+VS adv=2 — 1sp sufficient
                # Keycaps render as □1 — use text numbers
                _S_WARN="⚠️ ";  _S_INFO="ℹ️ ";  _S_ACT="⚙️ ";  _S_TIME="⏳ "
                N1="[1]"; N2="[2]"; N3="[3]"; N4="[4]"; N5="[5]"
                N6="[6]"; N7="[7]"; N8="[8]"; N9="[9]"; N0="[0]"
                NQ="[?] "; NCL="[CL]"
                ;;
            *)
                # macOS Terminal + Linux terminals (default)
                # ambig+VS: adv=1 but visual 2-wide — 2sp leaves 1 visible gap
                _S_WARN="⚠️  ";  _S_INFO="ℹ️  ";  _S_ACT="⚙️  ";  _S_TIME="⏳ "
                N1="1️⃣"; N2="2️⃣"; N3="3️⃣"; N4="4️⃣"; N5="5️⃣"
                N6="6️⃣"; N7="7️⃣"; N8="8️⃣"; N9="9️⃣"; N0="0️⃣"
                NQ="❓"; NCL="🆑"
                ;;
        esac

    else    # compat — PuTTY, legacy, bare vt terminals
        _S_OK="[√] "
        _S_ERR="[×] "
        _S_ON="${GREEN}√${RESET}"; _S_OFF="${RED}×${RESET}"   # status icons (need explicit color)
        _S_WARN="[!] "
        _S_INFO="[i] "
        _S_ACT="[❋] "
        _S_TIME="[…] "   # all single-width & PuTTY-safe; [√]/[×] mirror on/off √/× and full-mode ✅/❌, [❋]≈gear, […]=wait
        N1="[1]"; N2="[2]"; N3="[3]"; N4="[4]"; N5="[5]"
        N6="[6]"; N7="[7]"; N8="[8]"; N9="[9]"; N0="[0]"
        NQ="[?] "; NCL="[CL]"
    fi
}

# ── Terminal setup / restore ─────────────────────────────────────────────────
# Best-effort, for the session only: widen the window to a usable size and set a
# dark theme, then put everything back on exit. Terminals that don't support a
# given sequence just ignore it (PuTTY ignores the OSC colors; non-xterm ignore
# the resize), so this is safe everywhere.
TERM_MIN_COLS=110
TERM_MIN_ROWS=30
_TERM_ORIG_SIZE=""    # "rows;cols" saved at setup; empty = nothing to restore
_TERM_RESTORED=""

terminal_setup() {
    local _sz _r _c _nr _nc
    [ "${GL_NO_TERM_SETUP+x}" ] && return          # power-user opt-out
    [ -t 1 ] || return                              # only on a real terminal
    [ -n "$TMUX" ] && return                         # not inside tmux
    case "${TERM:-}" in screen*|tmux*) return ;; esac

    printf '\033]11;#000000\007\033]10;#ffffff\007'  # best-effort dark theme (OSC 11/10)

    # Grow only (never shrink). Needs a real stty to read the size so we can
    # restore it on exit; skip just the resize if stty isn't available.
    command -v stty >/dev/null 2>&1 || return
    _sz=$(stty size 2>/dev/null </dev/tty); _r=${_sz% *}; _c=${_sz#* }
    case "$_r" in ''|*[!0-9]*) return ;; esac
    case "$_c" in ''|*[!0-9]*) return ;; esac
    _TERM_ORIG_SIZE="${_r};${_c}"
    _nr=$_r; _nc=$_c
    [ "$_c" -lt "$TERM_MIN_COLS" ] && _nc=$TERM_MIN_COLS
    [ "$_r" -lt "$TERM_MIN_ROWS" ] && _nr=$TERM_MIN_ROWS
    { [ "$_nr" != "$_r" ] || [ "$_nc" != "$_c" ]; } && printf '\033[8;%s;%st' "$_nr" "$_nc"
}

terminal_restore() {
    [ -n "$_TERM_RESTORED" ] && return              # idempotent - run once
    _TERM_RESTORED=1
    stty sane 2>/dev/null </dev/tty                 # restore line discipline: single-char reads (or a Ctrl-C mid-read) can leave the tty raw
    printf '\033[?25h'                              # ensure cursor visible
    printf '\033]110\007\033]111\007'              # reset fg/bg to profile defaults
    [ -n "$_TERM_ORIG_SIZE" ] && printf '\033[8;%st' "$_TERM_ORIG_SIZE"
}

# Show the splash first, then detect the terminal. On first run this installs
# coreutils-stty, so the "Setting up terminal support..." spinner appears under
# the splash (before the menu) rather than on a blank screen.
command -v clear >/dev/null 2>&1 && clear
printf "%b\n" "$SPLASH"
detect_output_mode

# Widen + dark-theme the terminal for this session; restore it all on exit.
terminal_setup
trap 'terminal_restore' EXIT
trap 'terminal_restore; exit 130' INT
trap 'terminal_restore; exit 143' TERM

# -----------------------------
# Cleanup any previous updates
# -----------------------------
case "$0" in
    *.new)
        ORIGINAL="${0%.new}"
        printf "%s Applying update...\n" "$_S_ACT"
        # Carry the saved display preference into the new copy — an update swaps
        # the whole script, which would otherwise reset OUTPUT_PREF to default.
        old_pref=$(sed -n 's/^OUTPUT_PREF="\([^"]*\)".*/\1/p' "$ORIGINAL" 2>/dev/null)
        case "$old_pref" in
            full|compat) sed -i "s/^OUTPUT_PREF=\"[^\"]*\"/OUTPUT_PREF=\"$old_pref\"/" "$0" ;;
        esac
        mv -f "$0" "$ORIGINAL" && chmod +x "$ORIGINAL"
        printf "%s Update applied. Restarting...\n" "$_S_OK"
        sleep 3
        stty sane 2>/dev/null </dev/tty
        exec "$ORIGINAL" "$@"
        ;;
esac

# -----------------------------
# Utility Functions
# -----------------------------
# Count set bits in a hex mask ("0x7" -> 3). Empty/invalid -> 0. Used to turn an
# antenna chainmask into a spatial-stream count.
popcount_hex() {
    case "$1" in ''|0x|0X) printf '0'; return ;; esac
    _pc_n=$(( $1 )); _pc_c=0
    while [ "$_pc_n" -gt 0 ]; do _pc_c=$(( _pc_c + (_pc_n & 1) )); _pc_n=$(( _pc_n >> 1 )); done
    printf '%s' "$_pc_c"
}

press_any_key() {
    printf "\nPress any key to continue... "
    read -rsn1
    printf "\n"
}

read_single_char() {
    read -rsn1 char
    printf "%s" "$char"
}

# Item-selection token for a picker prompt: "1-N" only when there is an actual
# range; a single item prints just "1". Empty/zero count -> "1" (safe default).
picker_range() {
    [ "${1:-0}" -gt 1 ] 2>/dev/null && printf '1-%s' "$1" || printf '1'
}

print_centered_header() {
    title="$1"
    width=48
    title_display_len=${#title}
    case "$title" in
        *[🖥️📡🌐🔒⚙️💾📊🛡️📋☁️]*) title_display_len=$((title_display_len - 2)) ;;
    esac
    
    padding=$(((width - title_display_len) / 2))
    padding_right=$((width - padding - title_display_len))
    
    printf "\n%b\n" "${CYAN}┌────────────────────────────────────────────────┐${RESET}"
    printf "%b" "${CYAN}│"
    printf "%*s" $padding ""
    printf "%s" "$title"
    printf "%*s" $padding_right ""
    printf "%b\n" "│${RESET}"
    printf "%b\n\n" "${CYAN}└────────────────────────────────────────────────┘${RESET}"
}

print_success() { printf "%b\n" "${BOLD}${GREEN}${_S_OK}${RESET}${GREEN}$1${RESET}"; }
print_error()   { printf "%b\n" "${BOLD}${RED}${_S_ERR}${RESET}${RED}$1${RESET}"; }
print_warning() { printf "%b\n" "${BOLD}${YELLOW}${_S_WARN}${RESET}${YELLOW}$1${RESET}"; }
print_info()    { printf "%b\n" "${BOLD}${BLUE}${_S_INFO}${RESET}${BLUE}$1${RESET}"; }
print_action()  { printf "%b\n" "${BOLD}${CYAN}${_S_ACT}${RESET}${CYAN}$1${RESET}"; }

# Helper: Secure Password Input with Asterisks
get_password() {
    local prompt="$1"
    local password=""
    local char=""
    local backspace=$(printf '\177')
    local ctrl_h=$(printf '\b')

    printf "%s" "$prompt" >&2  
    while :; do
        read -s -n 1 char
        if [ -z "$char" ] || [ "$char" = "$(printf '\r')" ]; then
            break
        fi

        if [ "$char" = "$backspace" ] || [ "$char" = "$ctrl_h" ]; then
            if [ ${#password} -gt 0 ]; then
                password="${password%?}"
                printf "\b \b" >&2
            fi
        else
            password="$password$char"
            printf "*" >&2
        fi
    done
    printf "\n" >&2
    printf "%s" "$password" 
}

# -----------------------------
# Changelog viewer
# -----------------------------
# show_changelog [ARGS...]
#   Fetches CHANGELOG.md and renders it newest-first in the house pager. When the
#   running version is behind the newest entry, a grey "your version" rule marks
#   the boundary between new-to-you entries (above) and already-installed ones
#   (below), and a [U] Update key appears in the footer -> apply_update, which
#   re-downloads and restarts. One render path for both the startup prompt and
#   the Toolkit Management menu; $CL_EXIT_LABEL sets the [0] label ("Skip" from
#   startup, "Back" from the menu). Page height comes from `stty size`, or a
#   safe 22-line default when stty can't report one. ARGS forward to apply_update
#   for the exec-on-restart. Returns 1 if the changelog can't be fetched.
show_changelog() {
    local _cl_file="/tmp/.gl-changelog.$$" _cl_rn="/tmp/.gl-cl-render.$$"
    local _local _latest _behind _exitlbl
    local _total _rows _plines _pages _start _end _page _key _i _starts _nstart

    _local="$(grep -m1 '^# Version:' "$SCRIPT_PATH" | awk '{print $3}' | tr -d '\r')"
    [ -z "$_local" ] && _local="0000-00-00"
    _exitlbl="${CL_EXIT_LABEL:-Back}"

    if ! wget -q -O "$_cl_file" "$CHANGELOG_URL" 2>/dev/null || [ ! -s "$_cl_file" ]; then
        rm -f "$_cl_file"
        return 1
    fi

    # Newest "## <version>" header is the latest release.
    _latest="$(grep -m1 '^## ' "$_cl_file" | awk '{print $2}')"
    if [ -n "$_latest" ] && [ "$_latest" \> "$_local" ]; then _behind=1; else _behind=0; fi

    # Render newest-first (drop the intro before the first header). When behind,
    # emit a grey boundary rule just before the first entry that is <= your
    # version, so everything above the rule is new to you.
    awk -v local="$_local" -v behind="$_behind" -v g="$GREY" -v r="$RESET" '
        /^## / {
            seen = 1
            if (behind && !marked && ($2 "") <= (local "")) {
                printf " %s─────────────────────  your version: %s  ─────────────────────%s\n\n", g, local, r
                marked = 1
            }
            print; next
        }
        seen { print }
    ' "$_cl_file" > "$_cl_rn"
    rm -f "$_cl_file"

    _total=$(wc -l < "$_cl_rn" 2>/dev/null)
    case "$_total" in ''|*[!0-9]*) _total=0 ;; esac
    if [ "$_total" -eq 0 ]; then
        rm -f "$_cl_rn"
        return 1
    fi

    # Changelog lines per screen: real height minus chrome, else a safe default.
    _rows=$(stty size 2>/dev/null | awk '{print $1}')
    case "$_rows" in
        ''|*[!0-9]*) _plines=22 ;;
        *) _plines=$((_rows - 8)); [ "$_plines" -lt 12 ] && _plines=12 ;;
    esac

    # Page-start line numbers, snapped so a page never breaks mid-bullet: fill up
    # to _plines lines, then back the cut up to the nearest header/bullet/rule so a
    # wrapped bullet's continuation lines stay with it. Hard-cuts only if a single
    # unit is taller than one page.
    _starts=$(awk -v plines="$_plines" '
        { safe[NR] = ($0 ~ /^## / || $0 ~ /^- / || index($0, "your version:")) ? 1 : 0 }
        END {
            total = NR; s = 1; printf "%d", s
            while (s + plines <= total) {
                cut = s + plines
                while (cut > s + 1 && !safe[cut]) cut--
                if (cut <= s + 1) cut = s + plines
                printf " %d", cut
                s = cut
            }
        }' "$_cl_rn")
    [ -z "$_starts" ] && _starts=1                  # defensive: never wedge navigation on empty awk output
    _pages=$(echo "$_starts" | awk '{print NF}')
    case "$_pages" in ''|*[!0-9]*|0) _pages=1 ;; esac

    _page=1
    while :; do
        _start=$(echo "$_starts" | cut -d' ' -f"$_page")
        _nstart=$(echo "$_starts" | cut -d' ' -f"$((_page + 1))")
        if [ -n "$_nstart" ]; then _end=$((_nstart - 1)); else _end=$_total; fi
        clear
        print_centered_header "Change Log"
        printf "\n"
        sed -n "${_start},${_end}p" "$_cl_rn"
        printf " ──────────────────────────────────────────────────────────────────────────────\n"

        # House pager footer: [P] Previous  <chips|Page X/Y>  [N] Next  [U]?  [0] label.
        # Numbered chips up to 9 pages (read_single_char can't take a two-digit
        # jump); a "Page X of Y" counter beyond that.
        printf " [P] Previous   "
        if [ "$_pages" -le 9 ]; then
            _i=1
            while [ "$_i" -le "$_pages" ]; do
                if [ "$_i" -eq "$_page" ]; then printf "%b[%d]%b " "$BOLD" "$_i" "$RESET"
                else printf "%b[%d]%b " "$GREY" "$_i" "$RESET"; fi
                _i=$((_i + 1))
            done
        else
            printf "%bPage %d of %d%b   " "$BOLD" "$_page" "$_pages" "$RESET"
        fi
        printf "  [N] Next   "
        [ "$_behind" -eq 1 ] && printf "[U] Update   "
        printf "[0] %s  " "$_exitlbl"

        _key=$(read_single_char)
        printf "\n"
        case "$_key" in
            p|P) [ "$_page" -gt 1 ]        && _page=$((_page - 1)) ;;
            n|N) [ "$_page" -lt "$_pages" ] && _page=$((_page + 1)) ;;
            u|U) if [ "$_behind" -eq 1 ]; then
                     apply_update "$@"   # execs on success; returns here only on failure
                     press_any_key
                 fi ;;
            0)   break ;;
            [1-9]) if [ "$_pages" -le 9 ] && [ "$_key" -le "$_pages" ]; then
                       _page="$_key"
                   fi ;;
            *)   : ;;
        esac
    done

    rm -f "$_cl_rn"
    return 0
}

# apply_update [ARGS...] : download the latest script, swap it in, and restart.
# Used by the changelog viewer's [U]. Execs on success (never returns); returns
# 1 on a download/write failure so the viewer can recover and let you retry.
apply_update() {
    if ! spin_run "Downloading update" wget -q -O "$TMP_NEW_SCRIPT" "$SCRIPT_URL"; then
        rm -f "$SPIN_LOG" 2>/dev/null
        print_warning "Download failed (network or GitHub issue)."
        return 1
    fi
    rm -f "$SPIN_LOG" 2>/dev/null
    print_action "Updating..."
    if ! cp "$TMP_NEW_SCRIPT" "$SCRIPT_PATH.new" || ! chmod +x "$SCRIPT_PATH.new"; then
        print_warning "Could not write ${SCRIPT_PATH}.new (permissions?)."
        rm -f "$TMP_NEW_SCRIPT" 2>/dev/null
        return 1
    fi
    print_success "Upgrade complete. Restarting..."
    stty sane 2>/dev/null </dev/tty   # reset line discipline (a raw-mode keypress triggered us) so the restarted copy can read input
    exec "$SCRIPT_PATH.new" "$@"
}

# -----------------------------
# Self-update check (startup)
# -----------------------------
# Runs once at launch: fetches the remote version, records UPDATE_STATUS and
# REMOTE_VERSION for the Toolkit Management STATUS block, and — only when a newer
# release exists — offers to open the changelog viewer (where [U] applies it).
# Silent when already current, so startup stays quiet unless there's news.
check_self_update() {
    local ans _rc
    LOCAL_VERSION="$(grep -m1 '^# Version:' "$SCRIPT_PATH" | awk '{print $3}' | tr -d '\r')"
    [ -z "$LOCAL_VERSION" ] && LOCAL_VERSION="0000-00-00"

    # Fetch the remote copy to read its version. When a first-run install-skip
    # notice is on screen (STARTUP_NOTICE), let the spinner run 2s longer so the
    # message reads as productive activity instead of a dead pause. The sh -c
    # wrapper preserves wget's real exit code across the padding sleep.
    if [ "$STARTUP_NOTICE" = 1 ]; then
        spin_run "Checking for updates" sh -c 'wget -q -O "$1" "$2"; rc=$?; sleep 2; exit $rc' sh "$TMP_NEW_SCRIPT" "$SCRIPT_URL"
    else
        spin_run "Checking for updates" wget -q -O "$TMP_NEW_SCRIPT" "$SCRIPT_URL"
    fi
    _rc=$?
    if [ "$_rc" -ne 0 ]; then
        rm -f "$SPIN_LOG" 2>/dev/null
        UPDATE_STATUS="unknown"
        return 1
    fi
    rm -f "$SPIN_LOG" 2>/dev/null

    REMOTE_VERSION="$(grep -m1 '^# Version:' "$TMP_NEW_SCRIPT" | awk '{print $3}' | tr -d '\r')"
    [ -z "$REMOTE_VERSION" ] && REMOTE_VERSION="0000-00-00"
    rm -f "$TMP_NEW_SCRIPT" >/dev/null 2>&1

    if [ "$REMOTE_VERSION" \> "$LOCAL_VERSION" ]; then
        UPDATE_STATUS="available"
        printf "\nA new version is available. View Change Log & Update? [Y/n]: "
        read -r ans
        printf "\n"
        case "$ans" in
            n|N) print_info "Skipping the change log and update — available in the Toolkit Management menu."; sleep 2 ;;
            *)   CL_EXIT_LABEL="Skip"; show_changelog "$@"; CL_EXIT_LABEL="" ;;
        esac
    else
        UPDATE_STATUS="current"
    fi
}

# -----------------------------
# System Detection Functions
# -----------------------------
# Run a command in the background with a "<label>... <spinner>" indicator, then
# finalize the line (label, no spinner) and return the command's exit status.
# Output is captured to $SPIN_LOG so the caller can inspect it on failure.
spin_run() {
    local label="$1"; shift
    local pid rc c spin='-\|/'
    "$@" >"$SPIN_LOG" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        c=${spin%"${spin#?}"}; spin=${spin#?}$c
        printf "\r${BOLD}${CYAN}${_S_ACT}${RESET}${CYAN}%s...${RESET} %s" "$label" "$c"
        usleep 100000 2>/dev/null || sleep 1
    done
    wait "$pid"; rc=$?
    printf "\r${BOLD}${CYAN}${_S_ACT}${RESET}${CYAN}%s...${RESET}\033[K\n" "$label"
    return "$rc"
}

# Like spin_run, but for a command with a KNOWN fixed duration (the caller
# already told the user how long) - shows seconds remaining instead of a
# generic spinner. Output is captured to $SPIN_LOG, same as spin_run.
countdown_run() {
    local label="$1" total="$2"; shift 2
    local pid rc remain
    "$@" >"$SPIN_LOG" 2>&1 &
    pid=$!
    remain=$total
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${BOLD}${CYAN}${_S_TIME}${RESET}${CYAN}%s...${RESET} %ds remaining" "$label" "$remain"
        sleep 1
        [ "$remain" -gt 0 ] && remain=$((remain - 1))
    done
    wait "$pid"; rc=$?
    printf "\r${BOLD}${CYAN}${_S_TIME}${RESET}${CYAN}%s...${RESET}\033[K\n" "$label"
    return "$rc"
}

# Diagnose a failed network operation: pings the internet, then the package
# server, and prints targeted advice. Returns 0 only if both are reachable.
check_connectivity() {
    if ! ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        print_error "→ No internet connectivity (cannot reach 8.8.8.8)"
    elif ! ping -c 1 -W 3 downloads.openwrt.org >/dev/null 2>&1; then
        print_error "→ Internet works, but cannot reach the package server (DNS or repo issue?)"
    else
        return 0
    fi
    printf "\n"
    print_info "Common fixes:"
    printf "   • Check your internet connection\n"
    printf "   • Try: ping fw.gl-inet.com or ping downloads.openwrt.org\n"
    printf "   • Check date/time is correct (HTTPS validation)\n"
    printf "   • Re-flash firmware if repositories are very old or corrupted\n"
    return 1
}

# Refresh opkg package lists once per session (gated by $opkg_updated). Shows a
# spinner; on failure prints diagnostics and returns non-zero - callers decide
# how to recover (it no longer exits the program).
check_opkg_updated() {
    [ "$opkg_updated" -eq 1 ] && return 0
    if spin_run "Updating package lists" opkg update; then
        opkg_updated=1
        rm -f "$SPIN_LOG" 2>/dev/null
        return 0
    fi
    print_error "opkg update failed."
    check_connectivity
    print_info "Collected errors:"
    tail -n 20 "$SPIN_LOG" 2>/dev/null | grep -E '^(\*|\*\*\*|Collected errors:|wget returned)' | sed 's/^/  /'
    printf "\n"
    rm -f "$SPIN_LOG" 2>/dev/null
    return 1
}

# Ensure <pkg> is installed: no-op if already present, else refresh lists and
# install it with a spinner. $2 = optional friendly name for messages.
# Returns 0 if the package is installed afterwards, 1 otherwise.
install_package() {
    local pkg="$1" name="${2:-$1}"
    opkg list-installed 2>/dev/null | grep -q "^$pkg " && return 0
    check_opkg_updated || return 1
    spin_run "Installing $name" opkg install "$pkg"
    if opkg list-installed 2>/dev/null | grep -q "^$pkg "; then
        print_success "Installed: $name"
        rm -f "$SPIN_LOG" 2>/dev/null
        return 0
    fi
    print_error "Failed to install $name."
    check_connectivity
    rm -f "$SPIN_LOG" 2>/dev/null
    return 1
}

get_lan_ip() {
    local lan_ip
    lan_ip=$(ip -4 addr show br-lan 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n1)
    [ -z "$lan_ip" ] && lan_ip=$(uci -q get network.lan.ipaddr)
    [ -z "$lan_ip" ] && lan_ip="192.168.8.1"
    echo "${lan_ip}"
}

get_free_space() {
        local path="$1"
        while [ -n "$path" ] && [ ! -d "$path" ]; do
            path="${path%/*}"
        done
        [ -z "$path" ] && path="/"
        df -Ph "$path" 2>/dev/null | awk 'NR==2 {print $4}'
    }

get_fan_speed() {
    local fan_val=""
    local gl_path="/proc/gl-hw-info/fan"
    local node=""
    if [ -f "$gl_path" ]; then
        read -r node rest < "$gl_path" 2>/dev/null
        if [ -n "$node" ]; then
            for f in /sys/class/hwmon/"$node"/fan*_input; do
                if [ -f "$f" ]; then
                    read -r fan_val < "$f" 2>/dev/null
                    break
                fi
            done
        fi
    fi
    if [ -z "$fan_val" ]; then
        for f in /sys/class/hwmon/hwmon*/fan*_input; do
            if [ -f "$f" ]; then
                read -r fan_val < "$f" 2>/dev/null
                break
            fi
        done
    fi
    echo "${fan_val:-N/A}"
}

get_cpu_temp() {
    local raw_temp=""
    local temp_path=""
    if [ -f /proc/gl-hw-info/temperature ]; then
        read -r temp_path < /proc/gl-hw-info/temperature 2>/dev/null
    fi
    if [ -f "$temp_path" ]; then
        read -r raw_temp < "$temp_path" 2>/dev/null
    fi
    if [ -z "$raw_temp" ]; then
        for f in /sys/class/hwmon/hwmon*/temp*_input; do
            if [ -f "$f" ]; then
                read -r raw_temp < "$f" 2>/dev/null
                break
            fi
        done
    fi
    if [ -n "$raw_temp" ] && [ "$raw_temp" -ge 1000 ]; then
        local whole=$((raw_temp / 1000))
        local decimal=$(( (raw_temp % 1000) / 10 ))
        local formatted_decimal=$(printf "%02d" "$decimal")
        echo "$whole.$formatted_decimal"
    else
        echo "unknown"
    fi
}

get_cpu_vendor_model() {
    if [ -f /proc/device-tree/compatible ]; then
        result=$(tr '\0' '\n' < /proc/device-tree/compatible 2>/dev/null | grep -iE '^(mediatek|qcom|qca),' | head -1 | sed -E 's/^(mediatek|qcom|qca),/\1 /i; s/mt/MT/i; s/ipq/IPQ/i; s/qca/QCA/i')
        
        if [ -n "$result" ]; then
            printf "%s" "$result"
        else
            printf "Unknown"
        fi
    else
        printf "Unknown"
    fi
}

# Best-effort max CPU clock in MHz. Sources, most authoritative first; prints
# nothing if none are readable, so the caller simply omits the Frequency line.
#   1) lscpu             - x86 and boards that populate the MHz fields
#   2) cpufreq sysfs max - boards with a running DVFS governor
#   3) device-tree OPP   - opp-hz (64-bit big-endian Hz) decoded via hexdump;
#                          boards with an OPP table but no cpufreq driver loaded
#   4) last resort       - known fixed clocks for legacy SoCs that expose no
#                          OPP/cpufreq/lscpu data; only reached when 1-3 fail
get_cpu_freq_mhz() {
    local mhz khz v f

    if command -v lscpu >/dev/null 2>&1; then
        mhz=$(lscpu 2>/dev/null | awk -F: '/CPU max MHz/{print $2; exit}' | tr -dc '0-9.')
        [ -z "$mhz" ] && mhz=$(lscpu 2>/dev/null | awk -F: '/CPU MHz/{print $2; exit}' | tr -dc '0-9.')
        [ -n "$mhz" ] && { printf '%s' "$mhz"; return; }
    fi

    khz=0
    for f in /sys/devices/system/cpu/cpufreq/policy*/cpuinfo_max_freq \
             /sys/devices/system/cpu/cpu*/cpufreq/cpuinfo_max_freq; do
        [ -r "$f" ] || continue
        v=$(cat "$f" 2>/dev/null)
        [ "${v:-0}" -gt "$khz" ] 2>/dev/null && khz=$v
    done
    [ "$khz" -gt 0 ] 2>/dev/null && { printf '%s' "$((khz / 1000))"; return; }

    if command -v hexdump >/dev/null 2>&1; then
        mhz=$(for f in /proc/device-tree/cpus/opp_table*/opp*/opp-hz; do
                  [ -f "$f" ] && hexdump -v -e '1/1 "%u "' "$f"
                  echo
              done | awk '{v=0; for(i=1;i<=NF;i++) v=v*256+$i; if(v>m) m=v}
                         END{if(m>0) printf "%.0f", m/1000000}')
        [ -n "$mhz" ] && { printf '%s' "$mhz"; return; }
    fi

    # Last resort: known fixed clocks for legacy SoCs with no programmatic source.
    case "$(get_cpu_vendor_model)" in
        *MT7986*)  printf '2000' ;; # Flint 2
        *MT7981*)  printf '1300' ;; # Beryl AX
        *MT7621*)  printf '880'  ;; # Beryl
        *SF19A28*) printf '1000' ;; # Opal
        *IPQ4018*) printf '717'  ;; # Slate Plus
    esac
}

get_mem_stats() {
    local t=0 a=0 f=0
    if [ -f /proc/meminfo ]; then
        while read -r label value unit; do
            case "$label" in
                MemTotal:)     t=$((value / 1024)) ;;
                MemAvailable:) a=$((value / 1024)) ;;
                MemFree:)      f=$((value / 1024)) ;;
            esac
            [ "$t" -gt 0 ] && [ "$a" -gt 0 ] && [ "$f" -gt 0 ] && break
        done < /proc/meminfo
    fi
    local m=$t
    if [ "$m" -le 32 ]; then mem_rounded=32
    elif [ "$m" -le 64 ]; then mem_rounded=64
    elif [ "$m" -le 128 ]; then mem_rounded=128
    elif [ "$m" -le 256 ]; then mem_rounded=256
    elif [ "$m" -le 512 ]; then mem_rounded=512
    elif [ "$m" -le 1024 ]; then mem_rounded=1024
    elif [ "$m" -le 2048 ]; then mem_rounded=2048
    elif [ "$m" -lt 3072 ]; then mem_rounded=3072
    elif [ "$m" -le 4096 ]; then mem_rounded=4096
    else mem_rounded=$(( (m + 128) / 256 * 256 ))
    fi
    mem_total=$t
    mem_avail=$a
    mem_free=$f
    mem_used=$((t - a))
    mem_buffcache=$((a - f))
    local p_scaled=0
    if [ "$t" -gt 0 ]; then
        p_scaled=$(( (mem_used * 1000) / t ))
    fi
    mem_p_whole=$((p_scaled / 10))
    mem_p_decimal=$((p_scaled % 10))
}

get_agh_config() {
    if [ ! -f "$AGH_INIT" ]; then
        return 1
    fi
    
    config_path=$(grep -o '\-c [^ ]*' "$AGH_INIT" | awk '{print $2}')
    if [ -n "$config_path" ] && [ -f "$config_path" ]; then
        printf "%s" "$config_path"
        return 0
    fi
    
    return 1
}

get_agh_workdir() {
    if [ ! -f "$AGH_INIT" ]; then
        return 1
    fi
    
    workdir=$(grep -o '\-w [^ ]*' "$AGH_INIT" | awk '{print $2}')
    if [ -n "$workdir" ] && [ -d "$workdir" ]; then
        printf "%s" "$workdir"
        return 0
    fi
    
    return 1
}

is_agh_running() {
    if ! pidof AdGuardHome >/dev/null 2>&1; then
        return 1
    fi

    if netstat -tunlp | grep -q "AdGuardHome"; then
        return 0
    fi

    return 1
}

# Apply a config/file change while PRESERVING AdGuardHome's run-state.
# Restarts AGH only if it was running before the change; a deliberately-stopped
# service is left stopped (no false "failed to start"). Reverts from backup only
# if AGH WAS running and fails to come back.
#   $1 = was_running (1/0)
#   $2 = backup file ("" to skip revert)
#   $3 = restore target ("" to skip revert)
#   $4 = success context message (optional)
#   $5 = note shown when AGH is stopped (optional; default = deferred-apply note; "-" suppresses)
# Returns 0 when AGH ends in its expected state, 1 on a genuine restart failure.
agh_apply_and_restart() {
    local was_running="$1" backup="$2" target="$3" ctx="$4"
    local stopped_note="${5:-AdGuardHome is stopped — changes will apply when it next starts.}"
    printf "\n"
    if [ "$was_running" != "1" ]; then
        print_success "${ctx:-Changes saved.}"
        [ "$stopped_note" = "-" ] || print_info "$stopped_note"
        return 0
    fi
    $AGH_INIT start >/dev/null 2>&1; sleep 2
    if is_agh_running; then
        print_success "${ctx:-Changes applied.}"
        print_success "AdGuardHome restarted successfully."
        return 0
    fi
    if [ -n "$backup" ] && [ -n "$target" ]; then
        print_error "AdGuardHome failed to start! Reverting..."
        cp "$target" "${target}.error.$(date +%Y%m%d%H%M%S)" 2>/dev/null
        cp "$backup" "$target"
        $AGH_INIT start >/dev/null 2>&1; sleep 2
        if is_agh_running; then
            print_warning "Restored last known good configuration."
            return 1
        fi
        print_error "Could not restart AdGuardHome even after reverting — check the configuration manually."
        return 1
    fi
    print_error "AdGuardHome failed to start — check the configuration manually."
    return 1
}

# Service run-state control (Start / Restart / Stop). Surfaced at the top of the
# Control Center because it is the most-used action and answers the STATUS line.
agh_service_control() {
    if is_agh_running; then
        printf "\n"
        print_warning "Service is RUNNING."
        printf "Disable, Restart, or Cancel? [D/R/0]: "; read -r confirm
        if [ "$confirm" = "d" ] || [ "$confirm" = "D" ]; then
            uci set adguardhome.config.enabled='0' && uci set adguardhome.config.dns_enabled='0' && uci commit adguardhome
            $AGH_INIT stop >/dev/null 2>&1; sleep 1; printf "\n"; print_success "Service Disabled"
        elif [ "$confirm" = "r" ] || [ "$confirm" = "R" ]; then
            $AGH_INIT restart >/dev/null 2>&1; sleep 2; printf "\n"; print_success "Service Restarted"
        fi
    else
        printf "\n"
        print_warning "Service is STOPPED."
        printf "Enable the service? [y/N]: "; read -r confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            uci set adguardhome.config.enabled='1' && uci set adguardhome.config.dns_enabled='1' && uci commit adguardhome
            $AGH_INIT enable >/dev/null 2>&1; sleep 1; $AGH_INIT start >/dev/null 2>&1; sleep 2; printf "\n"; print_success "Service Enabled"
        fi
    fi
    press_any_key
}

# Mask a colon-delimited MAC address, keeping only the last octet visible.
mask_mac() {
    printf '%s' "$1" | awk -F: '{out=""; for(i=1;i<NF;i++) out=out"**:"; print out $NF}'
}

# Mask a string, keeping only its last 2 characters visible (same length out
# as in, so masking never shifts column alignment).
mask_keep_tail() {
    local s="$1" len tail_part stars i=0
    len=${#s}
    [ "$len" -le 2 ] && { printf '%s' "$s"; return; }
    tail_part=$(printf '%s' "$s" | tail -c 2)
    stars=""
    while [ "$i" -lt "$((len - 2))" ]; do stars="${stars}*"; i=$((i + 1)); done
    printf '%s%s' "$stars" "$tail_part"
}

# -----------------------------
# Hardware Information Display
# -----------------------------
show_hardware_info() {
    page=1
    reveal_ids=0
    total_pages=4
    nav_choice=""
    
    clear
    hash -r
    if ! command -v lscpu >/dev/null 2>&1; then
        print_centered_header "Hardware Information"
        install_package lscpu "lscpu (enhanced CPU info)"
        clear
    fi

    if command -v uci >/dev/null 2>&1; then
        hostname=$(uci get system.@system[0].hostname 2>/dev/null)
    fi

    if [ -f /proc/gl-hw-info/device_mac ]; then
        mac=$(cat /proc/gl-hw-info/device_mac 2>/dev/null)
    fi

    if [ -f /proc/gl-hw-info/device_sn ]; then
        sn=$(cat /proc/gl-hw-info/device_sn 2>/dev/null)
    fi

    if [ -f /proc/gl-hw-info/device_ddns ]; then
        ddns=$(cat /proc/gl-hw-info/device_ddns 2>/dev/null)
    fi

    cpu_vendor_model=$(get_cpu_vendor_model)

    if command -v lscpu >/dev/null 2>&1; then
        cpu_cores=$(lscpu 2>/dev/null | grep "^CPU(s):" | awk '{print $2}')
    else
        cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
    fi

    cpu_freq=$(get_cpu_freq_mhz)

    # 1. Primary: GL.iNet Universal Hardware Info (4.x+ Firmware)
    if [ -f /proc/gl-hw-info/flash_size ]; then
        flash_raw=$(cat /proc/gl-hw-info/flash_size | sed 's/MiB/MB/')
        
        # Determine type: eMMC is usually > 1GB or specifically on Brume/Flint series
        # But we can be precise by checking for the block device existence
        if [ -b /dev/mmcblk0 ]; then
            type="eMMC"
        else
            type="NAND Flash"
        fi
        storage_info=$(printf "   Physical %s: %b%s%b\n" "$type" "${GREEN}" "$flash_raw" "${RESET}")
    
    # 2. Smart dmesg detection
    elif dmesg | grep -iE "nand|spi|mtd|mmc" | grep -iq "MiB"; then
        d_line=$(dmesg | grep -iE "nand|spi|mtd|mmc" | grep -i "MiB" | head -n 1)
        d_size=$(echo "$d_line" | grep -oE '[0-9]+ MiB' | sed 's/MiB/MB/')
        
        case "$(echo "$d_line" | tr 'A-Z' 'a-z')" in
            *nand*) type="NAND Flash" ;;
            *spi*)  type="SPI Flash" ;;
            *mmc*)  type="eMMC" ;;
            *)      type="Flash Storage" ;;
        esac
        storage_info=$(printf "   Physical %s: %b%s%b\n" "$type" "${GREEN}" "$d_size" "${RESET}")
    
    # 3. Check for eMMC
    elif [ -b /dev/mmcblk0 ]; then
        mmc_blocks=$(cat /sys/block/mmcblk0/size)
        # Convert 512-byte blocks to MB
        mmc_mb=$((mmc_blocks * 512 / 1024 / 1024))
        
        if [ "$mmc_mb" -ge 1000 ]; then
            mmc_gb=$(( (mmc_mb + 512) / 1024 ))
            storage_info=$(printf "   Physical eMMC: %b%d GB%b\n" "${GREEN}" "$mmc_gb" "${RESET}")
        else
            storage_info=$(printf "   Physical eMMC: %b%d MB%b\n" "${GREEN}" "$mmc_mb" "${RESET}")
        fi

    # 4. Fallback to MTD 
    elif [ -f /proc/mtd ]; then
        max_hex=$(awk 'NR>1 {print $2}' /proc/mtd | sort -r | head -n 1)
        
        if [ -n "$max_hex" ]; then
            # Convert Hex to Decimal bytes using shell printf
            flash_bytes=$(printf "%d" "0x$max_hex")
            flash_mb=$((flash_bytes / 1024 / 1024))
            
            if [ "$flash_mb" -ge 1000 ]; then
                flash_gb=$(( (flash_mb + 512) / 1024 ))
                storage_info=$(printf "   Physical NAND: %b%d GB%b\n" "${GREEN}" "$flash_gb" "${RESET}")
            else
                storage_info=$(printf "   Physical NAND: %b%d MB%b\n" "${GREEN}" "$flash_mb" "${RESET}")
            fi
        fi
    else
        storage_info=$(printf "   Physical Storage: %bUnknown%b\n" "${RED}" "${RESET}")
    fi

    refresh_counter=0

    while true; do
        if [ "$page" -eq 1 ]; then 
            printf '\033[H\033[J'
            printf '\033[?25l'
            if [ $((refresh_counter % 10)) -eq 0 ]; then
                fsdata=$(df -Ph | head -1 | sed 's/^/   /')
                fstmp=$(df -Ph | grep -E "^/dev/" | grep -v "tmpfs" | head -3 | sed 's/^/   /')
            fi
            else 
                clear
        fi
        print_centered_header "Hardware Information"
        printf " ──────────────────────────────────────────────────────────────────────────────\n"
        case $page in
            1)  
                printf " %b%bPage 1 of $total_pages: System Overview%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                if [ "$reveal_ids" -eq 1 ]; then
                    reveal_label="${YELLOW}[*] Hide${RESET}"; mac_disp="$mac"; sn_disp="$sn"
                else
                    reveal_label="${YELLOW}[*] Reveal${RESET}"; mac_disp=$(mask_mac "$mac"); sn_disp=$(mask_keep_tail "$sn")
                fi
                printf " %b%-38s%b%b\n" "${CYAN}" "System Information:" "${RESET}" "$reveal_label"

                [ -n "$hostname" ] && printf "   Model:    %b%-26s%b" "${GREEN}" "$hostname" "${RESET}"
                [ -n "$mac" ] && printf "Device MAC: %b%s%b" "${GREEN}" "$mac_disp" "${RESET}"
                printf "\n"

                if [ -f /etc/glversion ]; then
                    firmware=$(cat /etc/glversion 2>/dev/null)
                    [ -n "$firmware" ] && printf "   Firmware: %b%-26s%b" "${GREEN}" "$firmware" "${RESET}"
                fi

                [ -n "$sn" ] && printf "Device SN:  %b%s%b" "${GREEN}" "$sn_disp" "${RESET}"
                printf "\n"

                if [ -f /proc/uptime ]; then
                    read -r uptime_seconds rest < /proc/uptime
                    uptime_raw=${uptime_seconds%.*}
                    up_d=$((uptime_raw / 86400))
                    up_h=$(( (uptime_raw % 86400) / 3600 ))
                    up_m=$(( (uptime_raw % 3600) / 60 ))
                    up_s=$(( uptime_raw % 60 ))
                    time_string=$(printf "%02d:%02d:%02d" "$up_h" "$up_m" "$up_s")  
                    printf "   Uptime:   %b%d Day(s), %-13s%b" "${GREEN}" "$up_d" "$time_string" "${RESET}"
                else
                    printf "   Uptime:   %b%-23s%b" "${YELLOW}" "Unknown" "${RESET}"
                fi

                ddns_disp="$ddns"; [ "$reveal_ids" -ne 1 ] && ddns_disp=$(mask_keep_tail "$ddns")
                [ ! -z "$ddns" ] && printf "   Device ID:  %b%s%b" "${GREEN}" "$ddns_disp" "${RESET}"
                
                printf "\n\n"
                printf " %b\n" "${CYAN}CPU:${RESET}"
                printf "   Vendor/Model:    %b%s%b\n" "${GREEN}" "$cpu_vendor_model" "${RESET}"
                [ -n "$cpu_cores" ] && printf "   Cores:           %b%-16s%b" "${GREEN}" "$cpu_cores" "${RESET}"
                [ -n "$cpu_freq" ] && printf "   Frequency:  %b%.0f MHz%b" "${GREEN}" "$cpu_freq" "${RESET}"
                printf "\n"
                
                cpu_temp=$(get_cpu_temp)
                if [ "$cpu_temp" = "unknown" ]; then
                    printf "   CPU Temperature: %b%-17s%b\033[K" "${YELLOW}" "Unknown" "${RESET}"
                else
                    printf "   CPU Temperature: %b%-17s%b\033[K" "${GREEN}" "$cpu_temp°C" "${RESET}"
                fi
                
                fan_speed=$(get_fan_speed)
                [ -n "$fan_speed" ] && printf "   Fan Speed:  %b%s RPM%b\033[K" "${GREEN}" "$fan_speed" "${RESET}"
                printf "\n"

                read -r cpu_label user nice system idle iowait irq softirq rest < /proc/stat
                total=$((user + nice + system + idle + iowait + irq + softirq))
                diff_total=$((total - prev_total))
                diff_idle=$((idle - prev_idle))
                if [ "$diff_total" -gt 0 ]; then
                    cpu_percentage=$(( (diff_total - diff_idle) * 100 / diff_total ))
                fi
                prev_total=$total
                prev_idle=$idle
                [ -n "$cpu_percentage" ] && printf "   CPU Usage:       %b%-5s%b %-10s" "${GREEN}" "$cpu_percentage%" "${RESET}" ""
                
                read -r load_1 load_5 load_15 rest < /proc/loadavg
                cpu_load="${load_1}, ${load_5}, ${load_15}"
                [ -n "$cpu_load" ] && printf "   Load Avg:   %b%s%b\033[K" "${GREEN}" "$cpu_load" "${RESET}"
                printf "\n\n"

                printf " %b\n" "${CYAN}Memory:${RESET}"
                
                get_mem_stats
                mem_display=$(
                printf "   Soldered RAM:    %b%-9s %-6s%b" "${GREEN}" "$mem_rounded MB" "" "${RESET}"
                printf "   Free RAM:   %b%s%b\n" "${GREEN}" "$mem_free MB" "${RESET}"
                printf "   Total Usable:    %b%-9s %-6s%b" "${GREEN}" "$mem_total MB" "" "${RESET}"
                printf "   Used RAM:   %b%d MB (%d.%d%%)%b\n" "${GREEN}" "$mem_used" "$mem_p_whole" "$mem_p_decimal" "${RESET}"
                printf "   Available RAM:   %b%-9s %-6s%b" "${GREEN}" "$mem_avail MB" "" "${RESET}"
                printf "   Buff/Cache: %b%s MB%b\033[K\n" "${GREEN}" "$mem_buffcache" "${RESET}"
                )
                printf "%b\n" "$mem_display\n"

                printf " %b\n" "${CYAN}Storage:${RESET}"
                printf "$storage_info\n"
                
                printf "\n %b\n" "${CYAN}Filesystem Usage:${RESET}"
                printf "%b\n%b\n" "$fsdata" "$fstmp"
                ;;
                
            2)
                printf " %b%bPage 2 of $total_pages: Hardware Crypto Acceleration%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                # Capabilities come from CPU HWCAP feature flags, NOT /proc/crypto.
                # OpenSSL/OpenVPN (userspace) and kernel/Go WireGuard both pick their
                # accelerated paths from these flags; /proc/crypto is the wrong layer.
                feat_line=$(grep -m1 -iE '^(features|flags)[[:space:]]*:' /proc/cpuinfo 2>/dev/null)
                has_aes=0; has_pmull=0; has_sha1=0; has_sha2=0; has_sha512=0; has_simd=0
                case " $feat_line " in *" aes "*)    has_aes=1    ;; esac
                case " $feat_line " in *" pmull "*)  has_pmull=1  ;; esac
                case " $feat_line " in *" sha1 "*)   has_sha1=1   ;; esac
                case " $feat_line " in *" sha2 "*)   has_sha2=1   ;; esac
                case " $feat_line " in *" sha512 "*) has_sha512=1 ;; esac
                case " $feat_line " in *" asimd "*|*" neon "*) has_simd=1 ;; esac

                cpu_features=$(printf '%s\n' "$feat_line" | grep -oE 'aes|pmull|sha1|sha2|sha512|sha3|asimd|neon' | tr '\n' ' ')
                [ -n "$cpu_features" ] && printf " CPU Features: %b%s%b\n\n" "${GREEN}" "${cpu_features% }" "${RESET}"

                # Per-algorithm value color/text (AES-GCM auth = GHASH needs PMULL;
                # ChaCha20-Poly1305 needs SIMD/NEON).
                aes_c=$RED; aes_t=NO; [ "$has_aes" -eq 1 ]    && { aes_c=$GREEN; aes_t=YES; }
                gcm_c=$RED; gcm_t=NO; [ "$has_pmull" -eq 1 ]  && { gcm_c=$GREEN; gcm_t=YES; }
                cha_c=$RED; cha_t=NO; [ "$has_simd" -eq 1 ]   && { cha_c=$GREEN; cha_t=YES; }
                s1_c=$RED;  s1_t=NO;  [ "$has_sha1" -eq 1 ]   && { s1_c=$GREEN;  s1_t=YES; }
                s2_c=$RED;  s2_t=NO;  [ "$has_sha2" -eq 1 ]   && { s2_c=$GREEN;  s2_t=YES; }
                s5_c=$RED;  s5_t=NO;  [ "$has_sha512" -eq 1 ] && { s5_c=$GREEN;  s5_t=YES; }

                printf " %b\n" "${CYAN}Hardware-Accelerated Algorithms:${RESET}"
                printf "   %-43s%b%s%b\n" "AES (OpenVPN, IPsec, TLS):"                "$aes_c" "$aes_t" "${RESET}"
                printf "   %-43s%b%s%b\n" "AES-GCM / GHASH (OpenVPN AEAD):"           "$gcm_c" "$gcm_t" "${RESET}"
                printf "   %-43s%b%s%b\n" "ChaCha20-Poly1305 (WireGuard, Tailscale):" "$cha_c" "$cha_t" "${RESET}"
                printf "   %-43s%b%s%b\n" "SHA-1 (HMAC, legacy TLS):"                 "$s1_c"  "$s1_t"  "${RESET}"
                printf "   %-43s%b%s%b\n" "SHA-256 (TLS, HMAC, firmware integrity):"  "$s2_c"  "$s2_t"  "${RESET}"
                printf "   %-43s%b%s%b\n" "SHA-512 (TLS/HMAC):"                       "$s5_c"  "$s5_t"  "${RESET}"

                # VPN verdict: FULL / LIMITED / NONE.
                if [ "$has_simd" -eq 1 ]; then wg_v="${GREEN}FULL${RESET}"; else wg_v="${RED}NONE${RESET}"; fi
                if   [ "$has_aes" -eq 1 ] && [ "$has_pmull" -eq 1 ]; then ovpn_v="${GREEN}FULL${RESET}"
                elif [ "$has_aes" -eq 1 ];                          then ovpn_v="${YELLOW}LIMITED${RESET}"
                else                                                     ovpn_v="${RED}NONE${RESET}"
                fi

                printf "\n %b\n" "${CYAN}VPN Performance Assessment:${RESET}"
                printf "   %-43s%b\n" "WireGuard / Tailscale:" "$wg_v"
                printf "   %-43s%b\n" "OpenVPN:"               "$ovpn_v"
                ;;
                
            3)
                printf " %b%bPage 3 of $total_pages: Network Interfaces%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                # --- 1. Map Discovery ---
                port_map="|"
                sw_list=$(swconfig list 2>/dev/null)
                if [ -n "$sw_list" ] && [ -f "/etc/board.json" ]; then
                    lan_ports=$(grep -B 1 '"role": "lan"' /etc/board.json | grep '"num":' | grep -oE '[0-9]+' | tr '\n' ' ')
                    current_label=1
                    for p in $(echo "$lan_ports" | tr ' ' '\n' | sort -rn); do
                        port_map="${port_map}P${p}:LAN${current_label}|"
                        current_label=$((current_label + 1))
                    done
                    wan_p=$(grep -B 1 '"role": "wan"' /etc/board.json | grep '"num":' | grep -oE '[0-9]+' | head -n 1)
                    [ -n "$wan_p" ] && port_map="${port_map}P${wan_p}:WAN|"
                fi

                # --- 2. Logical Interfaces ---
                printf " %b\n" "${CYAN}Network Interfaces (Logical/DSA):${RESET}"
                ip -br link show 2>/dev/null | grep -E "eth|lan|wan|br-" | grep -v "wlan" | while read iface state rest; do
                    base_iface=$(echo "$iface" | cut -d'@' -f1 | cut -d. -f1)
                    speed_raw=$(cat "/sys/class/net/$base_iface/speed" 2>/dev/null)
                    
                    # Format Speed string safely
                    if [ "$speed_raw" = "10000" ]; then spd="10Gbps"
                    elif [ -n "$speed_raw" ] && [ "$speed_raw" != "-1" ]; then spd="${speed_raw}Mbps"
                    else spd=""; fi

                    # Use printf with variables outside the format string to prevent escape char errors
                    if [ -n "$spd" ] && [ "$speed_raw" -ge 5000 ]; then
                        printf "   %-17s: %b%-5s%b %-12s %b%s%b\n" "$iface" "${GREEN}" "$state" "${RESET}" "$spd" "${CYAN}" "[Internal Trunk]" "${RESET}"
                    elif [ -n "$spd" ]; then
                        printf "   %-17s: %b%-5s%b %-12s\n" "$iface" "${GREEN}" "$state" "${RESET}" "$spd"
                    else
                        printf "   %-17s: %b%-5s%b\n" "$iface" "${GREEN}" "$state" "${RESET}"
                    fi
                done
                
                # --- 3. Physical Switch ---
                if [ -n "$sw_list" ]; then
                    printf "\n %b\n" "${CYAN}Physical Chassis Ports:${RESET}"
                    echo "$sw_list" | awk '{print $2}' | while read sw; do
                        sw_model=$(echo "$sw_list" | grep "$sw" | awk -F' - ' '{print $2}')
                        p_count=$(swconfig dev "$sw" help 2>&1 | grep -oE "ports: [0-9]+" | awk '{print $2}')
                        
                        printf "   %b%s (%s)%b\n" "${YELLOW}" "$sw" "$sw_model" "${RESET}"
                        printf "     Map: [ "
                        for i in $(seq 0 $((p_count - 1))); do
                            if swconfig dev "$sw" port "$i" get link 2>/dev/null | grep -q "link:up"; then
                                printf "%b$i%b " "${GREEN}" "${RESET}"
                            else
                                printf "%b$i%b " "${RED}" "${RESET}"
                            fi
                        done
                        printf "]\n"

                        for i in $(seq 0 $((p_count - 1))); do
                            link_info=$(swconfig dev "$sw" port "$i" get link 2>/dev/null)
                            if echo "$link_info" | grep -q "link:up"; then
                                h_label=$(echo "$port_map" | grep -o "|P$i:[^|]*" | cut -d: -f2)
                                # Standardize speed labels (remove baseT for cleanliness)
                                spd=$(echo "$link_info" | grep -oE "[0-9]+(baseT|Mbps|Gbps)" | sed 's/baseT/Mbps/' | sed 's/10000Mbps/10Gbps/' || echo "UP")
                                
                                [ -z "$h_label" ] && h_label="Port $i"
                                full_label="$h_label (P$i)"

                                if [[ "$spd" == *"10G"* ]]; then
                                    printf "     └─ %b%-12s%b: %bUP%b    %-12s %b(Internal)%b\n" "${YELLOW}" "$full_label" "${RESET}" "${GREEN}" "${RESET}" "$spd" "${CYAN}" "${RESET}"
                                else
                                    printf "     └─ %b%-12s%b: %bUP%b    %-12s\n" "${YELLOW}" "$full_label" "${RESET}" "${GREEN}" "${RESET}" "$spd"
                                fi
                            fi
                        done
                    done
                    printf "\n %bLegend: %bGreen=UP %bRed=DOWN %bCyan=Internal %bYellow=Chassis Label%b\n" "${BOLD}" "${GREEN}" "${RED}" "${CYAN}" "${YELLOW}" "${RESET}"
                fi
                ;;
            4)
                printf " %b%bPage 4 of $total_pages: Wireless Interfaces%b\n\n" "${BOLD}" "${CYAN}" "${RESET}"
                
                radio_count=0
                # Use UCI as the source of truth for the Radio list
                for radio in $(uci show wireless | grep "=wifi-device" | cut -d. -f2 | cut -d= -f1); do
                    radio_count=$((radio_count + 1))
                    
                    # 1. Configuration from UCI
                    htmode=$(uci -q get wireless.${radio}.htmode)
                    band=$(uci -q get wireless.${radio}.band)
                    
                    # 2. Map Radio to Interface (ra0, rai0, etc.)
                    iface=""
                    for iface_sec in $(uci show wireless | grep "=wifi-iface" | cut -d. -f2 | cut -d= -f1); do
                        if [ "$(uci -q get wireless.${iface_sec}.device)" = "$radio" ]; then
                            iface=$(uci -q get wireless.${iface_sec}.ifname)
                            break
                        fi
                    done

                    # 3. Real-time Channel Extraction (The Fix)
                    current_chan="N/A"
                    if [ -n "$iface" ] && command -v iwinfo >/dev/null 2>&1; then
                        # This sed regex finds the word 'Channel' and grabs the number following it
                        current_chan=$(iwinfo "$iface" info 2>/dev/null | sed -n 's/.*Channel: \([0-9]*\).*/\1/p')
                    fi
                    
                    # Fallback to UCI config if live data is missing
                    if [ -z "$current_chan" ]; then
                        current_chan=$(uci -q get wireless.${radio}.channel)
                    fi

                    # 4. MIMO from the driver's *configured* antenna chainmask
                    #    (popcount of TX/RX): 0x3=2x2, 0x7=3x3, 0xf=4x4. This is
                    #    the operating config, not the chip's max ("Available").
                    #    N/A when the driver can't report it.
                    mimo="N/A"
                    if [ -n "$iface" ] && command -v iw >/dev/null 2>&1; then
                        phy=$(cat "/sys/class/net/$iface/phy80211/name" 2>/dev/null)
                        if [ -n "$phy" ]; then
                            ant=$(iw phy "$phy" info 2>/dev/null | grep -i 'Configured Antennas')
                            tx=$(printf '%s' "$ant" | sed -n 's/.*TX \(0x[0-9a-fA-F]*\).*/\1/p')
                            rx=$(printf '%s' "$ant" | sed -n 's/.*RX \(0x[0-9a-fA-F]*\).*/\1/p')
                            txn=$(popcount_hex "$tx"); rxn=$(popcount_hex "$rx")
                            [ "$txn" -gt 0 ] && [ "$rxn" -gt 0 ] && mimo="${txn}x${rxn}"
                        fi
                    fi

                    # 5. Band Display
                    case "$band" in
                        2g) band="2.4GHz" ;;
                        5g) band="5GHz" ;;
                        6g) band="6GHz" ;;
                    esac

                    printf " %bRadio %d: %s%b\n" "${CYAN}" "$radio_count" "$radio" "${RESET}"
                    printf "   Interface: %b%s%b\n" "${GREEN}" "${iface:-N/A}" "${RESET}"
                    printf "   Band:      %b%s%b\n" "${GREEN}" "$band" "${RESET}"
                    printf "   HT Mode:   %b%s%b\n" "${GREEN}" "${htmode:-N/A}" "${RESET}"
                    printf "   MIMO:      %b%s%b\n" "${GREEN}" "$mimo" "${RESET}"
                    printf "   Channel:   %b%s%b\n" "${GREEN}" "${current_chan:-Auto}" "${RESET}"
                    printf "\n"
                done
                ;;
        esac
        
        printf " ──────────────────────────────────────────────────────────────────────────────\n"
        printf " [P] Previous   "
        i=1
        while [ $i -le $total_pages ]; do
            if [ $i -eq $page ]; then
                printf "%b[%d]%b " "${BOLD}" "$i" "${RESET}"
            else
                printf "%b[%d]%b " "${GREY}" "$i" "${RESET}"
            fi
            i=$((i + 1))
        done
        printf "  [N] Next   [0] Main menu  "
        
        if [ "$page" -eq 1 ]; then
            nav_choice=""
            read -t 1 -n 1 nav_choice
            refresh_counter=$((refresh_counter + 1))
            [ "$refresh_counter" -gt 1000 ] && refresh_counter=0
            printf '\033[?25h'
        else
            nav_choice=$(read_single_char)
        fi
        
        case "$nav_choice" in
            p|P|b|B) [ $page -gt 1 ] && page=$((page - 1)) && clear;;
            n|N) [ $page -lt $total_pages ] && page=$((page + 1)) && clear;;
            1|2|3|4)
                if [ "$page" -ne "$nav_choice" ]; then
                    page=$nav_choice
                    clear
                fi
                ;;
            '*') reveal_ids=$((1 - reveal_ids)); clear ;;
            0) return ;;
        esac
    done
}

# -----------------------------
# AdGuardHome UI Updates Management
# -----------------------------
show_agh_ui_help() {
    clear
    print_centered_header "AdGuardHome UI Updates - Help"
    
    cat << 'HELPEOF'
What does this setting control?
───────────────────────────────
This option controls whether AdGuardHome is allowed to automatically check for and 
download new versions of its web interface (UI) directly from the AdGuard servers.

Two modes:
• ENABLED  → AdGuardHome can update its own UI automatically when a new version is released
• DISABLED → UI updates are blocked (the --no-check-update flag is added)

Why would you want to disable UI updates?
─────────────────────────────────────────
On GL.iNet routers, the recommended approach is often to **disable automatic UI updates** because:

• GL.iNet provides their own pre-packaged, tested version of AdGuardHome
• Auto-updating the UI can sometimes cause compatibility issues with GL.iNet's custom firmware
• It may overwrite GL.iNet-specific patches or branding
• Manual updates through GL.iNet's firmware or opkg are usually safer and better integrated

When should you enable UI updates?
──────────────────────────────────
• You are running a standalone/community-installed AdGuardHome (not the GL.iNet version)
• You want the very latest UI features and fixes as soon as they are released
• You are comfortable troubleshooting potential compatibility problems

Quick recommendation for most GL.iNet users:
• Keep UI Updates **DISABLED** (default safe choice on GL firmware)
• Only enable if you specifically need a newer UI feature and understand the risks

In this menu you can:
• Enable or disable UI Updates (adds/removes the --no-check-update flag).
• Enable or disable update persistence, so AdGuardHome survives firmware updates.

Note: Changing this setting restarts AdGuardHome automatically if already started. 
      Your filtering rules and stats are preserved.
HELPEOF
    
    press_any_key
}

manage_agh_ui_updates() {
    while true; do
        clear
        print_centered_header "AdGuardHome UI Updates Management"

        if is_agh_running; then
            agh_pid=$(pidof AdGuardHome)
        else
            agh_pid=""
        fi

        printf " %b\n" "${CYAN}CURRENT STATUS${RESET}"
        if [ -z "$agh_pid" ]; then
            printf "   Running: %b\n" "$_S_OFF"
        else
            printf "   Running: %b (PID: %s)\n" "$_S_ON" "$agh_pid"
        fi

        if grep -q -- "--no-check-update" "$AGH_INIT"; then
            printf "   UI Updates: %bDISABLED%b\n" "${RED}" "${RESET}"
        else
            printf "   UI Updates: %bENABLED%b\n" "${GREEN}" "${RESET}"
        fi

        up_conf="/etc/sysupgrade.conf"
        updates_persist="0"

        if [ -s "$up_conf" ]; then
            updates_persist="1"
            for entry in "/usr/bin/AdGuardHome" "/etc/init.d/adguardhome" "/etc/AdGuardHome/config.yaml"; do
                if ! grep -qFx "$entry" "$up_conf" 2>/dev/null; then
                    updates_persist="0"
                    break
                fi
            done
        fi

        if [ "$updates_persist" -eq "1" ]; then
            printf "   Update Persistence: %bENABLED%b\n\n" "${GREEN}" "${RESET}"
        else
            printf "   Update Persistence: %bDISABLED%b\n\n" "${RED}" "${RESET}"
        fi
        
        # Adaptive labels (Rule 4): offer only the valid transition for each state.
        local ui_label ui_action persist_label
        if grep -q -- "--no-check-update" "$AGH_INIT"; then
            ui_label="Enable UI Updates"; ui_action="enable"
        else
            ui_label="Disable UI Updates"; ui_action="disable"
        fi
        if [ "$updates_persist" -eq 1 ]; then
            persist_label="Disable update persistence across firmware updates"
        else
            persist_label="Enable update persistence across firmware updates"
        fi

        printf "%s  %s\n" "$N1" "$ui_label"
        printf "%s  %s\n" "$N2" "$persist_label"
        printf "%s  Back\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-2/0/?]: "
        read -r agh_choice
        printf "\n"

        case $agh_choice in
            1)
                agh_was_running=0; is_agh_running && agh_was_running=1
                if [ "$ui_action" = "enable" ]; then
                    if [ "$updates_persist" -eq 0 ]; then
                        print_warning "UI updates are currently set to not persist across firmware updates.\n   Enabling UI updates may cause compatibility issues during firmware\n   updates due to legacy binaries being reinstalled. Consider enabling\n   update persistence to avoid this problem.\n"
                    else
                        print_info "UI updates are currently set to persist across firmware updates."
                        printf "\n"
                    fi
                    printf "Proceed with changes? [y/N]: "; read -r confirm
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                    sed -i 's/--no-check-update[[:space:]]*//g' "$AGH_INIT"
                    agh_apply_and_restart "$agh_was_running" "" "" "UI updates enabled."
                else
                    printf "Disable UI updates? [y/N]: "; read -r confirm
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                    sed -i '/procd_set_param command/ s/ \(-c\|--config\)/ --no-check-update \1/' "$AGH_INIT"
                    agh_apply_and_restart "$agh_was_running" "" "" "UI updates disabled."
                fi
                press_any_key
                ;;
            2)
                if [ "$updates_persist" -eq 1 ]; then
                    printf "Disable update persistence across firmware updates? [y/N]: "; read -r confirm ; printf "\n"
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                    sed -i "/\/usr\/bin\/AdGuardHome/d" /etc/sysupgrade.conf
                    sed -i "/\/etc\/init.d\/adguardhome/d" /etc/sysupgrade.conf
                    sed -i "/\/etc\/AdGuardHome\/config.yaml/d" /etc/sysupgrade.conf
                    print_success "Update persistence disabled in $up_conf"
                else
                    printf "Enable update persistence across firmware updates? [y/N]: "; read -r confirm ; printf "\n"
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue
                    [ ! -f "$up_conf" ] && touch "$up_conf"
                    for entry in "/usr/bin/AdGuardHome" "/etc/init.d/adguardhome" "/etc/AdGuardHome/config.yaml"; do
                        grep -qFx "$entry" "$up_conf" || echo "$entry" >> "$up_conf"
                    done
                    print_success "Update persistence enabled in $up_conf"
                fi
                press_any_key
                ;;
            \?|h|H|❓)
                show_agh_ui_help
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# AdGuardHome Storage Management
# -----------------------------
show_agh_storage_help() {
    clear
    print_centered_header "AdGuardHome Filter Space Limit - Help"
    
    cat << 'HELPEOF'
AdGuardHome Filter Space Limit – BE3600 & Similar Models

Why the limit exists
────────────────────
On 512MB RAM routers (MT3600BE, some newer GL models), GL.iNet creates a 10MB file 
and mounts it as /etc/AdGuardHome/data/filters. This caps filter cache space to 
prevent AdGuardHome from consuming too much RAM and crashing the router.

Removing this limit lets you use bigger blocklists (e.g. HaGeZi Pro++, multi-list setups), 
but significantly increases RAM usage when filters are loaded/updated.

Risks if you remove it without mitigation
─────────────────────────────────────────
• High RAM pressure → router slowdown, OOM killer, or crashes
• Especially bad with many clients, VPN, or heavy filtering

Strong recommendation
─────────────────────
Enable **zram swap** first (Manage Zram Swap → Install & Enable).  
Zram gives fast compressed swap in RAM, greatly reduces memory pressure, 
and is safe for most GL.iNet 512MB devices.

Only remove the 10MB limit after zram is active.
HELPEOF
    
    press_any_key
}

manage_agh_storage() {
    while true; do
        clear
        print_centered_header "AdGuardHome Storage Management"

        AGH_WORKDIR=$(get_agh_workdir)
        if [ -z "$AGH_WORKDIR" ]; then
            print_error "Could not find AdGuardHome working directory"
            press_any_key
            return
        fi
        
        printf " %b\n" "${CYAN}STORAGE STATUS${RESET}"
        printf "   Working Directory: %b%s%b\n" "${GREEN}" "$AGH_WORKDIR" "${RESET}"

        sub_section_shown=0
         if [ -d "$AGH_WORKDIR/data" ]; then
            sub_section_shown=1
            printf "\n %b\n" "${CYAN}$AGH_WORKDIR/data Directory:${RESET}"
            df -Ph "$AGH_WORKDIR/data" 2>/dev/null | tail -1 | awk '{printf "   Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
        fi

        if [ -d "$AGH_WORKDIR/data/filters" ]; then
            sub_section_shown=1
            printf "\n %b\n" "${CYAN}$AGH_WORKDIR/data/filters Directory:${RESET}"
            df -Ph "$AGH_WORKDIR/data/filters" 2>/dev/null | tail -1 | awk '{printf "   Total: %s | Used: %s | Free: %s\n", $2, $3, $4}'
        fi

        [ "$sub_section_shown" -eq 1 ] && printf "\n"
        limit_active=0
        if grep -q "$AGH_WORKDIR/data/filters" /proc/mounts; then
            limit_active=1
            # Calculate actual size from the mount point
            current_limit=$(df -Pm "$AGH_WORKDIR/data/filters" | tail -1 | awk '{print $2}')
            printf "   Filter Space Limit: %bACTIVE (%sMB)%b\n" "${YELLOW}" "$current_limit" "${RESET}"
        else
            printf "   Filter Space Limit: %bINACTIVE%b\n" "${GREEN}" "${RESET}"
        fi
        
        printf "\n%s  Remove Filter Space Limitation\n" "$N1"
        printf "%s  Re-enable Filter Space Limitation\n" "$N2"
        printf "%s  Back\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-2/0/?]: "
        read -r storage_choice
        printf "\n"

        local exec_pattern="^[[:space:]]*mount_filter_img[[:space:]]+"
        local comment_pattern="^[[:space:]]*#[[:space:]]*mount_filter_img[[:space:]]+"
        
        case $storage_choice in
            1)
                if [ "$limit_active" -eq 0 ]; then
                    print_warning "Filter space limitation is already INACTIVE on the system."
                    press_any_key; continue
                fi

                if ! grep -qE "$exec_pattern" "$AGH_INIT"; then
                    print_error "Could not find a feature call to disable."
                    press_any_key; continue
                fi
                
                cat << 'WARNEOF'
GL.iNet (MT3600BE & similar models) limits AdGuardHome filter cache to 10MB 
by creating a small tmpfs/loop-mounted partition at /etc/AdGuardHome/data/filters.

Removing this limit allows larger/more filter lists, but may cause high RAM usage 
and instability on 512MB devices when filters are big or many are enabled.
WARNEOF
                
                if ! swapon -s 2>/dev/null | grep -q zram; then
                    printf "\n"
                    print_warning "WARNING: Zram swap is NOT enabled!"
                    printf "\n"
                    print_info "It is strongly recommended to enable zram swap before adding aditional filter lists."
                fi
                
                printf "%b" "${YELLOW}Remove the 10MB limit anyway? [y/N]: ${RESET}"
                read -r confirm
                printf "\n"
                if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                    printf "Operation cancelled.\n"
                    press_any_key
                    continue
                fi
                
                if is_agh_running; then
                    agh_pid=$(pidof AdGuardHome)
                    $AGH_INIT stop >/dev/null 2>&1; sleep 1
                else
                    agh_pid=""
                fi

                loop_dev=$(mount | grep "$AGH_WORKDIR/data/filters" | awk '{print $1}')
                if [ -n "$loop_dev" ]; then
                    umount "$loop_dev" 2>/dev/null
                    print_success "Unmounted filter partition"
                fi
                
                if [ -f "$AGH_WORKDIR/data.img" ]; then
                    rm -f "$AGH_WORKDIR/data.img"
                    print_success "Removed data.img file"
                fi
                
                sed -i "s|^\([[:space:]]*\)\(mount_filter_img[[:space:]]\)|\1# \2|" "$AGH_INIT"
                print_success "Disabled execution call in init script"
                
                if [ -n "$agh_pid" ]; then
                    $AGH_INIT start >/dev/null 2>&1; sleep 2
                    if is_agh_running; then
                        print_success "AdGuardHome restarted successfully"
                        print_success "Filter space limit removed!"
                    else
                        print_error "Failed to restart AdGuardHome"
                    fi
                fi
                
                press_any_key
                ;;
            2)
                if [ "$limit_active" -eq 1 ]; then
                    print_warning "Filter space limitation is already ACTIVE."
                    press_any_key; continue
                fi
                
                if ! grep -q "mount_filter_img" "$AGH_INIT"; then
                    print_warning "Filter space limitation feature is not supported on this device/firmware."
                    press_any_key
                    continue
                fi

                if grep -qE "$exec_pattern" "$AGH_INIT"; then
                    print_warning "Filter space limitation is already enabled or not supported on this device/firmware."
                    press_any_key; continue
                fi

                if ! grep -qE "$comment_pattern" "$AGH_INIT"; then
                    print_error "Could not find a feature call to re-enable."
                    press_any_key; continue
                fi
                
                if is_agh_running; then
                    agh_pid=$(pidof AdGuardHome)
                    $AGH_INIT stop >/dev/null 2>&1; sleep 1
                else
                    agh_pid=""
                fi
                
                sed -i "s|^\([[:space:]]*\)#[[:space:]]*\(mount_filter_img[[:space:]]\)|\1\2|" "$AGH_INIT"
                print_success "Re-enabled execution call in init script"
                
                if [ -n "$agh_pid" ]; then
                    $AGH_INIT start >/dev/null 2>&1; sleep 2
                    if is_agh_running; then
                        print_success "AdGuardHome restarted successfully"
                        print_success "Filter space limit re-enabled!"
                    else
                        print_error "Failed to restart AdGuardHome"
                    fi
                fi
                
                press_any_key
                ;;
            \?|h|H|❓)
                show_agh_storage_help
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# AdGuardHome Lists Management
# -----------------------------
show_agh_lists_help() {
    clear
    print_centered_header "AdGuardHome Lists - Help"
    
    cat << 'HELPEOF'
What are these lists?
────────────────────────────────────────────────────────────────────────
This option installs custom DNS filter lists for AdGuardHome to enhance 
ad blocking and streaming compatibility:

- **Phantasm22's Blocklist**:
  Blocks Amazon Echo Show ads. Derived from HaGeZi's Pro++ for broad 
  protection, curated for GL.iNet performance. (Auto-updates, GPL-3.0).
  URL: https://github.com/phantasm22/AdGuardHome-Lists/blocklist.txt

- **Phantasm22's CDN Allow List**:
  Unblocks domains for Roku, Apple TV, NBC, Peacock, Hulu, Disney+, 
  YouTube, Prime, Max, and more. Prevents false positives.
  URL: https://github.com/phantasm22/AdGuardHome-Lists/allowlist.txt

- **Phantasm22's Apps and User Flow Allow List**:
  Unblocks domains necessary for common day to day use like clicking on
  a WSJ or Home Depot link or using other common apps.
  URL: https://github.com/phantasm22/AdGuardHome-Lists/allowlist2.txt

- **HaGeZi's Pro++ Blocklist**:
  Aggressive protection against ads, tracking, phishing, and malware.
  Part of the Multi series (230k+ entries). Strict protection; 
  best for users comfortable whitelisting if rare breaks occur.

Why HaGeZi's Pro++ as the default base?
────────────────────────────────────────────────────────────────────────
It provides comprehensive protection and balances aggressive blocking 
with usability. Users report ~2x more blocks than alternatives like 
OISD with minimal false positives. It is highly regarded on Reddit, 
NextDNS, and Pi-hole forums for privacy gains.

These lists auto-update in AdGuardHome. Install for enhanced blocking—
monitor for streaming breaks and whitelist via the AdGuardHome UI.
HELPEOF
    
    press_any_key
}

manage_agh_lists() {
    LIST_REGISTRY="1|Phantasm22's Blocklist|Blocklist|https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/blocklist.txt
2|HaGeZi's Pro++ Blocklist|Blocklist|https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/pro.plus.txt
3|Phantasm22's CDN Allow List|Allowlist|https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/allowlist.txt
4|Phantasm22's Apps and User Flow Allow List|Allowlist|https://raw.githubusercontent.com/phantasm22/AdGuardHome-Lists/refs/heads/main/allowlist2.txt"

    while true; do
        clear
        print_centered_header "AdGuardHome Lists Manager"

        AGH_CONFIG=$(get_agh_config)
        [ -z "$AGH_CONFIG" ] && { print_error "Config not found"; press_any_key; return; }
        
        LISTS_DATA=$(mktemp -t agh_data.XXXXXX)

        # ---------------------------------------------------------
        # 1. PARSING (Fixed for + signs and quotes)
        # ---------------------------------------------------------
        while IFS='|' read -r r_id r_name r_type r_url; do
			status_val=$(awk -v n="$r_name" '
                BEGIN { RS = "[[:space:]]*- "; FS = "\n" }
                # index() does a literal string search. It ignores plus signs and quotes.
                index($0, "name: " n) || index($0, "name: \"" n "\"") {
                    if ($0 ~ "enabled: true") { print "true"; exit }
                    if ($0 ~ "enabled: false") { print "false"; exit }
                }
			' "$AGH_CONFIG")
    		status=0; [ "$status_val" = "false" ] && status=1; [ "$status_val" = "true" ] && status=2
    		printf "%s|%s|%s|%s|1|1|%s\n" "$r_id" "$r_name" "$r_type" "$status" "$r_url" >> "$LISTS_DATA"
done <<EOF
$LIST_REGISTRY
EOF

        local next_idx=$(($(echo "$LIST_REGISTRY" | wc -l) + 1))
        awk '
            /^filters:/ || /^whitelist_filters:/ {in_sec=1; type=($1=="filters:"?"Blocklist":"Allowlist")}
            /^[a-z_]+:/ && !/^filters:/ && !/^whitelist_filters:/ {in_sec=0}
            in_sec && /name: / {
                gsub(/^[[:space:]]*name:[[:space:]]*/, "");
                gsub(/^"|",?$/, "");
                if ($0 != "") print type "|" $0
            }
        ' "$AGH_CONFIG" | while IFS='|' read -r c_type c_name; do
			if ! grep -q "|$c_name|" "$LISTS_DATA"; then
                status_val=$(awk -v n="$c_name" '
                    BEGIN { RS = "[[:space:]]*- "; FS = "\n" } 
                    $0 ~ "name: [\" ]*" n "[\" ]*" {
                        if ($0 ~ "enabled: true") { print "true"; exit }
                        if ($0 ~ "enabled: false") { print "false"; exit }
                    }
                ' "$AGH_CONFIG")
				status=1; [ "$status_val" = "true" ] && status=2
                printf "%s|%s|%s|%s|0|0|CUSTOM\n" "$next_idx" "$c_name" "$c_type" "$status" >> "$LISTS_DATA"
                next_idx=$((next_idx + 1))
            fi
        done

        # ---------------------------------------------------------
        # 2. UI LOOP
        # ---------------------------------------------------------
        while true; do
            clear
            print_centered_header "AdGuardHome Lists Manager"
            printf " %-5s %-12s %-50s %-20s\n" "Sel." "Type" "Name" "Status"
            printf " ──────────────────────────────────────────────────────────────────────────────────────────\n"
            while IFS='|' read -r idx name type stat sel rec url; do
                s_box="[ ]  "; [ "$sel" -eq 1 ] && s_box="[✓]  "
                case "$stat" in 0) s_txt="Missing" ;; 1) s_txt="Installed (inactive)" ;; 2) s_txt="Installed (active)" ;; esac
                label="$idx. $name"; [ "$rec" -eq 1 ] && label="$label ★"
                [ "$rec" -eq 1 ] && label=$(printf "%-52s" "$label") || label=$(printf "%-50s" "$label")
                printf " %-5s %-12s %-50s %-20s\n" "$s_box" "$type" "$label" "$s_txt"
            done < "$LISTS_DATA"
            printf " ──────────────────────────────────────────────────────────────────────────────────────────\n"
            printf " [A] All   [N] None   [#] Toggle   [C] Confirm   [0] Cancel   [?] Help\n"
            lists_count=$(wc -l < "$LISTS_DATA" 2>/dev/null | tr -dc '0-9')
            printf "\n Choose [%s/A/N/C/0/?]: " "$(picker_range "$lists_count")"
            read -r input

            case "$input" in
                a|A) sed -i 's/\(.*|.*|.*|.*|\)0\(|.*|.*\)/\11\2/' "$LISTS_DATA" ;;
                n|N) sed -i 's/\(.*|.*|.*|.*|\)1\(|.*|.*\)/\10\2/' "$LISTS_DATA" ;;
                [0-9]*)
                    if [ "$input" != "0" ]; then
                        num="$input"
                        awk -F'|' -v t="$num" 'BEGIN{OFS="|"} {if($1==t) $5=($5==1?0:1); print}' "$LISTS_DATA" > "$LISTS_DATA.tmp" && mv "$LISTS_DATA.tmp" "$LISTS_DATA"
                    else
                        # If it is exactly 0, handle it as the cancel command
                        rm -f "$LISTS_DATA"; return
                    fi
                    ;;
                c|C)
                    to_install=$(awk -F'|' '$5==1 && $4==0' "$LISTS_DATA")
                    to_remove=$(awk -F'|' '$5==0 && $4!=0' "$LISTS_DATA")
                    
					if [ -z "$to_install" ] && [ -z "$to_remove" ]; then
                        print_warning "No changes to apply (Selection matches current status)"
                        sleep 2
                        break 
                    fi

					# 3. CONFIRMATION SCREEN
					clear
                    print_centered_header "Confirm List Changes"
                    [ -n "$to_install" ] && { printf "${GREEN}TO BE INSTALLED:${RESET}\n"; echo "$to_install" | cut -d'|' -f2 | sed 's/^/  + /'; }
                    [ -n "$to_remove" ] && { printf "\n${RED}TO BE REMOVED:${RESET}\n"; echo "$to_remove" | cut -d'|' -f2 | sed 's/^/  - /'; }
                    
                    printf "\nProceed with changes? [y/N]: "; read -r confirm
                    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && break

                    # 4. BACKUP CREATION
                    stamp=$(date +%Y%m%d%H%M%S)
                    BACKUP_FILE="${AGH_CONFIG}.backup.${stamp}"
                    cp "$AGH_CONFIG" "$BACKUP_FILE"

                    agh_was_running=0; is_agh_running && agh_was_running=1
                    [ "$agh_was_running" -eq 1 ] && { $AGH_INIT stop >/dev/null 2>&1; sleep 1; }

                   	# 5. REMOVAL (Your logic, hardened for line order)
					echo "$to_remove" | while IFS='|' read -r i n t s sel rec u; do
						
						# 1. Find the exact line number of the name escaping special chars (e.g. +) and optional quotes
						n=$(echo "$n" | sed 's/+/\\+/g; s/\./\\./g')
						name_line=$(grep -nE "name: \"?$n\"?" "$AGH_CONFIG" | cut -d: -f1 | head -n1)
						
						if [ -n "$name_line" ]; then
							# 2. Find the nearest "- enabled:" ABOVE that name line
							# This ensures we hit the start of THE SPECIFIC block
							start_del=$(sed -n "1,${name_line}p" "$AGH_CONFIG" | grep -n "enabled:" | tail -n1 | cut -d: -f1)
							
							# 3. Delete 4 lines starting from that "- enabled" line
							if [ -n "$start_del" ]; then
								sed -i "${start_del},$((start_del + 3))d" "$AGH_CONFIG"
							fi
						fi
					done

                    # 6. INSTALLATION
					if [ -n "$to_install" ]; then
						count=0
						echo "$to_install" | while IFS='|' read -r i n t s sel rec u; do
							[ -z "$u" ] || [ "$u" = "CUSTOM" ] && continue
							
							ts="$(( $(date +%s) - 1769040000 ))$count"
							
							new_block="- enabled: true\\
url: $u\\
name: \"$n\"\\
id: $ts"

							target_head="filters:"
							[ "$t" = "Allowlist" ] && target_head="whitelist_filters:"

							# Remove empty array brackets if they exist
							sed -i "s/^$target_head \[\]/$target_head/" "$AGH_CONFIG"
							
							# Append the new block directly after the header line
							sed -i "/^$target_head/a $new_block" "$AGH_CONFIG"

							# Force 2 spaces for dash, 4 for children
							sed -i "s/^- enabled:/  - enabled:/" "$AGH_CONFIG"
							sed -i "s/^url:/    url:/" "$AGH_CONFIG"
							sed -i "s/^name:/    name:/" "$AGH_CONFIG"
							sed -i "s/^id:/    id:/" "$AGH_CONFIG"
							
							count=$((count + 1))
						done
					fi

					# 7. CLEANUP (Strict Header Matching)
					for head in "filters" "whitelist_filters"; do
						# Match the header only at the start of a line to avoid 'filtering_enabled' etc.
						if grep -qE "^$head:|^  $head:" "$AGH_CONFIG"; then
							# Check the line immediately following the specific header
							# We use -A 1 to see the 'After' line
							next_line=$(grep -A 1 -E "^$head:|^  $head:" "$AGH_CONFIG" | tail -n 1)
							
							# If the next line isn't a list item (- enabled), the section is empty or broken
							if ! echo "$next_line" | grep -q "\- enabled:"; then
								# Force the header to empty array and ensure no hanging fragments remain
								sed -i "/^$head:/ s/.*/$head: []/" "$AGH_CONFIG"
								sed -i "/^  $head:/ s/.*/  $head: []/" "$AGH_CONFIG"
							fi
						fi
					done

                    # 8. APPLY: restart only if AGH was running (preserve run-state)
                    if agh_apply_and_restart "$agh_was_running" "$BACKUP_FILE" "$AGH_CONFIG" "Changes applied."; then
                        print_success "Backup file created: $(basename "$BACKUP_FILE")"
                    fi
                    press_any_key; rm -f "$LISTS_DATA"; break 1
                    ;;
                \?|h|H|❓)
                    show_agh_lists_help ;;
                *) print_error "Invalid option"; sleep 1 ;;
            esac
        done
    done
}

# -----------------------------
# AdGuardHome Direct Access Management
# -----------------------------

show_agh_direct_help() {
    clear
    print_centered_header "Direct Access Help"
    cat << 'HELPEOF'

1. DIRECT ACCESS:
   - ON: Access AGH at http://192.168.8.1:3000 bypassing GL.iNet UI.
   - OFF: Port 3000 redirects to Port 80 (Standard GL.iNet Login).

2. WEB UI CREDENTIALS:
   - Uses 'apache' to generate a secure Bcrypt hash.
   - This is necessary to prevent open access to your dashboard
     once you bypass the GL.iNet login gatekeeper.

3. REMOVE PASSWORD:
   - Sets 'users: []' in the config.yaml. 
   - Useful if you want the dashboard to be entirely open on LAN.

NOTES:
I.  BACKUPS: Automatically creates .backup.YYYYMMDDHHMMSS for
    both the /etc/init.d script and the config.yaml.
II. PERSISTENCE: GL.iNet firmware updates will overwrite the
    init script. Simply run Option 1 again to restore access.

HELPEOF
    press_any_key
}

update_agh_credentials() {
    clear
    print_centered_header "Set Web UI Credentials"
    if [ "$PASS_STATUS" = "✅" ]; then
        print_warning "A password is already set. Proceeding will overwrite it."
        printf "\n"
    else 
        print_warning "No password currently set. This will create a new username and password."
    fi
    printf "Set Web UI credentials? [y/N]: "
    read -r confirm
    printf "\n"
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return

    # Dependency Check
    if ! command -v htpasswd >/dev/null 2>&1; then
        install_package apache "apache utils" || { press_any_key; return; }
    fi

    # Input capture — username (suggest root; blank offers retry/cancel)
    while true; do
        printf "Enter Username (e.g. root): "
        read -r user_name
        [ -n "$user_name" ] && break
        printf "\n"
        print_warning "Username cannot be blank."
        printf "Try again? [Y/n]: "; read -r _u_retry; printf "\n"
        case "$_u_retry" in n|N) print_info "Operation cancelled."; return ;; esac
    done

    # Password with confirmation; blank or mismatch offers retry/cancel
    while true; do
        user_pass=$(get_password "Enter Password: ")
        if [ -z "$user_pass" ]; then
            printf "\n"
            print_warning "Password cannot be blank."
            printf "Try again? [Y/n]: "; read -r _p_retry; printf "\n"
            case "$_p_retry" in n|N) print_info "Operation cancelled."; return ;; esac
            continue
        fi
        user_pass_conf=$(get_password "Confirm Password: ")
        if [ "$user_pass" = "$user_pass_conf" ]; then
            break
        fi
        printf "\n"
        print_warning "Passwords do not match."
        printf "Try again? [Y/n]: "; read -r _p_retry; printf "\n"
        case "$_p_retry" in n|N) print_info "Operation cancelled."; return ;; esac
    done

    BCRYPT_HASH=$(htpasswd -n -B -b "$user_name" "$user_pass" | cut -d: -f2)

    

    # --- VALIDATION LOGIC ---
    [ -z "$TIMESTAMP" ] && TIMESTAMP=$(date +%Y%m%d%H%M%S)
    BACKUP_FILE="$AGH_CONF.backup.$TIMESTAMP"
    cp "$AGH_CONF" "$BACKUP_FILE"

    # Validate structure BEFORE touching the service (reads only)
    local ESC_HASH=$(echo "$BCRYPT_HASH" | sed 's/[&]/\\&/g')
    local mode=""
    if grep -q "users: \[\]" "$AGH_CONF"; then
        mode="empty"
    elif grep -q "^users:" "$AGH_CONF"; then
        line_num=$(grep -n "^users:" "$AGH_CONF" | cut -d: -f1)
        check_name=$(sed -n "$((line_num+1))p" "$AGH_CONF")
        check_pass=$(sed -n "$((line_num+2))p" "$AGH_CONF")
        if echo "$check_name" | grep -q " - name:" && echo "$check_pass" | grep -q "password:"; then
            mode="block"
        else
            print_error "Unexpected YAML structure detected below 'users:' line."
            print_warning "Manual edit required to avoid corrupting config."
            press_any_key; return
        fi
    else
        print_error "Could not find 'users:' key in $AGH_CONF"
        press_any_key; return
    fi

    # Commit: stop (only if running), edit, then restart-if-was-running
    agh_was_running=0; is_agh_running && agh_was_running=1
    [ "$agh_was_running" -eq 1 ] && { $AGH_INIT stop >/dev/null 2>&1; sleep 1; }

    if [ "$mode" = "empty" ]; then
        sed -i "\|users: \[\]|c\users:\n  - name: $user_name\n    password: \"$ESC_HASH\"" "$AGH_CONF"
    else
        sed -i "$((line_num+1))s|- name: .*|- name: $user_name|" "$AGH_CONF"
        sed -i "$((line_num+2))s|password: .*|password: \"$ESC_HASH\"|" "$AGH_CONF"
    fi

    if agh_apply_and_restart "$agh_was_running" "$BACKUP_FILE" "$AGH_CONF" "Credentials updated."; then
        print_success "Backup created: $(basename "$BACKUP_FILE")"
    fi
    press_any_key
}

manage_agh_direct_access() {
    while true; do
        clear
        print_centered_header "AdGuardHome Direct Access"
        lan_ipaddr=$(get_lan_ip)
        AGH_CONF=$(get_agh_config)
        DIRECT_STATUS="❌"; direct_disp="$_S_OFF"
        grep -q -- "--glinet" "$AGH_INIT" || { DIRECT_STATUS="✅"; direct_disp="$_S_ON"; }

        PASS_STATUS="✅"; pass_disp="$_S_ON"
        grep -q "users: \[\]" "$AGH_CONF" && { PASS_STATUS="❌"; pass_disp="$_S_OFF"; }

        printf " ${CYAN}STATUS${RESET}\n"
        printf "   Direct Web UI Access: %b\n" "$direct_disp"
        printf "   Web UI Username / Password Set: %b\n\n" "$pass_disp"
        local direct_label="Enable Direct Access (Switch to Standalone)"
        [ "$DIRECT_STATUS" = "✅" ] && direct_label="Disable Direct Access (Switch to Integrated)"
        printf "%s  %s\n" "$N1" "$direct_label"
        printf "%s  Add/Update Web UI Credentials (Username/Password)\n" "$N2"
        printf "%s  Remove Web UI Password (Set to Open Access)\n" "$N3"
        printf "%s  Back\n" "$N0"
        printf "%s Help\n" "$NQ"
        
        printf "\nChoose [1-3/0/?]: "
        read -r direct_choice
        TIMESTAMP=$(date +%Y%m%d%H%M%S)

        case $direct_choice in
            1)
                clear
                if [ "$DIRECT_STATUS" = "❌" ]; then
                    print_centered_header "Enable AdGuardHome Direct Access"
                    print_warning "AdGuardHome direct access bypasses GL.iNet Web UI security."
                    printf "\n"
                    print_warning "If no password is set, and you bypass setting a password, the UI will be ${BOLD}UNSECURED.${RESET}"
                    printf "\n"
                    print_info "Once enabled, you can access AdGuardHome Web UI at ${BOLD}http://$lan_ipaddr:3000${RESET}"
                    printf "Enable Direct Access? [y/N]: "
                else
                    print_centered_header "Disable AdGuardHome Direct Access"
                    print_warning "AdGuardHome direct Web UI access via http://$lan_ipaddr:3000 will be disabled."
                    printf "\n"
                    print_warning "Any passwords set will remain but will be bypassed."
                    printf "\n"
                    print_info "Once disabled, you can access the AdGuardHome Web UI at: ${BOLD}http://$lan_ipaddr/${RESET}"
                    printf "Disable Direct Access? [y/N]: "
                fi
                read -r confirm
                [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue

                cp "$AGH_INIT" "$AGH_INIT.backup.$TIMESTAMP"
                agh_was_running=0; is_agh_running && agh_was_running=1

                if [ "$DIRECT_STATUS" = "✅" ]; then
                    # Turning Direct Access OFF (Integrated Mode)
                    sed -i 's/AdGuardHome /AdGuardHome --glinet /g' "$AGH_INIT"
                    agh_apply_and_restart "$agh_was_running" "$AGH_INIT.backup.$TIMESTAMP" "$AGH_INIT" "Direct Access disabled (Integrated Mode)."
                    press_any_key
                else
                    # Turning Direct Access ON (Standalone Mode)
                    sed -i 's/ --glinet//g' "$AGH_INIT"
                    if [ "$PASS_STATUS" = "❌" ]; then
                        printf "\n"
                        print_warning "No username/password has been set for AdGuardHome."
                        printf "Would you like to set one now? [Y/n]: "
                        read -r set_pass
                        printf "\n"
                        if [ "$set_pass" != "n" ] && [ "$set_pass" != "N" ]; then
                            update_agh_credentials && continue
                        else
                            print_warning "AdGuardHome Web UI will be UNSECURED (no password)."
                            agh_apply_and_restart "$agh_was_running" "$AGH_INIT.backup.$TIMESTAMP" "$AGH_INIT" "Direct Access enabled (Standalone Mode)."
                            press_any_key
                        fi
                    else
                        agh_apply_and_restart "$agh_was_running" "$AGH_INIT.backup.$TIMESTAMP" "$AGH_INIT" "Direct Access enabled (Standalone Mode)."
                        press_any_key
                    fi
                fi
                ;;

            2) update_agh_credentials;;  

            3)
                clear
                print_centered_header "Remove AdGuardHome Web UI Password"
                if [ "$PASS_STATUS" = "❌" ]; then
                    print_warning "No password currently exists."
                    press_any_key; continue
                fi
                if [ "$DIRECT_STATUS" = "✅" ]; then
                    print_warning "This removes the Web UI credentials, leaving AdGuardHome OPEN (unsecured)."
                else
                    print_warning "This removes the AdGuardHome Web UI credentials."
                fi
                printf "Remove credentials? [y/N]: "
                read -r confirm
                [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && continue

                BACKUP_FILE="$AGH_CONF.backup.$TIMESTAMP"
                cp "$AGH_CONF" "$BACKUP_FILE"
                agh_was_running=0; is_agh_running && agh_was_running=1
                [ "$agh_was_running" -eq 1 ] && { $AGH_INIT stop >/dev/null 2>&1; sleep 1; }

                # Find users: block and replace with users: []
                line_num=$(grep -n "^users:" "$AGH_CONF" | cut -d: -f1)
                # Delete the next two lines (- name and password) then change users: to users: []
                if ! grep -q "users: \[\]" "$AGH_CONF"; then
                    sed -i "$((line_num+1)),$((line_num+2))d" "$AGH_CONF"
                fi
                sed -i "${line_num}s/users:.*/users: []/" "$AGH_CONF"

                agh_apply_and_restart "$agh_was_running" "$BACKUP_FILE" "$AGH_CONF" "Web UI password removed."
                press_any_key
                ;;

            0) return ;;
            \?|h|H|❓) show_agh_direct_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}


# -----------------------------
# AdGuardHome Control Center
# -----------------------------

show_agh_help() {
    clear
    print_centered_header "AdGuardHome Hub - Help"
    cat << 'HELPEOF'
SERVICE: Start, restart or stop the AdGuardHome daemon. Listed first because
   it is the most-used control and answers the STATUS line above the menu.

ALLOW/BLOCKLISTS: Add or remove filter subscriptions (block and allow lists).

SETUP & ACCESS: UI entry points (Direct Access), binary lifecycle (Updates),
   and storage thresholds (10MB Limit).

BACKUP SUITE:
   - SAVE: Generates timestamped sync points for Config and Binary.
   - RESTORE: Allows modular injection of previous system states.
   - MANAGE: Cleanup utility to purge redundant backup files.

LOGS & MAINTENANCE:
   - LOGS: Real-time 'logread' stream for diagnostic observation.
   - CACHE: Flushes filter data to resolve download/checksum errors.

FACTORY RESET: Reconstructs the environment using read-only firmware
   defaults located in the /rom partition.

NOTES:
- Edits apply when AdGuardHome restarts. If the service is stopped, changes
  are saved and take effect the next time you start it.
- RULE DISCREPANCY: 'Raw' counts include all text lines. The Web UI
  displays a lower 'Optimized' count after deduplication.
- 10MB LIMIT: Crucial for routers with small flash storage. When
  active, it restricts filter space to prevent storage exhaustion.
- LOGS: Query logs are often in /tmp (RAM). If 'Free Space' is 
  low, the system may become unstable.
HELPEOF
    press_any_key
}

create_agh_backup() {
    local ts=$(date +%Y%m%d%H%M%S)
    local b_cfg="Y"
    local b_bin="N"
    local b_ini="N"
    local AGH_CONFIG=$(get_agh_config)

    while true; do
        clear
        print_centered_header "AdGuardHome Backup Creation"
        printf " TIMESTAMP: $ts\n"
        printf "\n #  Sel Component\n"
        printf " ────────────────────────────────────────────────────────────\n"
        printf " 1. [%s] Configuration Settings (YAML)\n" "$b_cfg"
        printf " 2. [%s] App Binary (AdGuardHome Executable)\n" "$b_bin"
        printf " 3. [%s] Startup Script (init.d)\n" "$b_ini"
        printf " ────────────────────────────────────────────────────────────\n"
        printf " [#] Toggle Component   [S] Save Backup   [0] Cancel\n"
        printf "\n Choose [1-3/S/0]: "
        read -r s_choice
        s_choice=$(echo "$s_choice" | tr 'A-Z' 'a-z')
        
        case "$s_choice" in
            1) [ "$b_cfg" = "Y" ] && b_cfg="N" || b_cfg="Y" ;;
            2) [ "$b_bin" = "Y" ] && b_bin="N" || b_bin="Y" ;;
            3) [ "$b_ini" = "Y" ] && b_ini="N" || b_ini="Y" ;;
            s)
                if [ "$b_cfg" = "N" ] && [ "$b_bin" = "N" ] && [ "$b_ini" = "N" ]; then
                    printf "\n"
                    print_error "Nothing selected to save."
                    sleep 1
                    continue
                fi

                printf "\n"
                print_info "Creating Selected Backups..."
                # Atomic Save Logic
                [ "$b_cfg" = "Y" ] && [ -f "$AGH_CONFIG" ] && cp "$AGH_CONFIG" "$AGH_CONFIG.backup.$ts"
                [ "$b_bin" = "Y" ] && [ -f "/usr/bin/AdGuardHome" ] && cp "/usr/bin/AdGuardHome" "/usr/bin/AdGuardHome.backup.$ts"
                [ "$b_ini" = "Y" ] && [ -f "/etc/init.d/adguardhome" ] && cp "/etc/init.d/adguardhome" "/etc/init.d/adguardhome.backup.$ts"
                
                printf "\n"
                print_success "Backup $ts completed!"
                press_any_key
                return 0
                ;;
            0) return 1 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

manage_agh_backups() {
    while true; do
        local backups=$(ls /etc/AdGuardHome/config.yaml.backup.* 2>/dev/null | sed 's/.*\.backup\.//' | sort -r)
        [ -z "$backups" ] && { print_error "No backups found."; sleep 2; return; }

        clear
        print_centered_header "Pick a Backup Date"
        printf " %-3s  %-18s  %s  %s   %s\n" "#" "Date / Time" "Conf" "Bin" "Init"
        printf " ─────────────────────────────────────────\n"

        local i=1
        local map_file="/tmp/agh_bk_map"
        > "$map_file"

        for ts in $backups; do
            local p_date="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}"
            local has_bin="[N]"; [ -f "/usr/bin/AdGuardHome.backup.$ts" ] && has_bin="[Y]"
            local has_ini="[N] "; [ -f "/etc/init.d/adguardhome.backup.$ts" ] && has_ini="[Y] "

            printf " %-3s  %-18s  %s  %s   %s\n" "$i." "$p_date" "[Y] " "$has_bin" "$has_ini"
            printf "%s|%s\n" "$i" "$ts" >> "$map_file"
            i=$((i+1))
        done
        printf " ────────────────────────────────────────────\n"
        printf " [#] To Restore   [0] Cancel\n"
        printf "\n Choose [%s/0]: " "$(picker_range $((i-1)))"
        read -r b_choice
        printf "\n"
        [ -z "$b_choice" ] || [ "$b_choice" = "0" ] && return

        local selected_ts=$(grep "^$b_choice|" "$map_file" | cut -d'|' -f2)
        if [ -z "$selected_ts" ]; then 
            print_error "Invalid selection"; sleep 1; continue
        fi

        # Only components with a backup for this timestamp are restorable. The
        # timestamp comes from a config backup, so config always exists; binary
        # and init are optional - show (and allow toggling) only what's present,
        # numbered sequentially so there are no gaps.
        local bin_avail=0; [ -f "/usr/bin/AdGuardHome.backup.$selected_ts" ] && bin_avail=1
        local ini_avail=0; [ -f "/etc/init.d/adguardhome.backup.$selected_ts" ] && ini_avail=1
        local fix_cfg="Y"
        local fix_bin="Y"; [ "$bin_avail" -eq 0 ] && fix_bin="N"
        local fix_ini="Y"; [ "$ini_avail" -eq 0 ] && fix_ini="N"
        while true; do
            clear
            print_centered_header "Select items to restore from: $selected_ts"
            printf " #  Sel Component\n"
            printf " ────────────────────────────────────────────────────────────\n"
            local n=0 cfg_n=0 bin_n=0 ini_n=0
            n=$((n+1)); cfg_n=$n; printf " %d. [%s] Configuration Settings\n" "$n" "$fix_cfg"
            if [ "$bin_avail" -eq 1 ]; then n=$((n+1)); bin_n=$n; printf " %d. [%s] App Binary (AdGuardHome)\n" "$n" "$fix_bin"; fi
            if [ "$ini_avail" -eq 1 ]; then n=$((n+1)); ini_n=$n; printf " %d. [%s] Startup Script (init.d)\n" "$n" "$fix_ini"; fi
            printf " ────────────────────────────────────────────────────────────\n"
            printf " [#] Toggle Restore   [C] Confirm   [0] Cancel\n"
            printf "\n Choose [%s/C/0]: " "$(picker_range "$n")"
            read -r s_choice
            s_choice=$(echo "$s_choice" | tr 'A-Z' 'a-z')
            if [ "$s_choice" = "0" ]; then
                return
            elif [ "$s_choice" = "c" ]; then
                if [ "$fix_cfg" = "N" ] && [ "$fix_bin" = "N" ] && [ "$fix_ini" = "N" ]; then
                    printf "\n"
                    print_error "Nothing selected to restore. Select an option or 0 to cancel."
                    press_any_key
                    continue
                fi
                printf "\nApplying Restore...\n"
                agh_was_running=0; is_agh_running && agh_was_running=1
                [ "$agh_was_running" -eq 1 ] && { $AGH_INIT stop >/dev/null 2>&1; sleep 1; }
                [ "$fix_cfg" = "Y" ] && cp "/etc/AdGuardHome/config.yaml.backup.$selected_ts" "/etc/AdGuardHome/config.yaml"
                [ "$fix_bin" = "Y" ] && cp "/usr/bin/AdGuardHome.backup.$selected_ts" "/usr/bin/AdGuardHome"
                [ "$fix_ini" = "Y" ] && cp "/etc/init.d/adguardhome.backup.$selected_ts" "/etc/init.d/adguardhome"
                agh_apply_and_restart "$agh_was_running" "" "" "Restore complete."
                press_any_key; return
            elif [ "$s_choice" = "$cfg_n" ]; then
                [ "$fix_cfg" = "Y" ] && fix_cfg="N" || fix_cfg="Y"
            elif [ "$bin_avail" -eq 1 ] && [ "$s_choice" = "$bin_n" ]; then
                [ "$fix_bin" = "Y" ] && fix_bin="N" || fix_bin="Y"
            elif [ "$ini_avail" -eq 1 ] && [ "$s_choice" = "$ini_n" ]; then
                [ "$fix_ini" = "Y" ] && fix_ini="N" || fix_ini="Y"
            else
                print_error "Invalid option"; sleep 1
            fi
        done
    done
}

delete_agh_backups() {
    local map_file="/tmp/agh_del_map"
    [ -f "$map_file" ] && rm -f "$map_file"
    while true; do
        local backups=$(ls /etc/AdGuardHome/config.yaml.backup.* 2>/dev/null | sed 's/.*\.backup\.//' | sort -r)
        [ -z "$backups" ] && { print_error "No backups found."; sleep 2; return; }

        # Initialize map file if it doesn't exist (Index|Timestamp|Selected)
        if [ ! -f "$map_file" ]; then
            local i=1
            for ts in $backups; do
                echo "$i|$ts|0" >> "$map_file"
                i=$((i+1))
            done
        fi

        clear
        print_centered_header "AdGuardHome Backup Cleanup"
        printf " %-3s  %-4s  %-18s  %s  %s   %s  %s\n" "Sel" "Idx" "Date / Time" "Conf" "Bin" "Init" "Size"
        printf " ───────────────────────────────────────────────────────\n"

        while IFS='|' read -r idx ts sel; do
            local p_date="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}"
            local s_box="[ ]"; [ "$sel" -eq 1 ] && s_box="[✓]"

            # Check presence of components
            local c="[Y] "; [ ! -f "/etc/AdGuardHome/config.yaml.backup.$ts" ] && c="[N] "
            local b="[Y]"; [ ! -f "/usr/bin/AdGuardHome.backup.$ts" ] && b="[N]"
            local n="[Y] "; [ ! -f "/etc/init.d/adguardhome.backup.$ts" ] && n="[N] "

            # Calculate total size for this timestamp
            local ts_bytes=0
            for f in "/etc/AdGuardHome/config.yaml.backup.$ts" "/usr/bin/AdGuardHome.backup.$ts" "/etc/init.d/adguardhome.backup.$ts"; do
                [ -f "$f" ] && ts_bytes=$((ts_bytes + $(ls -nl "$f" | awk '{print $5}')))
            done
            
            # Convert to human readable
            local p_size="0B"
            if [ "$ts_bytes" -ge 1048576 ]; then
                p_size=$(awk "BEGIN {printf \"%.1fM\", $ts_bytes/1048576}")
            elif [ "$ts_bytes" -ge 1024 ]; then
                p_size=$(awk "BEGIN {printf \"%.1fK\", $ts_bytes/1024}")
            else
                p_size="${ts_bytes}B"
            fi

            printf " %s  %-4s  %-18s  %s  %s   %s  %-6s\n" "$s_box" "$idx." "$p_date" "$c" "$b" "$n" "$p_size"
        done < "$map_file"

        printf " ──────────────────────────────────────────────────────────────\n"
        printf " [A] All   [N] None   [#] Toggle   [C] Confirm   [0] Cancel\n"
        bk_count=$(wc -l < "$map_file" 2>/dev/null | tr -dc '0-9')
        printf "\n Choose [%s/A/N/C/0]: " "$(picker_range "$bk_count")"
        read -r input
        local cmd=$(echo "$input" | tr 'A-Z' 'a-z')

        case "$cmd" in
            a) sed -i 's/|0$/|1/' "$map_file" ;;
            n) sed -i 's/|1$/|0/' "$map_file" ;;
            [1-9]*) 
                if grep -q "^$cmd|" "$map_file"; then
                    local current_state=$(grep "^$cmd|" "$map_file" | cut -d'|' -f3)
                    local new_state=$((1 - current_state))
                    sed -i "s/^\($cmd|[^|]*|\).*/\1$new_state/" "$map_file"
                else
                    print_error "Index $cmd not found"; sleep 1
                fi ;;
            c)
                if ! grep -q "|1$" "$map_file"; then
                    printf "\n"
                    print_error "No backups selected."; sleep 2; continue
                fi
                printf "\n"
                print_warning "WARNING: You are about to permanently delete selected backups."
                printf "Delete selected backups? [y/N]: "; read -r confirm
                case "$confirm" in
                    y|Y)
                    while IFS='|' read -r idx ts sel; do
                        if [ "$sel" -eq 1 ]; then
                            rm -f "/etc/AdGuardHome/config.yaml.backup.$ts"
                            rm -f "/usr/bin/AdGuardHome.backup.$ts"
                            rm -f "/etc/init.d/adguardhome.backup.$ts"
                        fi
                    done < "$map_file"
                    printf "\n"
                    print_success "Selected backups purged."
                    press_any_key;
                    rm -f "$map_file"
                    return ;;
                    *) print_error "Deletion cancelled." ; sleep 2 ; continue ;;
                esac ;;
            0) rm -f "$map_file"; return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

show_agh_setup_help() {
    clear
    print_centered_header "AdGuardHome Setup & Access - Help"

    cat << 'HELPEOF'
What is this?
─────────────
Configuration for how AdGuardHome stores its filter data, how its Web UI is
reached, and whether it is allowed to update its own UI. Each item opens its
own screen with full details and its own help.

Getting around (the same keys work on every screen):
• Type the number shown beside an item and press Enter to open it.
• [0] returns to the previous menu.
• [?] shows the help for the screen you are on.
HELPEOF

    press_any_key
}

sub_setup_config() {
    while true; do
        clear
        print_centered_header "AdGuardHome Setup, Access & UI Updates"
        printf "%s  Filter Storage Space Limit\n" "$N1"
        printf "%s  UI Direct Access\n" "$N2"
        printf "%s  UI Updates\n" "$N3"
        printf "%s  Back\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-3/0/?]: "
        read -r s_opt
        case "$s_opt" in
            \?|h|H|❓) show_agh_setup_help ;;
            1) manage_agh_storage ;;
            2) manage_agh_direct_access ;;
            3) manage_agh_ui_updates ;;
            0) break ;;
            *) print_error "Invalid option"; sleep 1;;
        esac
    done
}

show_agh_backup_help() {
    clear
    print_centered_header "AdGuardHome Backup & Recovery - Help"

    cat << 'HELPEOF'
What is this?
─────────────
Create, restore and manage backups of your AdGuardHome configuration, binary
and startup script. Backups are timestamped, so you can keep several and roll
back to any of them if a change goes wrong.

Getting around:
• Type the number shown beside an item and press Enter to open it.
• [0] returns to the previous menu.
• [?] shows this help.
HELPEOF

    press_any_key
}

sub_backup_recovery() {
    while true; do
        get_agh_stats 
        clear
        print_centered_header "AdGuardHome Backup & Recovery Suite"
        printf " ${CYAN}OVERVIEW${RESET}\n"
        printf "   Latest: %s  ·  Total Files: %s\n\n" "${bk_date:-None}" "${bk_file_count:-0}"
        printf " ${CYAN}STORAGE STATUS${RESET}\n"
        printf "   Used: %s  ·  Free: %s\n" "${bk_total_u:-0B}" "${qlog_f:-N/A}"
        printf " ────────────────────────────────────────────────\n\n"
        printf "%s  Save a New Backup\n" "$N1"
        printf "%s  Restore from Backup\n" "$N2"
        printf "%s  Manage/Delete Backups\n" "$N3"
        printf "%s  Back\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-3/0/?]: "
        read -r b_opt
        case "$b_opt" in
            \?|h|H|❓) show_agh_backup_help ;;
            1) create_agh_backup ;;
            2) manage_agh_backups ;;
            3) delete_agh_backups ;;
            0) break ;;
            *) print_error "Invalid option"; sleep 1;;
        esac
    done
}

show_agh_service_help() {
    clear
    print_centered_header "AdGuardHome Logs & Maintenance - Help"

    cat << 'HELPEOF'
What is this?
─────────────
Watch AdGuardHome's live logs and clear its cached filter files. Use this
screen for diagnostics or after changing filter lists. Starting, stopping and
restarting the service is the first item on the Control Center.

Getting around:
• Type the number shown beside an item and press Enter to open it.
• [0] returns to the previous menu.
• [?] shows this help.
HELPEOF

    press_any_key
}

sub_service_health() {
    while true; do
        clear
        print_centered_header "AdGuardHome Logs & Maintenance"
        printf "%s  Watch Live Logs\n" "$N1"
        printf "%s  Clear Filter Cache\n" "$N2"
        printf "%s  Back\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-2/0/?]: "
        read -r h_opt
        case "$h_opt" in
            \?|h|H|❓) show_agh_service_help ;;
            1)
               clear
               print_centered_header "AdGuardHome System Logs (Ctrl+C to exit)"
               sleep 1
               trap 'printf "\n\n"; print_warning "Stopping log viewing..."' INT
               logread -l 20 -e "AdGuardHome" 2>/dev/null
               logread -f -e "AdGuardHome" 2>/dev/null
               trap - INT
               press_any_key
               ;;
            2)
               printf "\n"
               print_warning "This clears all cached filter files; AdGuardHome re-downloads them on next start."
               printf "Clear filter cache? [y/N]: "; read -r confirm
               if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                   local wd=$(get_agh_workdir)
                   agh_was_running=0; is_agh_running && agh_was_running=1
                   rm -rf "${wd:-/etc/AdGuardHome}/data/filters/"* 2>/dev/null
                   agh_apply_and_restart "$agh_was_running" "" "" "Filters purged." "-"
                   cached_rules=""
               fi
               press_any_key ;;
            0) break ;;
            *) print_error "Invalid option"; sleep 1;;
        esac
    done
}

sub_confirm_factory_reset() {
    local L_INIT="/etc/init.d/adguardhome"
    local L_BIN="/usr/bin/AdGuardHome"
    local L_CONF="/etc/AdGuardHome/config.yaml"
    local init_ok=0 bin_ok=0 conf_ok=0
    local was_running=0
    local was_uci_enabled=0

    printf "\n"
    print_warning "WARNING: This will restore factory system files and defaults from /rom"
    printf "Restore factory defaults? [y/N]: "; read -r confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { printf "\n"; print_info "Operation cancelled."; press_any_key; return; }

    # --- 1. Pre-Check State & Stop Phase ---
    # Call the function directly to check the exit status
    is_agh_running && was_running=1
    
    if [ "$(uci -q get adguardhome.config.enabled)" = "1" ]; then
        was_uci_enabled=1
    fi

    if [ "$was_running" -eq 1 ]; then
        printf "\n"
        print_info "AdGuardHome is currently running. Stopping service..."
        [ -f "$L_INIT" ] && $L_INIT stop >/dev/null 2>&1; sleep 1
        sleep 1
        if is_agh_running; then
            kill -9 $(pidof AdGuardHome) >/dev/null 2>&1; sleep 1
        fi
        print_success "Service stopped successfully."
    fi

    # --- 2. Restore Files from ROM ---
    [ -f "/rom$L_INIT" ] && cp -f "/rom$L_INIT" "$L_INIT" && chmod +x "$L_INIT" && init_ok=1
    [ -f "/rom$L_BIN" ]  && cp -f "/rom$L_BIN" "$L_BIN"   && chmod +x "$L_BIN"  && bin_ok=1
    [ -f "/rom$L_CONF" ] && cp -f "/rom$L_CONF" "$L_CONF" && conf_ok=1
    
    # --- 3. Report Status ---
    printf "\n"
    [ $init_ok -eq 1 ] && print_success "Init Script restored" || print_error "Init Script missing in ROM"
    [ $bin_ok -eq 1 ]  && print_success "Binary restored"      || print_error "Binary missing in ROM"
    [ $conf_ok -eq 1 ] && print_success "Config yaml restored" || print_error "Config missing in ROM"
    printf "\n"

    # --- 4. Finalization Logic ---
    if [ $init_ok -eq 1 ] && [ $bin_ok -eq 1 ] && [ $conf_ok -eq 1 ]; then
        # Handle administrative state (UCI)
        if [ "$was_uci_enabled" -eq 1 ]; then
            uci set adguardhome.config.enabled='1' && uci set adguardhome.config.dns_enabled='1' && uci commit adguardhome
            $L_INIT enable >/dev/null 2>&1; sleep 1
            print_success "Full recovery successful! AdGuardHome auto-start re-enabled."
            printf "\n"
        else
            print_warning "AdGuardHome was disabled in UCI."
            printf "Enable AdGuardHome? [y/N]: "; read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then 
                uci set adguardhome.config.enabled='1' && uci set adguardhome.config.dns_enabled='1' && uci commit adguardhome
                $L_INIT enable >/dev/null 2>&1; sleep 1
                printf "\n"
                print_success "AdGuardHome enabled in GL Web UI and UCI."
                printf "\n"
                was_uci_enabled=1
            fi
        fi
        
        # Handle operational state (Running)
        if [ "$was_running" -eq 1 ]; then
            print_info "Automatically restarting service..."
            $L_INIT start >/dev/null 2>&1; sleep 2; print_success "Service restored to running state."
        elif [ "$was_uci_enabled" -eq 1 ]; then
            print_warning "AdGuardHome is enabled but not running."
            printf "Start the service? [y/N]: "; read -r confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then 
                printf "\n"
                print_info "Starting AdGuardHome..."
                printf "\n"
                $L_INIT start >/dev/null 2>&1; sleep 2; print_success "Service started successfully."
            fi
        fi
    elif [ $init_ok -eq 1 ] || [ $bin_ok -eq 1 ] || [ $conf_ok -eq 1 ]; then
        print_warning "Partial recovery. Some files are still missing."
    else
        print_error "Recovery failed. Files not found in /rom or write error."
    fi
    press_any_key
}

get_agh_stats() {
    # 1. Basic Status Icons
    run_icon="$_S_OFF"; is_agh_running && run_icon="$_S_ON"
    local web_enabled=$(uci -q get adguardhome.config.enabled)
    web_icon="$_S_OFF"; [ "$web_enabled" = "1" ] && web_icon="$_S_ON"
    
    # 2. Setup Paths
    local AGH_CONFIG=$(get_agh_config)
    local workdir=$(get_agh_workdir)
    local data_dir="${workdir:-/etc/AdGuardHome}/data"

    # 3. List & Rules Logic
    list_count=$(grep -c "url:" "$AGH_CONFIG" 2>/dev/null || echo "0")
    if [ -z "$cached_rules" ]; then
        local raw_val=$(find "$data_dir/filters" -type f 2>/dev/null | xargs cat 2>/dev/null | wc -l)
        cached_rules=$(printf "$raw_val" | awk '{len=length($0); for(i=len-3;i>0;i-=3) $0=substr($0,1,i) "," substr($0,i+1); print $0}')
    fi

    # 4. Storage Metric: Filters
    filt_u=$(du -sh "$data_dir/filters" 2>/dev/null | awk '{print $1}')
    filt_f=$(get_free_space "$data_dir/filters")

    # 5. Storage Metric: Query Logs (DBs + JSON)
    local q_bytes=0
    for f in "$data_dir/stats.db" "$data_dir/sessions.db" "$data_dir/querylog.json"; do
        [ -f "$f" ] && q_bytes=$((q_bytes + $(ls -nl "$f" | awk '{print $5}')))
    done
    qlog_u=$(awk "BEGIN {printf \"%.1fM\", ${q_bytes:-0}/1048576}")
    qlog_f=$(get_free_space "$data_dir")

    # 6. Backup Storage & Last Date
    local bk_locs="/etc/AdGuardHome /usr/bin /etc/init.d"
    
    local bk_bytes=$(find $bk_locs -maxdepth 1 -name "*.backup.*" -exec ls -nl {} + 2>/dev/null | awk '{sum += $5} END {print sum + 0}')
    
    bk_total_u=$(awk "BEGIN { 
        mbs = $bk_bytes / 1048576;
        if (mbs > 0 && mbs < 0.1) printf \"0.01M\";
        else printf \"%.2fM\", mbs;
    }")

    bk_file_count=$(find $bk_locs -maxdepth 1 -name "*.backup.*" 2>/dev/null | wc -l)
    
    local last_bk_file=$(ls -t /etc/AdGuardHome/config.yaml.backup.* 2>/dev/null | head -n1)
    if [ -n "$last_bk_file" ]; then
        # Extracts YYYYMMDD from the suffix
        local ts=$(echo "$last_bk_file" | awk -F'.backup.' '{print $2}')
        bk_date="${ts:0:4}-${ts:4:2}-${ts:6:2}"
    else
        bk_date="None"
    fi

    # 7. Version Info
    v_num=$(/usr/bin/AdGuardHome --version 2>/dev/null | awk '{print $4}')
}

agh_control_center() {
    while true; do
        get_agh_stats
        clear
        print_centered_header "AdGuardHome Control Center"
        printf " ${CYAN}STATUS${RESET}\n   Run: %b  ·  GL WebUI: %b  ·  Version: v%s\n\n" "${run_icon:-$_S_OFF}" "${web_icon:-$_S_OFF}" "${v_num:-N/A}"
        printf " ${CYAN}FILTERS${RESET}\n   Lists: %s  ·  Rules: %s\n\n" "${list_count:-0}" "${cached_rules:-0}"
        printf " ${CYAN}STORAGE${RESET}\n   Filters: %s/%s  ·  Logs: %s/%s\n\n" "${filt_u:-0B}" "${filt_f:-N/A}" "${qlog_u:-0B}" "${qlog_f:-N/A}"
        printf " ${CYAN}BACKUP${RESET}\n   Date: %s  ·  Size: %s  ·  Files: %s\n\n" "${bk_date:-None}" "${bk_total_u:-0B}" "${bk_file_count:-0}"
        printf " ────────────────────────────────────────────────\n\n"
        local svc_label="Start AdGuardHome"
        is_agh_running && svc_label="Restart / Stop AdGuardHome"
        printf "%s  %s\n" "$N1" "$svc_label"
        printf "%s  Manage Allow/Blocklists\n" "$N2"
        printf "%s  Setup, Access & UI Updates\n" "$N3"
        printf "%s  Backup & Recovery Suite\n" "$N4"
        printf "%s  Logs & Maintenance\n" "$N5"
        printf "%s Reset to Factory Settings (Start Over)\n" "$NCL"
        printf "%s  Main menu\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-5/CL/0/?]: "
        read -r choice

        case "$choice" in
            1) agh_service_control ;;
            2) manage_agh_lists ;;
            3) sub_setup_config ;;
            4) sub_backup_recovery ;;
            5) sub_service_health ;;
            [cC][lL]) sub_confirm_factory_reset ;;
            0) break ;;
            \?|h|H|❓) show_agh_help ;;
            *) print_error "Invalid option"; sleep 1;;
        esac
    done
}

# -----------------------------
# System Tweaks
# -----------------------------

# --- Zram Swap Management ---

show_zram_help() {
    clear
    print_centered_header "Zram Swap - Help"
    
    cat << 'HELPEOF'
Zram Swap – Quick Help

What is zram swap?
──────────────────
Zram creates a compressed block device in your router's RAM and uses it as swap space. 
Instead of writing swap data to slow flash storage (which wears it out quickly), zram 
compresses the data and keeps it in RAM. This is much faster and protects your NAND/eMMC.

Main benefits on GL.iNet routers:
• Greatly improves performance when RAM is low (e.g. heavy VPN, AdGuardHome, many clients)
• Reduces lag and stuttering under memory pressure
• Does not use or impact the router's flash storage
• Uses minimal CPU overhead on modern router SoCs

Typical recommendations:
• 50% of total RAM is a good starting size (e.g. 256 MB on a 512 MB router)
• Most GL.iNet users enable it if they run AdGuardHome + VPN or have ≥10–15 devices connected

When should you use it?
Yes → if your router frequently runs out of RAM or you notice slowdowns
No  → if you have 1 GB+ RAM and very light usage

Important notes:
• Zram uses some CPU to compress/decompress → not ideal on very old/slow CPUs
• Data in zram is lost on reboot (normal for swap)
• Routers with 512MB flash or less will have a forced limit for AdGuardHome allow/block lists.

In this menu you can:
1. Install & enable zram swap
2. Disable it (stops and disables on boot)
3. Enable/Disable Persistence - survives firmware updates
4. Completely uninstall the package
HELPEOF
    
    press_any_key
}

manage_zram() {
    local up_conf="/etc/sysupgrade.conf"
    local laz_list="/etc/lazarus.list"

    while true; do
		hash -r
        zram_persisting=0
        if grep -qFx "/etc/init.d/zram" "$up_conf" 2>/dev/null; then
            zram_persisting=1
        fi

        clear
        print_centered_header "Zram Swap Management"
        
        printf " %b\n" "${CYAN}STATUS${RESET}"
        if command -v zram >/dev/null 2>&1 || [ -f /etc/init.d/zram ]; then
            if /etc/init.d/zram enabled 2>/dev/null; then
                printf "   Zram Swap:   %bENABLED%b\n" "${GREEN}" "${RESET}"
                
                if [ -f /sys/block/zram0/disksize ]; then
                    disksize=$(cat /sys/block/zram0/disksize 2>/dev/null)
                    disksize_mb=$((disksize / 1024 / 1024))
                    printf "   Disk Size: %d MB\n" "$disksize_mb"
                fi
                
                if swapon -s 2>/dev/null | grep -q zram; then
                    printf "   Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                else
                    printf "   Status: %bINACTIVE%b\n" "${YELLOW}" "${RESET}"
                fi
            else
                printf "   Zram Swap:   %bDISABLED%b\n" "${YELLOW}" "${RESET}"
            fi
        else
            printf "   Zram Swap:   %bNOT INSTALLED%b\n" "${RED}" "${RESET}"
        fi
        if [ "$zram_persisting" -eq 1 ]; then
                printf "   Persistence: %bENABLED%b\n\n" "${GREEN}" "${RESET}"
            else
                printf "   Persistence: %bDISABLED%b\n\n" "${YELLOW}" "${RESET}"
        fi
        
        local zram_persist_label="Enable Persistence"
        [ "$zram_persisting" -eq 1 ] && zram_persist_label="Disable Persistence"
        printf "%s  Install and Enable\n" "$N1"
        printf "%s  Disable\n" "$N2"
        printf "%s  %s\n" "$N3" "$zram_persist_label"
        printf "%s  Uninstall Package\n" "$N4"
        printf "%s  Back\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-4/0/?]: "
        read -r zram_choice
        printf "\n"
        
        case $zram_choice in
            1)
                if ! opkg list-installed | grep -q "^zram-swap"; then
                    install_package zram-swap || { press_any_key; continue; }
                fi
                
                if [ -f /etc/init.d/zram ]; then
                    print_info "Enabling and starting zram swap"
                    /etc/init.d/zram enable >/dev/null 2>&1; sleep 1
                    /etc/init.d/zram start >/dev/null 2>&1; sleep 2
                    print_success "Zram swap enabled and started"

                    if swapon -s 2>/dev/null | grep -q zram; then
                        print_success "Zram swap is working correctly"
                    else
                        print_warning "Zram swap may not be working properly"
                    fi
                else
                    print_error "Zram init script not found"
                fi
                press_any_key
                ;;
            2)
                if [ -f /etc/init.d/zram ]; then
                    /etc/init.d/zram stop >/dev/null 2>&1; sleep 1
                    /etc/init.d/zram disable >/dev/null 2>&1; sleep 1
                    print_success "Zram swap disabled and stopped"
                else
                    print_warning "Zram swap is not installed"
                fi
                press_any_key
                ;;
            3)
                if [ ! -f /etc/init.d/zram ]; then
                    print_error "Zram swap is not installed."
                else
                    local z_paths="/etc/init.d/zram /etc/config/system"
                    
                    if [ "$zram_persisting" -eq 0 ]; then
                        for p in $z_paths; do
                            grep -qFx "$p" "$up_conf" || echo "$p" >> "$up_conf"
                        done
                        grep -qFx "zram-swap" "$laz_list" 2>/dev/null || echo "zram-swap" >> "$laz_list"
                        create_lazarus_hook
                        print_success "Zram persistence enabled."
                    else
                        for p in $z_paths; do
                            sed -i "\|$p|d" "$up_conf" 2>/dev/null
                        done
                        sed -i "\|zram-swap|d" "$laz_list" 2>/dev/null
                        print_warning "Zram persistence disabled."
                    fi
                fi
                press_any_key
                ;;
            4)
                if opkg list-installed | grep -q "^zram-swap"; then
                    printf "%b" "${YELLOW}Remove zram-swap package? [y/N]: ${RESET}"
                    read -r confirm
                    printf "\n"
                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        [ -f /etc/init.d/zram ] && /etc/init.d/zram stop >/dev/null 2>&1; sleep 1
                        opkg remove --autoremove zram-swap >/dev/null 2>&1
                        for p in /etc/init.d/zram /etc/config/system; do
                            sed -i "\|$p|d" "$up_conf" 2>/dev/null
                        done
                        sed -i "\|zram-swap|d" "$laz_list" 2>/dev/null
                        
                        print_success "zram-swap package removed"
                    else
                        printf "Removal cancelled."
                    fi
                else
                    print_warning "zram-swap package is not installed"
                fi
                press_any_key
                ;;
            \?|h|H|❓)
                show_zram_help
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# --- Fan Management Module ---

show_fan_help() {
    clear
    print_centered_header "Fan Management - Help"
    
    cat << 'HELPEOF'
Fan Management – Quick Help

How the Fan Controller Works:
─────────────────────────────
The /usr/bin/gl_fan process uses a PID-style controller to manage speed 
based on three primary temperature setpoints.

The Setpoints Explained:
• Minimum: The temperature where the fan starts spinning at its lowest 
  voltage. Setting this higher keeps the fan off longer.
• Fan-On: The "Target" temperature. The controller will ramp the fan up 
  toward 100% speed as it approaches and exceeds this value.
• Warning: Primarily used for system logs and UI alerts. Usually set 
  equal to or slightly higher than the Fan-On setpoint.
• Max: This script's custom "Unlock." It extends the slider range
  in the web interface, allowing you to set thresholds up to 120°C.

Thermal Hierarchy (Safety Rules):
─────────────────────────────────
To prevent logic loops, the following rules are enforced:
  Minimum ≤ Fan-On ≤ Max
  Warning must be between Minimum and Max.

Dynamic vs. Manual Mode:
• Dynamic: The system automatically adjusts RPM based on heat.
• Manual: Forces the fan to a specific percentage (0-100%). 
  Note: Manual mode persists until you re-enable Dynamic control.

Safety Warning:
────────────────
Extending limits beyond 100°C can lead to hardware throttling or 
emergency shutdowns. Most silicon is rated for ~105°C. Use 110°C+ 
only if you understand the thermal risks to your specific model.
HELPEOF
    
    press_any_key
}

manage_fan_settings() {
    current_model=$(cat /proc/gl-hw-info/model)
    nav_choice=""

    reset_to_factory(){
        # 1. Restore the 'Engine' (The Library) and the 'Seed' (The ROM config)
        if [ -f "/rom/lib/functions/gl_util.sh" ]; then 
            cp "/rom/lib/functions/gl_util.sh" "/lib/functions/gl_util.sh"
        fi

        if [ -f "/rom/etc/config/glfan" ]; then 
            cp "/rom/etc/config/glfan" "/etc/config/glfan"
        fi
        
        # 2. Trigger the Internal Provisioner
        # This populates UCI with the REAL factory defaults for THIS specific model
        . /lib/functions/gl_util.sh
        fan_init
        uci commit glfan
        
        # 3. Restore Web UI Visuals & Logic from ROM
        if [ -f "/rom/www/views/gl-sdk4-ui-overview.common.js.gz" ]; then
            cp "/rom/www/views/gl-sdk4-ui-overview.common.js.gz" "/www/views/gl-sdk4-ui-overview.common.js.gz"
        fi
        
        local app_rom_gz=$(find /rom/www/js/ -name "app.*.js.gz" -type f | head -n 1)
        if [ -n "$app_rom_gz" ]; then
            cp "$app_rom_gz" "/www/js/$(basename "$app_rom_gz")"
        fi

        if [ -f "/rom/www/i18n/gl-sdk4-ui-overview.en.json" ]; then
            cp "/rom/www/i18n/gl-sdk4-ui-overview.en.json" "/www/i18n/gl-sdk4-ui-overview.en.json"
        fi
        
        /etc/init.d/gl_fan restart >/dev/null 2>&1
    }

    sync_system_and_ui() {
        # Start at a good working state
        reset_to_factory       
        
        local n_min=$1  # Minimum (The Floor)
        local n_cur=$2  # Fan-On (The current target)
        local n_wrn=$3  # Warning (The visual/system trigger)
        local n_max=$4  # Maximum (The Ceiling)
        
        local b_min=$((n_min - 1)) 
        local b_max=$((n_max + 1))
        local util_file="/lib/functions/gl_util.sh"

        # --- 1. System Logic & Backend Variable Sync ---
        # Patch the hardware floor comparisons in the fan control library
        sed -i "s/-lt 6[0-9]/-lt $n_min/g" "$util_file"
        sed -i "s/-lt 7[0-9]/-lt $n_min/g" "$util_file"

        # Use the model identifier to target the correct code block for assignments
        if awk "/$current_model[)]/,/;;/" "$util_file" | grep -q "temperature="; then
            sed -i "/$current_model[)]/,/;;/ s/\(minimum_temperature=\)[0-9]*/\1$n_min/" "$util_file"
            sed -i "/$current_model[)]/,/;;/ s/\([[:space:]]temperature=\)[0-9]*/\1$n_cur/" "$util_file"
        else
            sed -i "s/\(local minimum_temperature=\)[0-9]*/\1$n_min/" "$util_file"
            sed -i "s/\(local temperature=\)[0-9]*/\1$n_cur/" "$util_file"
        fi
        sed -i "s/warn_temperature=.*$/warn_temperature=\"$n_wrn\"/" "$util_file"

        # --- 2. UCI Persistence ---
        uci set glfan.globals.minimum_temperature="$n_min"
        uci set glfan.globals.temperature="$n_cur"
        uci set glfan.globals.warn_temperature="$n_wrn"
        uci commit glfan

        # --- 3. View Component Patching (UI Logic & Visuals) ---
        local view_gz="/www/views/gl-sdk4-ui-overview.common.js.gz"
        [ ! -f "$view_gz" ] && cp "/rom$view_gz" "$view_gz"
        gunzip -f "$view_gz"
        local v="/www/views/gl-sdk4-ui-overview.common.js"

        # SECTION A: Computed Property Overrides (Dynamic Shadowing)
        sed -i "s/minimum_temperature:t/minimum_temperature:ignore,t=$n_min/g" "$v"
        sed -i "s/maximum_temperature:t/maximum_temperature:ignore,t=$n_max/g" "$v"
        sed -i "s/maximumTemperature:()=>[0-9]*/maximumTemperature:()=>$n_max/g" "$v"

        # SECTION B: Literal Logic Guards (Integer Boundaries)
        sed -i "s/t<70/t<$n_min/g" "$v"
        sed -i "s/t>90/t>$n_max/g" "$v"
        sed -i "s/ature=70/ature=$n_min/g" "$v"
        sed -i "s/ature=90/ature=$n_max/g" "$v"

        # SECTION C: Universal Component Logic (Snap-Back Prevention)
        sed -i "s/t<this.minimumTemperature/t<$n_min/g" "$v"
        sed -i "s/t>this.maximumTemperature/t>$n_max/g" "$v"
        sed -i "s/this.temperature=this.minimumTemperature/this.temperature=$n_min/g" "$v"
        sed -i "s/this.temperature=this.maximumTemperature/this.temperature=$n_max/g" "$v"

        # SECTION D: Physical Slider Attributes (Visual Buffer)
        sed -i "s/attrs:{min:[^,]*[0-9a-zA-Z.-]*,max:[0-9a-zA-Z.+-]*/attrs:{min:$b_min,max:$b_max/g" "$v"

        # SECTION E: Slider Scale & Step Labels
        local marks_obj="${n_min}:'${n_min}°C'"
        local span=$((n_max - n_min))
        local interval=10
        [ "$span" -le 50 ] && interval=5
        for i in $(seq $((n_min + $interval)) "$interval" "$n_max"); do
            marks_obj="$marks_obj,$i:'$i°C'"
        done
        sed -i "s/marks:t.tMarks/marks:{$marks_obj}/g" "$v"

        # SECTION F: Information Strings (Info Box / Localization)
        local info_pattern="fan start is [^.]*"
        local info_replacement="fan start is $n_min °C ~ $n_max °C "
        sed -i "s/$info_pattern/$info_replacement/g" "$v"
        [ -f "/www/i18n/gl-sdk4-ui-overview.en.json" ] && \
        sed -i "s/$info_pattern/$info_replacement/g" "/www/i18n/gl-sdk4-ui-overview.en.json"

        # --- 4. Global Application Controller Patch (Validator Range) ---
        local app_gz=$(find /www/js/ -name "app.*.js.gz" -type f | head -n 1)
        if [ -n "$app_gz" ]; then
            gunzip -f "$app_gz"
            local app_file="${app_gz%.gz}"
            # Unlock the global validator range
            sed -i "s/[0-9]\{1,3\}||i<[0-9]\{2,3\}/${n_min}||i<$((n_max + 1))/g" "$app_file"
            # Prevent initial state snap-back on page load
            sed -i "s/temperature:6[90]/temperature:$n_cur/g" "$app_file"
            sed -i "s/temperature:76/temperature:$n_cur/g" "$app_file"
            gzip -f "$app_file"
        fi

        # 5. Deployment
        gzip -f "$v"
        /etc/init.d/gl_fan restart
    }
    
    clear
    printf '\033[?25l'
    
    while true; do
        
        # 1. State Capture & Fanless Detection
        has_fan=true
        [ ! -d "/sys/class/thermal/cooling_device0" ] && has_fan=false

        c_mode="DYNAMIC (System)"
        c_mode_color="${GREEN}"
        if ! pgrep -f '/usr/bin/gl_fan' >/dev/null; then
            c_mode="MANUAL (Static)"
            c_mode_color="${YELLOW}"
        fi
        
        c_temp_fmt=$(get_cpu_temp)
        c_fan_rpm="N/A"
        c_speed_pct=0
        
        if [ "$has_fan" = "true" ]; then
            c_fan_rpm=$(get_fan_speed)
            c_pwm=$(cat /sys/class/thermal/cooling_device0/cur_state 2>/dev/null)
            [ -z "$c_pwm" ] && c_pwm=0
            c_speed_pct=$(( (c_pwm * 100 + 127) / 255 ))
        fi

        # 2. Get Current UI Max Setpoint
        local view_gz="/www/views/gl-sdk4-ui-overview.common.js.gz"
        local util_file="/lib/functions/gl_util.sh"
        local attrs_block=$(gzip -dc "$view_gz" 2>/dev/null | grep -oE "attrs:\{min:[-0-9]+,max:[0-9]+")

        if [ -n "$attrs_block" ]; then
            raw_min=$(echo "$attrs_block" | cut -d: -f3 | cut -d, -f1)
            raw_max=$(echo "$attrs_block" | cut -d: -f4)
            u_min=$((raw_min + 1))
            ui_max=$((raw_max - 1))
        else
            u_min=$(gzip -dc "$view_gz" 2>/dev/null | grep -oE "minimumTemperature:[^}]*" | grep -oE "[0-9]{2,3}" | head -n 1)
            ui_max=$(gzip -dc "$view_gz" 2>/dev/null | grep -oE "maximumTemperature:[^}]*" | grep -oE "[0-9]{2,3}" | head -n 1)
        fi

        # --- 3. UCI Configuration State (The "Truth") ---
        u_cur=$(uci -q get glfan.globals.temperature)
        u_wrn=$(uci -q get glfan.globals.warn_temperature)

        # --- 4. Sanitization & Fallbacks ---
        [ -z "$u_min" ] && u_min=70
        [ -z "$ui_max" ] && ui_max=90
        [ -z "$u_cur" ] && u_cur=75
        [ -z "$u_wrn" ] && u_wrn=75

        printf '\033[H'
        print_centered_header "Fan Management"
        
        printf " %b\n" "${CYAN}STATUS${RESET}"
        if [ "$has_fan" = "false" ]; then
            printf "   Hardware:          %bNOT DETECTED (Fanless Unit)%b\033[K\n" "${RED}" "${RESET}"
        else
            printf "   Control Mode:      %b%s%b\033[K\n" "$c_mode_color" "$c_mode" "${RESET}"
            printf "   Current Speed:     %d%% (%s RPM)\033[K\n" "$c_speed_pct" "$c_fan_rpm"
        fi
        printf "   Temperature:       %b%s°C%b\033[K\n\n" "${WHITE}" "$c_temp_fmt" "${RESET}"

        printf " %b\n" "${CYAN}SYSTEM & WEB UI SETTINGS${RESET}"
        printf "   Minimum Setpoint:  %s°C\033[K\n" "${u_min:-UNKNOWN}"
        printf "   Fan-On Setpoint:   %s°C\033[K\n" "${u_cur:-UNKNOWN}"
        printf "   Warning Setpoint:  %s°C\033[K\n" "${u_wrn:-UNKNOWN}"
        printf "   Max Setpoint:      %b%s°C%b\033[K\n\n" "${YELLOW}" "$ui_max" "${RESET}"

        if [ "$has_fan" = "false" ]; then
            print_warning "Fan settings are disabled on fanless hardware.\033[K"
            printf "%s  Back\033[K\n" "$N0"
            printf "\nChoose [0/?]: \033[K"
        else
            printf "%s  Set Static Fan Speed (0-100%%)\033[K\n" "$N1"
            printf "%s  Enable Dynamic Fan Control\033[K\n" "$N2"
            printf "%s  Set Minimum Setpoint\033[K\n" "$N3"
            printf "%s  Set Fan-On Setpoint\033[K\n" "$N4"
            printf "%s  Set Warning Setpoint\033[K\n" "$N5"
            printf "%s  Set Maximum Setpoint\033[K\n" "$N6"
            printf "%s  Reset to Factory Defaults\033[K\n" "$N7"
            printf "%s  Back\033[K\n" "$N0"
            printf "%s Help\033[K\n" "$NQ"
            printf "\nChoose [1-7/0/?]: \033[K"
        fi
               
        printf '\033[?25h'
        read -t 1 -n 1 fan_choice
        printf "\n"

        if [ -n "$fan_choice" ]; then
            current_choice="$fan_choice"
            fan_choice=""
            printf "\n"
        
            if [ "$has_fan" = "false" ]; then
                case "$current_choice" in
                    0) return ;;
                    \?|h|H|help|HELP) show_fan_help; continue ;;
                    *) continue ;;
                esac
            fi

            case "$current_choice" in
                1)
                    printf "Enter Speed %% (0-100): "
                    read -r pct
                    printf "\n"
                    pct=$(echo "$pct" | tr -dc '0-9')
                    if [ -n "$pct" ] && [ "$pct" -le 100 ]; then
                        /etc/init.d/gl_fan stop >/dev/null 2>&1
                        echo "$(( (pct * 255 + 50) / 100 ))" > /sys/class/thermal/cooling_device0/cur_state
                        print_success "Manual mode active: $pct%"
                    else
                        print_error "Invalid input."
                    fi
                    press_any_key; clear ;;
                2)
                    /etc/init.d/gl_fan enable >/dev/null 2>&1
                    /etc/init.d/gl_fan restart >/dev/null 2>&1
                    print_success "Dynamic control restored"
                    press_any_key; clear ;;
                3)
                    printf "Set new Minimum Setpoint (0°C - %s°C): " "$u_cur"
                    read -r val
                    val=$(echo "$val" | tr -dc '0-9')
                    if [ -n "$val" ] && [ "$val" -le "$u_cur" ]; then
                        sync_system_and_ui "$val" "$u_cur" "$u_wrn" "$ui_max"
                        printf "\n"
                        print_success "Minimum setpoint updated to ${val}°C (System & UI)."
                    else
                        printf "\n"
                        print_error "Must be a number and ≤ Fan-On ($u_cur°C)"
                    fi
                    press_any_key; clear ;;
                4)
                    printf "New Fan-On Setpoint (%s°C - %s°C): " "$u_min" "$ui_max"
                    read -r val
                    printf "\n"
                    val=$(echo "$val" | tr -dc '0-9')
                    if [ -n "$val" ] && [ "$val" -ge "$u_min" ] && [ "$val" -le "$ui_max" ]; then
                        sync_system_and_ui "$u_min" "$val" "$u_wrn" "$ui_max"
                        printf "\n"
                        print_success "Fan-On setpoint updated"
                    else
                        printf "\n"
                        print_error "Must be between Min ($u_min°C) and Max ($ui_max°C)"
                    fi
                    press_any_key; clear ;;
                5)
                    printf "New Warning Setpoint (%s°C - %s°C): " "$u_min" "$ui_max"
                    read -r val
                    printf "\n"
                    val=$(echo "$val" | tr -dc '0-9')
                    if [ -n "$val" ] && [ "$val" -ge "$u_min" ] && [ "$val" -le "$ui_max" ]; then
                        sync_system_and_ui "$u_min" "$u_cur" "$val" "$ui_max"
                        printf "\n"
                        print_success "Warning setpoint updated"
                    else
                        printf "\n"
                        print_error "Must be between Min ($u_min°C) and Max ($ui_max°C)"
                    fi
                    press_any_key; clear ;;
                6)
                    print_warning "DANGER: EXTENDING AND SETTING THERMAL LIMITS PAST 90°C MAY CAUSE DAMAGE TO YOUR DEVICE!"
                    printf "Set new Maximum Setpoint (%s°C - 120°C): " "$u_cur"
                    read -r val
                    val=$(echo "$val" | tr -dc '0-9')
                    if [ -n "$val" ] && [ "$val" -ge "$u_cur" ] && [ "$val" -le 120 ]; then
                        if [ "$val" -lt $u_wrn ]; then
                            printf "\n"
                            print_warning "New Max is below current Warning setpoint. Adjusting Warning to match new Max."
                            printf "\n"
                            u_wrn="$val"
                        fi
                        sync_system_and_ui "$u_min" "$u_cur" "$u_wrn" "$val"
                        printf "\n"
                        print_success "Max setpoint updated to ${val}°C."
                    else
                        printf "\n"
                        print_error "Must be between Fan-On ($u_cur°C) and 120°C"
                    fi
                    press_any_key; clear ;;
                7)
                    print_warning "Restoring to Factory Defaults..."
                    reset_to_factory
                    printf "\n"
                    print_success "Factory defaults restored. Refresh browser."
                    press_any_key; clear ;;
                0) return ;;
                \?|h|H|❓) show_fan_help; clear; continue ;;
                *) print_error "Invalid option"; sleep 1; clear ;;
            esac
            printf "\033[?25l"
        fi
    done
}

# --- Guest Network Bandwidth Limiter ---

show_guestnetwork_help() {
    clear
    print_centered_header "Guest Network Limiter - Help"
    
    cat << 'HELPEOF'
Guest Network Bandwidth Limiter – Quick Help

What is a Bandwidth Limiter?
───────────────────────────
This tool allows you to set a "speed ceiling" for your Guest Wi-Fi. 
Unlike per-client limits, this sets a Global Cap for the entire 
Guest bridge (br-guest). 

Main Benefits:
• Congestion Control: Prevents guests from saturating your 10G/1G line.
• Fair Sharing: Uses 'FQ_CoDel' to ensure one guest's 4K video doesn't 
  cause "lag" or high ping for another guest's Zoom call.
• Priority: Protects your "Home" network's performance during heavy use.

How it Works (The Technical Bit):
────────────────────────────────
• Upload (Egress): Limits traffic leaving the router via br-guest.
• Download (Ingress): Redirects incoming traffic to a virtual device 
  (ifb0) to "shape" the flow before it reaches the guest's device.
• HW Acceleration: Some high-speed routers bypass the CPU. If your 
  limits aren't working, you may need to disable "Network Acceleration" 
  in the GL.iNet Dashboard.

Usage in this Menu:
───────────────────
1. Set Download/Upload: Enter the max speed in Mbps (Megabits). 
   Entering '0' removes the limit for that direction.
2. Persistence: Ensures your limits are reapplied automatically
   after a reboot or a firmware sysupgrade.
3. Reset to Defaults: Cleans all kernel tables, stops the background 
   service, and offers to uninstall the 'tc' power tools.

Testing your Limits:
────────────────────
To verify it's working:
1. Connect a phone or laptop to the GUEST Wi-Fi SSID.
2. Run a speed test (e.g., Speedtest.net or your script's tester).
3. The result should stay slightly below the Mbps you defined.

Note: Setting a limit too low (e.g., < 2 Mbps) may cause some modern 
apps and websites to time out or feel "broken."
HELPEOF
    
    press_any_key
}

manage_guest_limiter() {
    local choice new_dl new_ul
    
    mgl_dependency_check() {
        hash -r
        if ! command -v tc >/dev/null 2>&1; then
            install_package tc-full
            hash -r
        fi
    }

    get_hw_accel_info() {
        # --- 1. Qualcomm Logic (Master) ---
        if [ -f "/etc/config/ecm" ]; then
            if [ "$(uci -q get ecm.global.enabled)" = "1" ]; then
                echo -e "${RED}ENABLED (Qualcomm)${RESET}"
            else
                echo -e "${GREEN}DISABLED (Qualcomm)${RESET}"
            fi
            return
        fi

        # --- 2. MediaTek Logic ---
        if [ -f "/etc/config/mtkhnat" ]; then
            if [ "$(uci -q get mtkhnat.global.enable)" = "1" ]; then
                echo -e "${RED}ENABLED (MediaTek)${RESET}"
            else
                echo -e "${GREEN}DISABLED (MediaTek)${RESET}"
            fi
            return
        fi

        # --- 3. SFE Fallback (For older/non-offloading specific chips) ---
        if [ "$(uci -q get firewall.@defaults[0].flow_offloading)" = "1" ]; then
            echo -e "${RED}ENABLED (SFE/Direct)${RESET}" && return
        else
            echo -e "${GREEN}DISABLED (SFE/Direct)${RESET}" && return
        fi
    
        echo -e "${YELLOW}UNKNOWN${RESET}"
    }

    toggle_admin_access() {
        local action=$1  # "on" or "off"
        local rule_name="guest_admin_access"
        local lan_ip=$(get_lan_ip)
        [ -z "$lan_ip" ] && lan_ip=$(ip -4 addr show br-lan | grep inet | awk '{print $2}' | cut -d/ -f1)
        [ -z "$lan_ip" ] && lan_ip="192.168.8.1"

        # 1. Always start by removing the named rule 
        uci -q delete firewall."$rule_name"

        # 2. Add it back only if we want it ON
        if [ "$action" = "on" ]; then
            uci set firewall."$rule_name"=rule
            uci set firewall."$rule_name".name='Allow-Guest-Admin'
            uci set firewall."$rule_name".src='guest'
            uci set firewall."$rule_name".dest_ip="$lan_ip"
            uci set firewall."$rule_name".target='ACCEPT'
        fi

        # 3. Commit and Reload
        uci commit firewall
        /etc/init.d/firewall reload >/dev/null 2>&1
    }

    while true; do
        # 1. Get Guest Radio Status (Detecting 2.4, 5, and 6G)
        local g24 g50 g60 mlo wstatus dl_status ul_status persist_status
        wrs="0"
        if uci -q get wireless.guest2g >/dev/null; then
            if [ "$(uci -q get wireless.guest2g.disabled)" = "0" ]; then
                g24="${GREEN}ON${RESET}"
                wrs="1"
            else
                g24="${RED}OFF${RESET}"
            fi
        else g24="0"
        fi
        if uci -q get wireless.guest5g >/dev/null; then
            if [ "$(uci -q get wireless.guest5g.disabled)" = "0" ]; then
                g50="${GREEN}ON${RESET}"
                wrs="1"
            else
                g50="${RED}OFF${RESET}"
            fi
        else g50="0"
        fi
        if uci -q get wireless.guest6g >/dev/null; then
            if [ "$(uci -q get wireless.guest6g.disabled)" = "0" ]; then 
                g60="${GREEN}ON${RESET}"
                wrs="1"
            else
                g60="${RED}OFF${RESET}"
            fi
        else
            g60="0"
        fi
        if uci -q get wireless.wlanmldguest2g >/dev/null; then
            mlo="${RED}OFF${RESET}"
            # If ANY MLO band is enabled, set the whole MLO status to ON
            if [ "$(uci -q get wireless.wlanmldguest2g.disabled)" = "0" ] || \
               [ "$(uci -q get wireless.wlanmldguest5g.disabled)" = "0" ] || \
               [ "$(uci -q get wireless.wlanmldguest6g.disabled)" = "0" ]; then
                mlo="${GREEN}ON${RESET}"
                wrs="1"
            fi
        else
            mlo="0"
        fi

        if [ "$g60" = "0" ] && [ "$g50" = "0" ] && [ "$g24" = "0" ] && [ "$mlo" = "0" ]; then
            printf "\n"
            print_error "No wireless interfaces found. Exiting..."
            press_any_key
            return
        fi

        # 2. Get HW acceleration status

        hw_status=$(get_hw_accel_info)
        case "$hw_status" in
            *ENABLED*)
                hw_message="⃗→ Limits Blocked"
                ;;
            *)
                hw_message="→ Limits Ready"
                ;;
        esac
        lan_ipaddr=$(get_lan_ip)

        # 3. Read Current Limits from Init Script
        local hw_state_raw=$(get_hw_accel_info)
        cur_dl=""
        cur_ul=""
        if echo "$hw_state_raw" | grep -q "DISABLED"; then
            if [ -f /etc/init.d/guest_limiter ]; then
                cur_dl=$(grep "LIMIT_DL=" /etc/init.d/guest_limiter 2>/dev/null | cut -d'=' -f2 | tr -d '"')
                cur_ul=$(grep "LIMIT_UL=" /etc/init.d/guest_limiter 2>/dev/null | cut -d'=' -f2 | tr -d '"')
            fi
            [ -z "$cur_dl" ] || [ "$cur_dl" -eq 0 ] && dl_status="${CYAN}UNLIMITED${RESET}" || dl_status="${GREEN}${cur_dl} Mbps${RESET}"
            [ -z "$cur_ul" ] || [ "$cur_ul" -eq 0 ] && ul_status="${CYAN}UNLIMITED${RESET}" || ul_status="${GREEN}${cur_ul} Mbps${RESET}"
        else
            dl_status="${GREY}UNLIMITED (HW Accel Active)${RESET}"
            ul_status="${GREY}UNLIMITED (HW Accel Active)${RESET}"
        fi

         
        # 4. Check Persistence
        grep -q "/etc/init.d/guest_limiter" /etc/sysupgrade.conf 2>/dev/null && persist_status="${GREEN}ENABLED${RESET}" || persist_status="${RED}DISABLED${RESET}"

        # 5. Get Guest network to GL web-ui access
        if uci -q get firewall.guest_admin_access >/dev/null; then
            admin_access="${GREEN}ENABLED${RESET}"
        else
            admin_access="${RED}DISABLED${RESET}"
        fi

        clear
        print_centered_header "Guest Network Bandwidth Limiter"
        printf " %b\n" "${CYAN}INTERFACE STATUS${RESET}"
        [ "$g24" != "0" ] && printf "   Guest Wi-Fi (2.4G): %b\n" "$g24"
        [ "$g50" != "0" ] && printf "   Guest Wi-Fi (5G):   %b\n" "$g50"
        [ "$g60" != "0" ] && printf "   Guest Wi-Fi (6G):   %b\n" "$g60"
        [ "$mlo" != "0" ] && printf "   Guest Wi-Fi (MLO):  %b\n" "$mlo"
        printf "\n"
        printf " %b\n" "${CYAN}CONFIGURATION STATUS${RESET}"
        printf "   Download Limit:     %b\n" "$dl_status"
        printf "   Upload Limit:       %b\n" "$ul_status"
        printf "   Guest -> GL Web UI: %b\n" "$admin_access" 
        printf "   HW Acceleration:    %b %b\n" "$hw_status" "$hw_message"
        printf "   Persistence:        %b\n" "$persist_status"
        printf "\n"
        local g_persist_label="Enable Persistence"
        [ "$persist_status" = "${GREEN}ENABLED${RESET}" ] && g_persist_label="Disable Persistence"
        local g_admin_label="Enable Guest Network to Web UI access"
        [ "$admin_access" = "${GREEN}ENABLED${RESET}" ] && g_admin_label="Disable Guest Network to Web UI access"
        local g_hw_label="Enable HW Acceleration"
        case "$hw_status" in *ENABLED*) g_hw_label="Disable HW Acceleration" ;; esac
        printf " %s  Set Download Limit (Mbps) - 0 to disable\n" "$N1"
        printf " %s  Set Upload Limit   (Mbps) - 0 to disable\n" "$N2"
        printf " %s  %s\n" "$N3" "$g_admin_label"
        printf " %s  %s\n" "$N4" "$g_hw_label"
        printf " %s  %s\n" "$N5" "$g_persist_label"
        printf " %s  Reset to Defaults (Clean Uninstall)\n" "$N6"
        printf " %s  Back\n" "$N0"
        printf " %s Help\n" "$NQ"

        printf "\n Choose [1-6/0/?]: "; read -r choice

        case "$choice" in
            1) 
                if [ "$wrs" = "0" ]; then
                    printf "\n"
                    print_error "No active wireless guest interfaces found."
                    press_any_key
                    continue
                fi
                printf "\n"
                local hw_state_raw=$(get_hw_accel_info)
                if echo "$hw_state_raw" | grep -q "DISABLED"; then
                    read -p " Enter Download Limit (0-10000 Mbps): " new_dl
                    if echo "$new_dl" | grep -qE '^[0-9]+$'; then
                        mgl_dependency_check
                        apply_guest_config "$new_dl" "$cur_ul"
                        press_any_key
                    else
                        print_error "Invalid input. Please enter a whole number."
                        sleep 2
                    fi
                else
                    print_error "HW acceleration must be DISABLED."
                    press_any_key
                fi
                ;;
            2) 
                if [ "$wrs" = "0" ]; then
                    printf "\n"
                    print_error "No active wireless guest interfaces found."
                    press_any_key
                    continue
                fi
                printf "\n"
                local hw_state_raw=$(get_hw_accel_info)
                if echo "$hw_state_raw" | grep -q "DISABLED"; then
                    read -p " Enter Upload Limit (0-10000 Mbps): " new_ul
                    if echo "$new_ul" | grep -qE '^[0-9]+$'; then
                        mgl_dependency_check
                        apply_guest_config "$cur_dl" "$new_ul"
                        press_any_key
                    else
                        print_error "Invalid input. Please enter a whole number."
                        sleep 2
                    fi
                else
                    print_error "HW acceleration must be DISABLED."
                    press_any_key
                fi
                ;;
            3) 
                if [ "$wrs" = "0" ]; then
                    printf "\n"
                    print_error "No active wireless guest interfaces found."
                    press_any_key
                    continue
                fi
                printf "\n"
                if uci -q get firewall.guest_admin_access >/dev/null; then
                    toggle_admin_access "off"
                    print_info "Guest -> Web UI Access: DISABLED."
                else
                    toggle_admin_access "on"
                    print_info "Guest -> Web UI Access: ENABLED."
                fi
                press_any_key
                ;;
            4)
                printf "\n"
                local hw_state_raw=$(get_hw_accel_info)
                if echo "$hw_state_raw" | grep -q "ENABLED"; then
                    print_info "Disabling HW Acceleration..."
                    set_hw_accel 0 >/dev/null 2>&1
                    [ -x /etc/init.d/guest_limiter ] && /etc/init.d/guest_limiter restart >/dev/null 2>&1
                elif echo "$hw_state_raw" | grep -q "DISABLED"; then
                    print_info "Enabling HW Acceleration..."
                    if set_hw_accel 1 >/dev/null 2>&1; then
                        [ -x /etc/init.d/guest_limiter ] && /etc/init.d/guest_limiter stop && /etc/init.d/guest_limiter disable
                    else
                        printf "\n"
                        print_error "Cannot enable Hardware Acceleration. Client speed limits in effect."
                    fi
                else
                    print_error "Unknown hardware engine. Set HW acceleration through Web-UI."
                fi
                press_any_key
                ;;
            5) 
                printf "\n"
                if [ ! -f "/etc/init.d/guest_limiter" ]; then
                    print_warning "No limits configured. Set a limit (Option 1 or 2) first."
                    press_any_key
                    continue
                fi
                
                if [ "$persist_status" = "${GREEN}ENABLED${RESET}" ]; then
                    sed -i '/\/etc\/init.d\/guest_limiter/d' /etc/sysupgrade.conf
                    print_info "Persistence Disabled."
                else
                    if ! grep -q "/etc/init.d/guest_limiter" /etc/sysupgrade.conf; then
                        echo "/etc/init.d/guest_limiter" >> /etc/sysupgrade.conf
                    fi
                    print_info "Persistence Enabled (saved to sysupgrade.conf)."
                fi
                press_any_key
                ;;
            6) 
                if [ "$wrs" = "0" ]; then
                    printf "\n"
                    print_error "No active wireless guest interfaces found."
                    press_any_key
                    continue
                fi
                printf "\n"
                print_info "Restoring to factory settings..."
                printf "\n"
                
                # 1. Stop the service 
                if [ -f "/etc/init.d/guest_limiter" ]; then
                    /etc/init.d/guest_limiter stop >/dev/null 2>&1
                    /etc/init.d/guest_limiter disable >/dev/null 2>&1
                fi
                
                # 2. Hard Cleanup
                tc qdisc del dev br-guest root >/dev/null 2>&1
                tc qdisc del dev br-guest clsact >/dev/null 2>&1
                if [ -d "/sys/class/net/br-guest-ifb" ]; then
                    ip link set dev br-guest-ifb down >/dev/null 2>&1
                    ip link del dev br-guest-ifb >/dev/null 2>&1
                fi

                # 3. Final Hardware Flush (Restore full speed)
                [ -x /etc/init.d/mtk-hwnat ] && /etc/init.d/mtk-hwnat restart >/dev/null 2>&1
                [ -x /etc/init.d/mtk-hwnat-post ] && /etc/init.d/mtk-hwnat-post restart >/dev/null 2>&1
                [ -x /etc/init.d/shortcut-fe ] && /etc/init.d/shortcut-fe restart >/dev/null 2>&1
                [ -x /etc/init.d/bridger ] && /etc/init.d/bridger restart >/dev/null 2>&1

                # 4. Remove Files and Persistence
                rm -f /etc/init.d/guest_limiter
                sed -i '/\/etc\/init.d\/guest_limiter/d' /etc/sysupgrade.conf
                
                cur_dl=0
                cur_ul=0

                # 5. Enable HW Acceleration and Disable Web-UI Access
                toggle_admin_access "off" >/dev/null 2>&1
                if set_hw_accel 1 >/dev/null 2>&1; then 
                    print_success "Guest network limits removed and HW Acceleration restored."
                else
                    print_error "Guest network limits removed. HW Acceleration NOT restored. (User QoS rules may exist)"
                fi
                press_any_key
                ;;
            0) break ;;
            \?|h|H|❓) show_guestnetwork_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}


# Set HW Acceleration
# To Disable: set_hw_accel 0
# To Disable and disabled web-UI toggle: set_hw_accel 0 restrict
# To Enable:  set_hw_accel 1

set_hw_accel() {
    local target_state=$1  # 0 (Off) or 1 (On)
    local mode=$2          # "restrict" to disable web-UI toggle
    local kicked=0

    # --- A. PRE-FLIGHT & UI LOCK MANAGEMENT ---
    if [ "$target_state" = "1" ]; then
        # 1. Precision Check: Block enable if REAL user QoS rules exist
        local real_limits=$(uci show qos | grep "\.mac=" | grep -v "00:00:00:00:00:00" | wc -l)
        if [ "$real_limits" -gt 0 ]; then
            return 1
        fi
        
        # 2. Surgical Unlock: Remove our padlock 
        uci -q delete qos.000000000000
        local idx=0
        while [ -n "$(uci -q get qos.@client[$idx])" ]; do
            if [ "$(uci -q get qos.@client[$idx].mac)" = "00:00:00:00:00:00" ]; then
                uci delete qos.@client[$idx]
            else
                idx=$((idx + 1))
            fi
        done
        uci commit qos
    else
        # 3. Handle Disabling: Apply UI padlock only if in 'restrict' mode
        if [ "$mode" = "restrict" ]; then
            uci set qos.000000000000=queue
            uci set qos.000000000000.mac='00:00:00:00:00:00'
            uci set qos.000000000000.download='1000000'
            uci set qos.000000000000.upload='1000000'
            uci set qos.000000000000.cnt='1'
            uci commit qos
        else
            uci -q delete qos.000000000000
            local idx=0
            while [ -n "$(uci -q get qos.@client[$idx])" ]; do
                if [ "$(uci -q get qos.@client[$idx].mac)" = "00:00:00:00:00:00" ]; then
                    uci delete qos.@client[$idx]
                else
                    idx=$((idx + 1))
                fi
            done
            uci commit qos
        fi
    fi
    
    # 1. OPENWRT FIREWALL OFFLOADING
    # Skip raw firewall offload on Qualcomm/ECM routers to prevent Web UI bugs
    if [ ! -f "/etc/config/ecm" ]; then
        uci -q set firewall.@defaults[0].flow_offloading="$target_state"
        uci -q set firewall.@defaults[0].flow_offloading_hw="$target_state"
        uci -q set firewall.@defaults[0].nss_offloading="$target_state"
        uci commit firewall
    fi

    # 2. HARDWARE SPECIFIC: Qualcomm 
    if [ -f "/etc/config/ecm" ] && [ -x "/etc/init.d/qca-nss-ecm" ]; then
        uci set ecm.global.enabled="$target_state"
        uci commit ecm
        if [ "$target_state" = "0" ]; then
            /etc/init.d/qca-nss-ecm stop
            [ -e /sys/kernel/debug/ecm/ecm_db/defunct_all ] && echo 1 > /sys/kernel/debug/ecm/ecm_db/defunct_all
        else
            /etc/init.d/qca-nss-ecm start
        fi
        kicked=1
    fi

    # 3. HARDWARE SPECIFIC: MediaTek 
    if [ -f "/etc/config/mtkhnat" ] && [ -x "/etc/init.d/mtk-hwnat-post" ]; then
        uci set mtkhnat.global.enable="$target_state"
        uci commit mtkhnat
        if [ "$target_state" = "0" ]; then
            /etc/init.d/mtk-hwnat-post stop
        else
            /etc/init.d/mtk-hwnat-post start
        fi
        kicked=1
    fi

    # 4. THE CATCH-ALL: Standard/Beryl (MT1300) or Unknown
    if [ "$kicked" -eq 0 ]; then
        /etc/init.d/firewall reload >/dev/null 2>&1
    fi

    # 5. UI SYNC: Ensure gl_eqos picks up the ghost changes immediately
    [ -x /usr/bin/gl_eqos ] && /usr/bin/gl_eqos restart >/dev/null 2>&1
}

# Apply Function (Internal Template Generation)

apply_guest_config() {
    local dl=$1
    local ul=$2
    [ -z "$dl" ] && dl=0
    [ -z "$ul" ] && ul=0
    
    # 1. Convert to kbit with overhead (2% DL, 4% UL)
    local dl_kbit=$(( dl * 1020 ))
    local ul_kbit=$(( ul * 1040 ))

    # 2. Uninstall if 0/0
    if [ "$dl" -eq 0 ] && [ "$ul" -eq 0 ]; then
        if [ -f "/etc/init.d/guest_limiter" ]; then
            /etc/init.d/guest_limiter stop >/dev/null 2>&1
            /etc/init.d/guest_limiter disable >/dev/null 2>&1
            rm -f /etc/init.d/guest_limiter
        fi
        printf "\n"
        print_info "Guest network limits removed."
        return
    fi

    # 3. Create the Init Script
    cat <<EOF > /etc/init.d/guest_limiter
#!/bin/sh /etc/rc.common
# LIMIT_DL=$dl
# LIMIT_UL=$ul
START=99

# --- CLEANUP ---
clean_all() {
    [ -x /usr/bin/gl_eqos ] && /usr/bin/gl_eqos stop >/dev/null 2>&1
    tc qdisc del dev br-guest root >/dev/null 2>&1
    tc qdisc del dev br-guest clsact >/dev/null 2>&1
    if [ -d "/sys/class/net/br-guest-ifb" ]; then
        tc qdisc del dev br-guest-ifb root >/dev/null 2>&1
        ip link set dev br-guest-ifb down >/dev/null 2>&1
        ip link del dev br-guest-ifb >/dev/null 2>&1
    fi
    sleep 1
}

start() {
    local i=0
    while [ ! -d "/sys/class/net/br-guest" ] && [ \$i -lt 30 ]; do
        sleep 1
        i=\$((i+1))
    done
    clean_all
    # --- SETUP UPLOAD PIPE ---
    # Upload Control (fq_codel + HTB)
    if [ "$ul" != "0" ]; then
        ip link add dev br-guest-ifb type ifb
        ip link set dev br-guest-ifb up
        
        tc qdisc add dev br-guest-ifb root handle 1: htb default 1
        tc class add dev br-guest-ifb parent 1: classid 1:1 htb rate ${ul_kbit}kbit ceil ${ul_kbit}kbit burst 15k cbuffer 15k
 
        # --- THE REDIRECT HOOK ---
        tc qdisc add dev br-guest clsact
        tc filter add dev br-guest ingress protocol ip u32 match u32 0 0 action mirred egress redirect dev br-guest-ifb
        tc filter add dev br-guest ingress protocol ipv6 u32 match u32 0 0 action mirred egress redirect dev br-guest-ifb
    fi

    # --- SETUP DOWNLOAD PIPE ---
    if [ "$dl" != "0" ]; then
        tc qdisc add dev br-guest root handle 1: htb default 1
        tc class add dev br-guest parent 1: classid 1:1 htb rate ${dl_kbit}kbit ceil ${dl_kbit}kbit burst 15k cbuffer 15k
    fi

    # --- HARDWARE ACCELERATION FLUSH ---
    [ -x /etc/init.d/mtk-hwnat ] && /etc/init.d/mtk-hwnat restart 2>/dev/null
    [ -x /etc/init.d/mtk-hwnat-post ] && /etc/init.d/mtk-hwnat-post restart 2>/dev/null
    [ -x /etc/init.d/shortcut-fe ] && /etc/init.d/shortcut-fe restart 2>/dev/null
    [ -x /etc/init.d/bridger ] && /etc/init.d/bridger restart >/dev/null 2>&1
}

stop() {
    clean_all    
    [ -x /etc/init.d/mtk-hwnat ] && /etc/init.d/mtk-hwnat restart 2>/dev/null
    [ -x /etc/init.d/mtk-hwnat-post ] && /etc/init.d/mtk-hwnat-post restart 2>/dev/null
    [ -x /etc/init.d/shortcut-fe ] && /etc/init.d/shortcut-fe restart 2>/dev/null
    [ -x /etc/init.d/bridger ] && /etc/init.d/bridger restart >/dev/null 2>&1
}
EOF

    # 4. Finalize and Launch
    set_hw_accel 0 restrict
    chmod +x /etc/init.d/guest_limiter
    /etc/init.d/guest_limiter enable
    /etc/init.d/guest_limiter restart
    printf "\n"
    print_success "Configured: $dl Mbps Down / $ul Mbps Up"
}

# --- Web-UI Terminal Manager ---
show_terminal_help() {
    clear
    print_centered_header "Web Terminal Management - Help"
    
    cat << 'HELPEOF'
Web Terminal (ttyd) Management – Quick Help

What is the Web Terminal?
───────────────────────────
This tool embeds a fully functional Linux terminal directly into your 
GL.iNet Admin Panel. It allows you to execute commands, edit configs, 
and manage your router without needing an external SSH client.

Main Benefits:
• Zero Config: Access your shell from any browser (Safari/Chrome/Edge).
• Secure: Uses '/bin/login' to require your root password.
• Integrated: Adds a custom icon ( >_ ) to the top navigation bar.

How it Works (The Technical Bit):
────────────────────────────────
• Backend (ttyd): A lightweight C-based terminal-to-web server that 
  runs as a Procd service (Start Priority: 99).
• Frontend (JS Injection): Patches the 'app.*.js.gz' file in /www/js/ 
  to inject a draggable, minimizable terminal modal.
• The "Fast-UI" Label: The window header automatically pulls your 
  router's model (e.g., gl-be3600) from the browser's LocalStorage 
  to match a native macOS/Linux terminal feel.

Usage in this Menu:
───────────────────
1. Install & Deploy: Automatically installs the 'ttyd' package, 
   configures the black-background theme via UCI, starts the service, 
   and injects the Web UI button.
2. Disable Service & UI: Stops the background process and reverts the 
   Admin Panel JS to its original ROM state. The 'ttyd' package 
   remains installed for quick re-activation.
3. Completely Uninstall: Stops the service, uninstalls the 'ttyd' 
   binary, deletes its config, and restores the factory UI.

Important UX Notes:
────────────────────
• Hard Refresh: After deploying or disabling, you MUST perform a 
  "Hard Refresh" (Cmd+Shift+R or Ctrl+F5) in your browser. This 
  clears the Nginx cache ( /var/lib/nginx ) and forces the new UI.
• Security: The service is bound to the 'LAN' interface by default. 
  It is not accessible from the WAN (Internet) unless you manually 
  open Port 7681 in the firewall.
• Persistence: Configuration is handled via UCI (/etc/config/ttyd), 
  ensuring your terminal settings survive a reboot.

Note: If the icon does not appear after a refresh, ensure "Network 
Acceleration" isn't preventing the UI from updating, though the 
script attempts to force this by clearing the Nginx cache.
HELPEOF
    
    press_any_key
}

manage_web_terminal() {
    while true; do
        clear
        print_centered_header "Web-UI Terminal Interface"
        
        TARGET_GZ=$(ls /www/js/app.*.js.gz | head -n 1)
        if [ -z "$TARGET_GZ" ]; then
            print_error "Cannot find target JS file for patching. Exiting..."
            press_any_key
            return
        fi
        
        # Check Service Status via Procd
        if pgrep ttyd >/dev/null; then
            if grep -q "option ssl '1'" /etc/config/ttyd 2>/dev/null; then
                svc_status="${GREEN}RUNNING (HTTPS)${RESET}"
            else
                svc_status="${GREEN}RUNNING (HTTP)${RESET}"
            fi
        else
            svc_status="${RED}STOPPED${RESET}"
        fi
        
        zcat "$TARGET_GZ" 2>/dev/null | grep -q "term-wrapper" && inj_status="${GREEN}ENABLED${RESET}" || inj_status="${YELLOW}DISABLED${RESET}"
        
        printf " %b\n" "${CYAN}STATUS${RESET}"
        printf "   ttyd Service:   %b\n" "$svc_status"
        printf "   Web UI Button:  %b\n\n" "$inj_status"
        
        printf "%s  Enable Web-UI Terminal\n" "$N1"
        printf "%s  Disable Web-UI Terminal\n" "$N2"
        printf "%s  Completely Uninstall\n" "$N3"
        printf "%s  Back\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-3/0/?]: "
        read -r term_choice
        printf "\n"
        
        case $term_choice in
            1)
                ttyd_proto="http"
                hash -r
                if pgrep ttyd >/dev/null; then
                    if [ "$inj_status" = "${GREEN}ENABLED${RESET}" ]; then
                         print_warning "Web-UI Terminal is already running and patched."
                         press_any_key
                         continue
                    else
                         grep -q "option ssl '1'" /etc/config/ttyd 2>/dev/null && ttyd_proto="https"
                         print_warning "Web-UI Terminal service is running but UI is not patched. Re-patching..."
                    fi
                else
                    if ! command -v ttyd >/dev/null 2>&1; then
                        install_package ttyd
                    fi

                    print_info "Configuring ttyd service..."
                    printf "\n"

                    # Detect HTTPS mode and prompt for connection mode
                    redirect_https=$(uci -q get uhttpd.main.redirect_https 2>/dev/null)
                    if [ "$redirect_https" = "1" ]; then
                        print_warning "The GL Admin Panel is set to force HTTPS. ttyd will be installed in HTTPS mode so the\n   embedded terminal loads correctly in your browser.\n"
                        ttyd_proto="https"
                    else
                        print_info "ttyd runs over HTTP by default and will not work when accessing the Admin Panel via HTTPS.\n   ttyd over HTTPS works when accessing the Admin Panel via HTTP or HTTPS but requires a\n   one-time browser cert acceptance."
                        printf "   Use HTTPS? [y/N]: "
                        read -r proto_choice
                        printf "\n"
                        [ "$proto_choice" = "y" ] || [ "$proto_choice" = "Y" ] && ttyd_proto="https"
                    fi

                    # Generate cert if HTTPS chosen
                    if [ "$ttyd_proto" = "https" ]; then
                        if [ ! -f /etc/ttyd.crt ] || [ ! -f /etc/ttyd.key ]; then
                            print_info "Generating self-signed certificate for ttyd..."
                            printf "\n"
                            openssl req -x509 -nodes -newkey rsa:2048 \
                                -keyout /etc/ttyd.key \
                                -out /etc/ttyd.crt \
                                -days 3650 \
                                -subj "/CN=gl-router" >/dev/null 2>&1
                            print_success "Generated /etc/ttyd.crt"
                            printf "\n"
                            print_success "Generated /etc/ttyd.key"
                            printf "\n"
                        else
                            print_info "SSL certificates already exist, reusing."
                            printf "\n"
                        fi
                    fi

                    # Write UCI config
                    if [ "$ttyd_proto" = "https" ]; then
                        cat << 'UCIEOF' > /etc/config/ttyd
config ttyd
	option enable '1'
	option port '7681'
	option interface '@lan'
	option command '/bin/login'
	option ssl '1'
	option ssl_cert '/etc/ttyd.crt'
	option ssl_key '/etc/ttyd.key'
	list client_option 'scrollback=10000'
	list client_option 'theme={"background":"#000000"}'
	list client_option 'titleFixed="Terminal"'
UCIEOF
                        lan_ip=$(get_lan_ip)
                        print_warning "Before using the terminal, open a new tab and visit: ${CYAN}https://${lan_ip}:7681${RESET}"
                        print_warning "You must accept the certificate warning, then return to the Admin Panel."
                        print_warning "The terminal will not load until this is done!"
                        printf "\n"
                    else
                        cat << 'UCIEOF' > /etc/config/ttyd
config ttyd
	option enable '1'
	option port '7681'
	option interface '@lan'
	option command '/bin/login'
	list client_option 'scrollback=10000'
	list client_option 'theme={"background":"#000000"}'
	list client_option 'titleFixed="Terminal"'
UCIEOF
                    fi

                    /etc/init.d/ttyd enable
                    /etc/init.d/ttyd restart >/dev/null 2>&1

                fi
               
                # UI Injection 
                print_info "Patching Web-UI..."
                printf "\n"
                TARGET_JS="${TARGET_GZ%.gz}"
                cp -f "/rom$TARGET_GZ" "$TARGET_GZ"
                zcat "$TARGET_GZ" > "$TARGET_JS"

                # JS Patch logic
                cat << 'EOF' >> "$TARGET_JS"
;(function(){
  const inject = () => {
    if (document.getElementById('term-wrapper')) return;
    const anchor = document.querySelector('.icon-reboot');
    if (!anchor) return;
    const rs = window.getComputedStyle(anchor);
    const rml = parseInt(rs.marginLeft)||0, rmr = parseInt(rs.marginRight)||0;
    const wML = rml > 0 ? rml+'px' : '0px';
    const wMR = rml > 0 ? '0px' : rmr+'px';
    const wrapper = document.createElement('span');
    wrapper.id = 'term-wrapper';
    wrapper.className = 'btn-icon';
    wrapper.style.cssText = 'margin-left:'+wML+'; margin-right:'+wMR+'; display:inline-flex; align-items:center; cursor:pointer; color:#606266; font-size:18px;';
    wrapper.innerHTML = ' >_ ';
    wrapper.onclick = () => {
      if(document.getElementById('term-modal')) return;
      const host = window.location.hostname;
      const aliasEl = document.querySelector('.alias span');
      const hostLabel = (aliasEl && aliasEl.innerText.trim())
                        ? aliasEl.innerText.trim().toLowerCase()
                        : host;
      const modal = document.createElement('div');
      modal.id = 'term-modal';
      modal.style.cssText = 'position:fixed; top:10%; left:10%; width:70%; height:60%; background:#000 !important; z-index:9999; border-radius:10px; box-shadow:0 20px 50px rgba(0,0,0,0.9); overflow:hidden; border:1px solid #444; min-width:300px;';
      const head = document.createElement('div');
      head.id = 'term-header';
      head.style.cssText = 'background:#1a1a1a; padding:10px 15px; display:flex; justify-content:space-between; align-items:center; cursor:move; user-select:none; border-bottom:1px solid #333;';
      const popOutSvg = '<svg width="14" height="14" viewBox="0 0 512 512" fill="#00a8ff" style="cursor:pointer;"><path d="M432 320H400a16 16 0 0 0-16 16v112H64V128h112a16 16 0 0 0 16-16V80a16 16 0 0 0-16-16H48a48 48 0 0 0-48 48v400a48 48 0 0 0 48 48h352a48 48 0 0 0 48-48V336a16 16 0 0 0-16-16zM488 0H360c-21.37 0-32.05 25.91-17 41l35.73 35.73L135 320.37a24 24 0 0 0 0 34L157.67 377a24 24 0 0 0 34 0l243.61-243.68L471 169c15 15 41 4.47 41-17V24a24 24 0 0 0-24-24z"/></svg>';
      head.innerHTML = '<div style="display:flex; gap:8px;"><div id="t-cls" style="width:12px;height:12px;background:#ff5f56;border-radius:50%;cursor:pointer;"></div><div id="t-min" style="width:12px;height:12px;background:#ffbd2e;border-radius:50%;cursor:pointer;"></div><div id="t-max" style="width:12px;height:12px;background:#27c93f;border-radius:50%;cursor:pointer;"></div></div><span style="color:#888;font-family:monospace;font-size:11px;pointer-events:none;">root@'+hostLabel+': ~</span><div id="t-pop">'+popOutSvg+'</div>';
      const ifrm = document.createElement('iframe');
      const termUrl = 'http://' + host + ':7681/';
      ifrm.src = termUrl;
      ifrm.style.cssText = 'width:100%; height:calc(100% - 38px); border:none; background:#000;';
      modal.appendChild(head); modal.appendChild(ifrm); document.body.appendChild(modal);
      const setTrans = (on) => modal.style.transition = on ? 'all 0.3s ease-in-out' : 'none';
      document.getElementById('t-pop').onclick = (e) => { e.stopPropagation(); window.open(termUrl,'_blank'); modal.remove(); };
      document.getElementById('t-cls').onclick = () => modal.remove();
      let isMin = false, minOldStyle = {};
      document.getElementById('t-min').onclick = () => {
        setTrans(true);
        if (!isMin) {
          minOldStyle = { top:modal.style.top, left:modal.style.left, width:modal.style.width, height:modal.style.height, bottom:modal.style.bottom, right:modal.style.right };
          Object.assign(modal.style, { top:'auto', left:'auto', bottom:'20px', right:'20px', width:'250px', height:'38px' });
          ifrm.style.display = 'none';
          resizeHandle.style.display = 'none';
        } else {
          ifrm.style.display = 'block';
          resizeHandle.style.display = '';
          setTrans(false);
          Object.assign(modal.style, { top:'auto', left:'auto', bottom:'20px', right:'20px', width:minOldStyle.width, height:minOldStyle.height });
          requestAnimationFrame(() => requestAnimationFrame(() => {
            setTrans(true);
            Object.assign(modal.style, { top:minOldStyle.top||'10%', left:minOldStyle.left||'10%', bottom:minOldStyle.bottom||'auto', right:minOldStyle.right||'auto', width:minOldStyle.width, height:minOldStyle.height });
          }));
        }
        isMin = !isMin;
      };
      let isMax = false, maxOldPos = {};
      document.getElementById('t-max').onclick = () => {
        setTrans(true);
        if (!isMax) {
          maxOldPos = { t:modal.style.top, l:modal.style.left, w:modal.style.width, h:modal.style.height, b:modal.style.bottom, r:modal.style.right };
          Object.assign(modal.style, { top:'0', left:'0', width:'100%', height:'100%', borderRadius:'0', bottom:'auto', right:'auto' });
        } else {
          Object.assign(modal.style, { top:maxOldPos.t, left:maxOldPos.l, width:maxOldPos.w, height:maxOldPos.h, bottom:maxOldPos.b, right:maxOldPos.r, borderRadius:'10px' });
        }
        isMax = !isMax;
      };
      head.onmousedown = (e) => {
        if (e.target.id.startsWith('t-')) return;
        const rect = modal.getBoundingClientRect();
        setTrans(false);
        modal.style.top = rect.top + 'px';
        modal.style.left = rect.left + 'px';
        modal.style.bottom = 'auto';
        modal.style.right = 'auto';
        let ox = e.clientX - rect.left, oy = e.clientY - rect.top;
        document.onmousemove = (e) => { modal.style.left=(e.clientX-ox)+'px'; modal.style.top=(e.clientY-oy)+'px'; };
        document.onmouseup = () => { document.onmousemove = null; };
      };
      const resizeHandle = document.createElement('div');
      resizeHandle.style.cssText = 'position:absolute; bottom:0; right:0; width:12px; height:12px; cursor:se-resize; z-index:10001; background:linear-gradient(135deg, transparent 50%, #888 50%);';
      modal.appendChild(resizeHandle);
      resizeHandle.onmousedown = (e) => {
        e.preventDefault();
        e.stopPropagation();
        const startX = e.clientX, startY = e.clientY;
        const startW = modal.offsetWidth, startH = modal.offsetHeight;
        ifrm.style.pointerEvents = 'none';
        document.onmousemove = (e) => {
          modal.style.width  = Math.max(300, startW + e.clientX - startX) + 'px';
          modal.style.height = Math.max(100, startH + e.clientY - startY) + 'px';
        };
        document.onmouseup = () => { document.onmousemove = null; ifrm.style.pointerEvents = ''; };
      };
    };
    const _anc=[]; let _n=anchor;
    while(_n){_anc.push(_n);_n=_n.parentElement;}
    let _h=document.querySelector('.icon-question-circle');
    while(_h&&!_anc.includes(_h.parentElement))_h=_h.parentElement;
    const _fp=_h?_h.parentElement:anchor.parentNode;
    let _ru=anchor;
    while(_ru.parentElement!==_fp)_ru=_ru.parentElement;
    _fp.insertBefore(wrapper,_ru);
  };
  setInterval(inject,1000);
})();
EOF
                [ "$ttyd_proto" = "https" ] && sed -i 's|http://|https://|g' "$TARGET_JS"
                gzip -c "$TARGET_JS" > "$TARGET_GZ"
                rm -f "$TARGET_JS"
                rm -rf /var/lib/nginx/*
                print_success "Web-UI Terminal Installed. \n   Please perform a HARD REFRESH (Ctrl+F5 or Cmd+Shift+R) in your browser to see the changes."
                press_any_key
                ;;

            2)
                print_info "Disabling Web Terminal..."
                printf "\n"
                
                # Only attempt to stop/disable if the service script exists
                
                if [ -f "/etc/init.d/ttyd" ]; then
                    if pgrep ttyd >/dev/null; then
                        print_info "Stopping ttyd service..."
                        printf "\n"
                        /etc/init.d/ttyd stop 2>/dev/null
                        /etc/init.d/ttyd disable 2>/dev/null
                        killall ttyd >/dev/null 2>&1
                        print_success "Service stopped."
                        printf "\n"
                    else
                        print_warning "ttyd service is not running."
                        printf "\n"
                    fi
                else
                    print_warning "ttyd service not found; skipping service stop."
                    printf "\n"
                fi

                # Restore UI to stock regardless of service status
                if [ -f "/rom$TARGET_GZ" ]; then
                    cp -f "/rom$TARGET_GZ" "$TARGET_GZ"
                    rm -rf /var/lib/nginx/*
                    print_success "Web UI button removed and cache cleared."
                    printf "\n"
                    print_info "Please perform a HARD REFRESH (Ctrl+F5 or Cmd+Shift+R) in your browser."
                else
                    print_error "ROM backup not found. Manual UI restoration required."
                fi
                press_any_key
                ;;

            3)
                print_warning "Completely Uninstalling ttyd..."
                printf "\n"
                
                # Stop service before removal if it exists
                if command -v ttyd >/dev/null 2>&1 || [ -f "/etc/init.d/ttyd" ]; then
                    if pgrep ttyd >/dev/null; then
                        print_info "Stopping ttyd service..."
                        printf "\n"
                        /etc/init.d/ttyd stop 2>/dev/null
                        killall ttyd >/dev/null 2>&1
                        print_success "Service stopped."
                        printf "\n"
                    else
                        print_warning "ttyd service is not running."
                        printf "\n"
                    fi
                    opkg remove --autoremove ttyd >/dev/null 2>&1
                    rm -f /etc/config/ttyd
                    if [ -f /etc/ttyd.crt ] || [ -f /etc/ttyd.key ]; then
                        print_info "Removing ttyd SSL certificates..."
                        printf "\n"
                        rm -f /etc/ttyd.crt /etc/ttyd.key
                        print_success "SSL certificates removed."
                        printf "\n"
                    fi
                    print_success "ttyd package uninstalled."
                    printf "\n"
                fi

                # Always ensure the UI is restored
                if [ -f "/rom$TARGET_GZ" ]; then
                    cp -f "/rom$TARGET_GZ" "$TARGET_GZ"
                    rm -rf /var/lib/nginx/*
                    print_success "Web UI button removed and cache cleared."
                else
                    print_error "ROM backup not found. Manual UI restoration required."
                fi
                press_any_key
                ;;
            0) return ;;
            \?|h|H|❓) show_terminal_help ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# --- Manage Packages ---

get_action_text() {
    local t_i=$1 local t_p=$2 local o_i=$3 local o_p=$4
    
    if [ "$t_i" -eq "$o_i" ] && [ "$t_p" -eq "$o_p" ]; then
        echo "No Change"
    elif [ "$t_i" -eq 1 ] && [ "$o_i" -eq 0 ]; then
        [ "$t_p" -eq 1 ] && echo "> Install + Persist" || echo "> Install Package"
    elif [ "$t_i" -eq 1 ] && [ "$o_i" -eq 1 ] && [ "$t_p" -ne "$o_p" ]; then
        [ "$t_p" -eq 1 ] && echo "> Enable Persistence" || echo "> Disable Persistence"
    elif [ "$t_i" -eq 0 ] && [ "$o_i" -eq 1 ]; then
        [ "$o_p" -eq 1 ] && echo "> Remove + Unpersist" || echo "> Remove Package"
    else
        echo "No Change"
    fi
}

create_lazarus_hook() {
    local hook="/etc/uci-defaults/99-lazarus"
    cat << 'EOF' > "$hook"
#!/bin/sh
# Lazarus Survival Engine - Post-Upgrade Package Restoration Hook
if [ -f /etc/lazarus.list ]; then
    opkg update
    cat /etc/lazarus.list | xargs opkg install
fi
# Re-persist the healer list itself
grep -qFx "/etc/lazarus.list" /etc/sysupgrade.conf || echo "/etc/lazarus.list" >> /etc/sysupgrade.conf
exit 0
EOF
    chmod +x "$hook"
}

manage_packages() {
    # Define the Utility Database (Package|Binary|Config/Service Files)
    # Types: R = Reinstall (Complex), B = Binary (Simple)
    local UTILITY_DB="zram-swap|/etc/init.d/zram|R|/etc/init.d/zram /etc/config/system
librespeed-go|/usr/bin/librespeed-go|R|/usr/bin/librespeed-go /etc/config/librespeed-go /etc/init.d/librespeed-go
stress|/usr/bin/stress|B|/usr/bin/stress
stress-ng|/usr/bin/stress-ng|B|/usr/bin/stress-ng
lscpu|/usr/bin/lscpu|B|/usr/bin/lscpu
apache|/usr/bin/htpasswd|R|/usr/bin/htpasswd
htop|/usr/bin/htop|B|/usr/bin/htop
rsync|/usr/bin/rsync|B|/usr/bin/rsync
vim-fuller|/usr/bin/vim|R|/usr/bin/vim
speedtest|/usr/bin/speedtest|B|/usr/bin/speedtest /root/.config/ookla/speedtest-cli.json"

    local map_file="/tmp/pkg_manage_map"
    local sys_conf="/etc/sysupgrade.conf"
    local laz_list="/etc/lazarus.list"
    
    # Initialization: Scan current system state
    init_system_state(){
    [ -f "$map_file" ] && rm -f "$map_file"
    local i=1
    echo "$UTILITY_DB" | while IFS='|' read -r name bin type paths; do
        local inst=0; [ -f "$bin" ] && inst=1
        local pers=0
        # Check if any of its paths are in sysupgrade.conf
        for p in $paths; do
            if grep -qFx "$p" "$sys_conf" 2>/dev/null; then pers=1; break; fi
        done
        # Format: Index|Name|Target_I|Target_P|Action|Type|Paths|Orig_I|Orig_P
        echo "$i|$name|$inst|$pers|No Change|$type|$paths|$inst|$pers" >> "$map_file"
        i=$((i+1))
    done
    }

    init_system_state

    while true; do
        clear
        print_centered_header "Package & Persistence Manager"
        printf "       %-7s %-7s %-19s %s\n" "Install" "Persist" "Package Name" "Planned Action"
        printf " ───────────────────────────────────────────────────────────\n"

        while IFS='|' read -r idx name i_t p_t action type paths o_i o_p; do
            local i_box="  [ ]  "; [ "$i_t" -eq 1 ] && i_box="  [✓]  "
            local p_box="  [ ]  "; [ "$p_t" -eq 1 ] && p_box="  [✓]  "

            printf " %-5s %s %s %-19s %b%s%b\n" "$idx." "$i_box" "$p_box" "$name" "${CYAN}" "$action" "${RESET}"
        done < "$map_file"

        printf " ───────────────────────────────────────────────────────────\n"
        printf " [A] All   [N] None   [#] Toggle   [C] Confirm   [0] Cancel   [?] Help\n"
        pkg_count=$(wc -l < "$map_file" 2>/dev/null | tr -dc '0-9')
        printf "\n Choose [%s/A/N/C/0/?]: " "$(picker_range "$pkg_count")"
        read -r cmd
        cmd=$(echo "$cmd" | tr 'A-Z' 'a-z')

        case "$cmd" in
            a|A) 
                # Step 1: Force targets to 1|1 for all rows
                awk -F'|' -v OFS='|' '{$3=1; $4=1; print}' "$map_file" > "${map_file}.tmp"
                
                # Step 2: Re-calculate the "Smart" action text for all 9 columns
                while IFS='|' read -r idx name ti tp act type paths oi op; do
                    new_act=$(get_action_text 1 1 "$oi" "$op")
                    echo "$idx|$name|1|1|$new_act|$type|$paths|$oi|$op"
                done < "${map_file}.tmp" > "$map_file"
                rm -f "${map_file}.tmp"
                ;;
            n|N)
                # Step 1: Force targets to 0|0 for all rows
                awk -F'|' -v OFS='|' '{$3=0; $4=0; print}' "$map_file" > "${map_file}.tmp"
                
                # Step 2: Re-calculate the "Smart" action text for all 9 columns
                while IFS='|' read -r idx name ti tp act type paths oi op; do
                    new_act=$(get_action_text 0 0 "$oi" "$op")
                    echo "$idx|$name|0|0|$new_act|$type|$paths|$oi|$op"
                done < "${map_file}.tmp" > "$map_file"
                rm -f "${map_file}.tmp"
                ;;
            [1-9]*)
                if grep -q "^$cmd|" "$map_file"; then
                    local line=$(grep "^$cmd|" "$map_file")
                    # Extract columns (Note the new positions for Orig_I and Orig_P)
                    local name=$(echo "$line" | cut -d'|' -f2)
                    local cur_i=$(echo "$line" | cut -d'|' -f3)
                    local cur_p=$(echo "$line" | cut -d'|' -f4)
                    local type=$(echo "$line" | cut -d'|' -f6)
                    local paths=$(echo "$line" | cut -d'|' -f7)
                    local o_i=$(echo "$line" | cut -d'|' -f8)
                    local o_p=$(echo "$line" | cut -d'|' -f9)
                    
                    # 3-Way Cycle: (0,0) -> (1,0) -> (1,1) -> Back to (0,0)
                    local next_i=0; local next_p=0
                    if [ "$cur_i" -eq 0 ] && [ "$cur_p" -eq 0 ]; then
                        next_i=1; next_p=0
                    elif [ "$cur_i" -eq 1 ] && [ "$cur_p" -eq 0 ]; then
                        next_i=1; next_p=1
                    else
                        next_i=0; next_p=0
                    fi
                    
                    # Get the smart action text based on the NEW targets vs ORIGINAL live state
                    local next_act=$(get_action_text "$next_i" "$next_p" "$o_i" "$o_p")
                    
                    # Update the map file
                    grep -v "^$cmd|" "$map_file" > "${map_file}.tmp"
                    echo "$cmd|$name|$next_i|$next_p|$next_act|$type|$paths|$o_i|$o_p" >> "${map_file}.tmp"
                    sort -n "${map_file}.tmp" > "$map_file" && rm -f "${map_file}.tmp"
                fi
                ;;
            c)
                # 1. Build Confirmation Lists
                local to_add=""; local to_rem=""
                while IFS='|' read -r idx name t_i t_p action type paths o_i o_p; do
                    # Skip if no change
                    [ "$action" == "No Change" ] && continue

                    # Match specific strings for Additions
                    case "$action" in
                        "> Install Package")
                            to_add="${to_add}\n  + $name (Install)"
                            ;;
                        "> Install + Persist")
                            to_add="${to_add}\n  + $name (Install + Persist)"
                            ;;
                        "> Enable Persistence")
                            to_add="${to_add}\n  + $name (Persist)"
                            ;;
                    esac

                    # Match specific strings for Removals
                    case "$action" in
                        "> Remove Package")
                            to_rem="${to_rem}\n  - $name (Remove)"
                            ;;
                        "> Remove + Unpersist")
                            to_rem="${to_rem}\n  - $name (Remove + Unpersist)"
                            ;;
                        "> Disable Persistence")
                            to_rem="${to_rem}\n  - $name (Unpersist)"
                            ;;
                    esac
                done < "$map_file"

                if [ -z "$to_add" ] && [ -z "$to_rem" ]; then
                    print_error "No changes planned."; sleep 2; continue
                fi

                clear
                print_centered_header "Confirm System Changes"
                [ -n "$to_add" ] && { printf "${GREEN}TO BE INSTALLED or PERSISTED:${RESET}"; printf "$to_add\n\n"; }
                [ -n "$to_rem" ] && { printf "${RED}TO BE REMOVED or UNPERSISTED:${RESET}"; printf "$to_rem\n\n"; }
                
                printf "Proceed with changes? [y/N]: "; read -r confirm; printf "\n"
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    install_fail=0
                    # map_file columns: idx|name|i_t|p_t|action|type|paths|o_i|o_p
                    while IFS='|' read -r idx name i_t p_t action type paths o_i o_p; do
                        [ "$action" == "No Change" ] && continue
                        
                        # EXECUTE REMOVALS
                        if [[ "$action" == *"> Remove"* ]] || [[ "$action" == *"> Unpersist"* ]]; then
                            if [ "$i_t" -eq 0 ]; then
                                if [ "$name" == "speedtest" ]; then
                                    rm -f /usr/bin/speedtest
                                else
                                    opkg remove --autoremove "$name" >/dev/null 2>&1
                                fi
                            fi
                            
                            # Standard cleanup for paths and survival lists
                            for p in $paths; do sed -i "\|$p|d" "$sys_conf" 2>/dev/null; done
                            [ -f "$laz_list" ] && sed -i "\|$name|d" "$laz_list" 2>/dev/null
                        fi

                        # EXECUTE INSTALLS
                        if [[ "$action" == *"Install"* ]] || [[ "$action" == *"Persist"* ]]; then
                            if [ "$i_t" -eq 1 ]; then
                                if [ "$name" == "speedtest" ]; then
                                    install_ookla_speedtest
                                else
                                    install_package "$name" || install_fail=$((install_fail + 1))
                                fi
                            fi

                            if [ "$p_t" -eq 1 ]; then
                                for p in $paths; do grep -qFx "$p" "$sys_conf" || echo "$p" >> "$sys_conf"; done
                                if [ "$type" == "R" ]; then
                                    grep -qFx "$name" "$laz_list" 2>/dev/null || echo "$name" >> "$laz_list"
                                    create_lazarus_hook
                                fi
                            fi
                        fi
                    done < "$map_file"
                    if [ "$install_fail" -gt 0 ]; then
                        print_warning "$install_fail package(s) failed to install; other changes applied."
                    else
                        print_success "System changes applied."
                    fi
                    press_any_key
                    init_system_state
                    continue
                fi
                ;;
            0) rm -f "$map_file" 2>/dev/null; return ;;
            \?|h|H|❓) show_package_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# --- Manage SSH ---

show_ssh_help() {
    clear
    print_centered_header "SSH Key Management - Help"
    
    cat << 'HELPEOF'
SSH Key Management – Quick Help

What is an SSH Key?
───────────────────
An SSH key is a "digital passport" that allows you to log into your router
securely without typing your password every time. It consists of a 
Public Key (which stays on the router) and a Private Key (which stays on 
your computer). 

Main Benefits:
• Security: Keys are virtually impossible to brute-force compared to passwords.
• Convenience: Log in instantly from your terminal or script.
• Persistence: This script can ensure your keys survive firmware updates.

How to find or generate your Public Key:
────────────────────────────────────────
Your Public Key usually ends in .pub. DO NOT paste your Private Key.

• macOS / Linux:
  1. Open Terminal.
  2. Check for existing keys: cat ~/.ssh/id_rsa.pub (or id_ed25519.pub)
  3. To generate new: ssh-keygen -t ed25519
  4. Copy the output of: cat ~/.ssh/id_ed25519.pub

• Windows (PowerShell/CMD):
  1. Open PowerShell.
  2. Check for existing keys: cat $HOME\.ssh\id_rsa.pub
  3. To generate new: ssh-keygen -t ed25519
  4. Copy the text starting with "ssh-ed25519..."

• Windows (PuTTY):
  1. Open 'PuTTYgen'.
  2. Click 'Load' (for existing) or 'Generate' (for new).
  3. Copy the text from the box labeled: 
     "Public key for pasting into OpenSSH authorized_keys file"

Usage in this Menu:
───────────────────
1. Add Key: Paste the entire line (starts with ssh-rsa, ssh-ed25519, etc.).
2. Manage: View existing keys. Use [✓] to mark keys for deletion.
3. Persistence: Adds /etc/dropbear/authorized_keys to the
   sysupgrade list so you don't lose access after a firmware update.

Security Warning:
─────────────────
Never share your PRIVATE key with anyone. Only the PUBLIC key belongs
on the router.
HELPEOF
    
    press_any_key
}

manage_ssh_keys() {
    local auth_file="/etc/dropbear/authorized_keys"
    local up_conf="/etc/sysupgrade.conf"
    local ssh_data="/tmp/ssh_mgr.data"

    while true; do
        # 1. Status Calculations
        local key_count=0
        [ -f "$auth_file" ] && key_count=$(grep -c "^ssh-" "$auth_file")
        
        local persistence="${YELLOW}DISABLED${RESET}"
        grep -qFx "$auth_file" "$up_conf" 2>/dev/null && persistence="${GREEN}ENABLED${RESET}"

        clear
        print_centered_header "SSH Key Management"
        
        printf " %b\n" "${CYAN}STATUS${RESET}"
        printf "   Authorized Keys:  %d\n" "$key_count"
        printf "   Persistence:      %b\n\n" "$persistence"

        local ssh_persist_label="Enable Persistence"
        [ "$persistence" = "${GREEN}ENABLED${RESET}" ] && ssh_persist_label="Disable Persistence"
        printf "%s  Add a New SSH Key\n" "$N1"
        printf "%s  Manage / Delete Keys\n" "$N2"
        printf "%s  %s\n" "$N3" "$ssh_persist_label"
        printf "%s  Back\n" "$N0"
        printf "%s Help\n" "$NQ"
        
        printf "\nChoose [1-3/0/?]: "
        read -r ssh_choice
        
        case "$ssh_choice" in
            1) # ADD KEY
                printf "\n${CYAN}Paste your public key (starts with ssh-rsa, etc.):${RESET}\n"
                read -r new_key
                printf "\n"
                if echo "$new_key" | grep -qE "^ssh-(rsa|ed25519|dss|ecdsa) "; then
                    # Extract base64 part for duplicate check
                    local key_base64=$(echo "$new_key" | awk '{print $2}')
                    if [ -f "$auth_file" ] && grep -q "$key_base64" "$auth_file"; then
                        print_warning "Key already exists in authorized_keys."
                    else
                        mkdir -p /etc/dropbear
                        echo "$new_key" >> "$auth_file"
                        chmod 0700 /etc/dropbear && chmod 0600 "$auth_file"
                        print_success "Key added successfully."
                    fi
                else
                    print_error "Invalid key format."
                fi
                press_any_key ;;

            2) # MANAGE / DELETE UI
                if [ ! -s "$auth_file" ]; then
                    print_error "No keys found to manage."
                    sleep 1; continue
                fi

                while true; do
                    # Generate fresh temp data: Index | Type | Identity | Selected(0/1)
                    # Use awk to handle keys with no comments by truncating the key string itself
                    awk '{
                        type=$1; 
                        # If comment (field 3) exists, use it. Otherwise, truncate field 2.
                        if ($3 != "") { 
                            id=$3; for(i=4;i<=NF;i++) id=id" "$i 
                        } else { 
                            id="(No comment) " substr($2,1,15)"..." 
                        }
                        print NR "|" type "|" id "|0"
                    }' "$auth_file" > "$ssh_data"

                    while true; do
                        clear
                        print_centered_header "SSH Authorized Keys Manager"
                        printf "\n"
                        printf " %-5s %-4s %-12s %-40s\n" "Sel" "Idx" "Key Type" "Identity / Comment"
                        printf " ────────────────────────────────────────────────────────────────\n"
                        while IFS='|' read -r idx type id sel; do
                            s_box=" [ ] "; [ "$sel" -eq 1 ] && s_box=" [✓] "
                            printf " %s %-4s %-12s %-40s\n" "$s_box" "$idx." "$type" "$id"
                        done < "$ssh_data"
                        printf " ────────────────────────────────────────────────────────────────\n"
                        printf " [A] All   [N] None   [#] Toggle   [D] Delete   [0] Cancel\n"
                        key_count=$(wc -l < "$ssh_data" 2>/dev/null | tr -dc '0-9')
                        printf "\n Choose [%s/A/N/D/0]: " "$(picker_range "$key_count")"
                        read -r cmd

                        case "$cmd" in
                            a|A) sed -i 's/|0$/|1/' "$ssh_data" ;;
                            n|N) sed -i 's/|1$/|0/' "$ssh_data" ;;
                            [0-9]*)
                                [ "$cmd" -eq 0 ] && break 2
                                awk -F'|' -v t="$cmd" 'BEGIN{OFS="|"} {if($1==t) $4=($4==1?0:1); print}' "$ssh_data" > "$ssh_data.tmp" && mv "$ssh_data.tmp" "$ssh_data" ;;
                            d|D)
                                local to_del=$(awk -F'|' '$4==1' "$ssh_data")
                                if [ -z "$to_del" ]; then
                                    print_warning "No keys selected."; sleep 2; continue
                                fi
                                
                                clear
                                print_centered_header "Confirm Deletion"
                                echo "$to_del" | awk -F'|' '{print "  - " $2 " (" $3 ")"}'
                                printf "\nDelete selected keys? [y/N]: "; read -r confirm
                                if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                                    # Create a keep-list of line numbers
                                    local lines_to_keep=$(awk -F'|' '$4==0 {print $1}' "$ssh_data")
                                    if [ -z "$lines_to_keep" ]; then
                                        > "$auth_file" # Wipe if all deleted
                                    else
                                        # Use awk to reconstruct the file from original line numbers
                                        local tmp_auth="/tmp/auth.keep"
                                        for l in $lines_to_keep; do
                                            sed -n "${l}p" "$auth_file" >> "$tmp_auth"
                                        done
                                        mv "$tmp_auth" "$auth_file"
                                    fi
                                    chmod 0600 "$auth_file"
                                    print_success "Keys updated."
                                    break 2
                                fi ;;
                            0) break 2 ;;
                        esac
                    done
                done
                rm -f "$ssh_data" ;;

            3) # TOGGLE PERSISTENCE
                printf "\n"
                if grep -qFx "$auth_file" "$up_conf" 2>/dev/null; then
                    sed -i "\|$auth_file|d" "$up_conf"
                    print_warning "Persistence disabled. Keys will be lost on firmware upgrade."
                else
                    echo "$auth_file" >> "$up_conf"
                    print_success "Persistence enabled. Keys will survive firmware upgrades."
                fi
                press_any_key ;;
                
            0) return ;;
            \?|h|H|❓) show_ssh_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

show_system_tweaks_help() {
    clear
    print_centered_header "System Tweaks - Help"
    cat << 'HELPEOF'
System Tweaks – Quick Help

Overview
────────
This menu groups configuration and management tools for common GL.iNet
router customizations. Each option targets a specific subsystem.

Options
───────
1. Device Fan Settings
   Adjust fan speed thresholds, min/max RPM, and thermal warning temps.
   Only available on hardware with controllable fans (e.g. Flint 3).

2. Manage Zram Swap
   Install and configure compressed RAM swap. Essential on low-RAM
   devices running AdGuardHome + VPN simultaneously.

3. Guest Network Bandwidth Limiter
   Set global speed limits for the guest subnet and control whether
   guest clients can reach the router's LAN IP.

4. Web-UI Terminal Interface
   Embed a draggable terminal (powered by ttyd) into the GL.iNet
   Admin Panel as a ">_" icon in the navigation bar.

5. Package and Persistence Manager
   Install useful CLI tools (htop, tcpdump, etc.) and configure them
   to survive firmware upgrades via the sysupgrade keep-list.

6. SSH Key Management
   Add, view, and delete authorized SSH keys. Enable or disable persistence so
   your keys survive firmware upgrades.

7. Toolkit Management
   Install this script to /usr/sbin/glinet_utils so it can be run
   from anywhere. Manage sysupgrade persistence and updates.
HELPEOF
    press_any_key
}

# -----------------------------
# Toolkit Management
# -----------------------------

toolkit_is_installed() {
    [ -f "$INSTALL_PATH" ]
}

toolkit_persistence_enabled() {
    grep -qFx "$INSTALL_PATH" /etc/sysupgrade.conf 2>/dev/null
}

set_toolkit_persistence() {
    local enable="$1"
    local keep_conf="/etc/sysupgrade.conf"
    if [ "$enable" -eq 1 ]; then
        if ! grep -qFx "$INSTALL_PATH" "$keep_conf" 2>/dev/null; then
            printf "%s\n" "$INSTALL_PATH" >> "$keep_conf"
            print_success "Added to $keep_conf — will survive firmware upgrades."
        else
            print_info "Already persisted in $keep_conf — no change."
        fi
    else
        if grep -qFx "$INSTALL_PATH" "$keep_conf" 2>/dev/null; then
            sed -i "\|^${INSTALL_PATH}$|d" "$keep_conf" 2>/dev/null
            print_success "Removed from $keep_conf — will not survive firmware upgrades."
        else
            print_info "Not in $keep_conf — no change."
        fi
    fi
}

show_toolkit_help() {
    clear
    print_centered_header "Toolkit Management - Help"
    cat << 'HELPEOF'
Toolkit Management – Quick Help

Install to /usr/sbin/glinet_utils
──────────────────────────────────
Copies this script to /usr/sbin/glinet_utils (no .sh extension) so
you can run it from any directory by typing just: glinet_utils

Once installed, the self-updater always targets the installed copy,
keeping a single up-to-date version on your router.

Sysupgrade Persistence
──────────────────────
By default, files added to /usr/sbin via the overlay filesystem are
lost when you perform a firmware upgrade (sysupgrade). Enabling
persistence adds /usr/sbin/glinet_utils to /etc/sysupgrade.conf so
the file is preserved across upgrades.

After a firmware upgrade, the preserved copy will check GitHub for
updates on its first run and self-update if a newer version exists.

View Change Log & Update
────────────────────────
Browse the full change log, newest first. When you are behind, a
line marks your installed version (everything above it is new to
you) and [U] updates in place and restarts. The heading reads
"View Change Log" when you are already up to date.

Uninstall
─────────
Removes /usr/sbin/glinet_utils and its sysupgrade.conf entry.
The script you are currently running is not affected.
HELPEOF
    press_any_key
}

check_install_prompt() {
    [ "$SCRIPT_PATH" = "$INSTALL_PATH" ] && return
    [ "$INSTALL_PROMPTED" -eq 1 ] && return

    print_info "Installing to $INSTALL_PATH lets you run this program from anywhere as a system command."
    printf "   Install as a system command? [Y/n]: "
    read -r _ip_ans
    printf "\n"
    case "$_ip_ans" in
        n|N)
            sed -i 's/^INSTALL_PROMPTED=0$/INSTALL_PROMPTED=1/' "$SCRIPT_PATH"
            print_info "Skipping. You can install later via System Tweaks > Toolkit Management."
            STARTUP_NOTICE=1
            ;;
        *)
            do_install_to_sbin "$@"
            ;;
    esac
}

do_install_to_sbin() {
    print_action "Installing to $INSTALL_PATH..."
    if ! cp "$SCRIPT_PATH" "$INSTALL_PATH" || ! chmod +x "$INSTALL_PATH"; then
        print_error "Install failed. Check write permissions on /usr/sbin."
        press_any_key
        return 1
    fi
    print_success "Installed to $INSTALL_PATH"

    if ! toolkit_persistence_enabled; then
        printf "\n   Persist across firmware upgrades? [Y/n]: "
        read -r _persist_ans
        printf "\n"
        case "$_persist_ans" in
            n|N) print_warning "Not persisted — will be lost on next sysupgrade." ;;
            *)   set_toolkit_persistence 1 ;;
        esac
    fi

    printf "\n"
    print_action "Switching to installed copy..."
    sleep 2
    exec "$INSTALL_PATH" "$@"
}

manage_display_settings() {
    # Per-mode preview screen. Uses hardcoded escapes so each sample renders
    # truthfully regardless of the currently active OUTPUT_MODE.
    _display_settings_screen() {
        local page="$1" detected="$2"
        local _R="\033[0m" _G="\033[32m" _Y="\033[33m" _B="\033[38;5;153m" _C="\033[36m" _RD="\033[31m"
        case "$page" in
            1)
                printf " %bPage 1 of 3 — Full mode%b (emoji symbols + color)\n\n" "${BOLD}${CYAN}" "$_R"
                printf "   %bMessages%b\n" "$_C" "$_R"
                printf "     %b✅ Operation completed successfully%b\n" "$_G" "$_R"
                printf "     %b❌ Operation failed%b\n" "$_RD" "$_R"
                printf "     %b⚠️  Something needs attention%b\n" "$_Y" "$_R"
                printf "     %bℹ️  Informational message%b\n" "$_B" "$_R"
                printf "     %b⚙️  Action in progress%b\n\n" "$_C" "$_R"
                printf "   %bStatus%b\n" "$_C" "$_R"
                printf "     %b✅ On / enabled / running%b      %b❌ Off / disabled / stopped%b\n\n" "$_G" "$_R" "$_RD" "$_R"
                printf "   %bA menu looks like%b\n" "$_C" "$_R"
                printf "     1️⃣  Show Hardware Information\n"
                printf "     2️⃣  AdGuardHome Control Center\n"
                printf "     3️⃣  System Tweaks\n"
                printf "     0️⃣  Exit\n"
                printf "     ❓ Help\n"
                ;;
            2)
                printf " %bPage 2 of 3 — Compatible mode%b (Unicode symbols + color, PuTTY-safe)\n\n" "${BOLD}${CYAN}" "$_R"
                printf "   %bMessages%b\n" "$_C" "$_R"
                printf "     %b✓  Operation completed successfully%b\n" "$_G" "$_R"
                printf "     %b✗  Operation failed%b\n" "$_RD" "$_R"
                printf "     %b⚠  Something needs attention%b\n" "$_Y" "$_R"
                printf "     %bℹ  Informational message%b\n" "$_B" "$_R"
                printf "     %b⚙  Action in progress%b\n\n" "$_C" "$_R"
                printf "   %bStatus%b\n" "$_C" "$_R"
                printf "     %b✓ On / enabled / running%b      %b✗ Off / disabled / stopped%b\n\n" "$_G" "$_R" "$_RD" "$_R"
                printf "   %bA menu looks like%b\n" "$_C" "$_R"
                printf "     [1]  Show Hardware Information\n"
                printf "     [2]  AdGuardHome Control Center\n"
                printf "     [3]  System Tweaks\n"
                printf "     [0]  Exit\n"
                printf "     [?]  Help\n"
                ;;
            3)
                printf " %bPage 3 of 3 — Auto%b (detect terminal on each launch)\n\n" "${BOLD}${CYAN}" "$_R"
                printf "   Re-detects your terminal every time the toolkit\n"
                printf "   starts and selects Full or Compatible automatically.\n\n"
                printf "   Right now it would use:\n"
                printf "     %b%s%b\n" "$_G" "$detected" "$_R"
                ;;
        esac
    }

    local _page=1 total=3
    while true; do
        clear
        print_centered_header "Display Settings"
        printf " ──────────────────────────────────────────────────────────────────────────────\n"

        local pref_display
        case "$OUTPUT_PREF" in
            full)   pref_display="${GREEN}Full${RESET}"                  ;;
            compat) pref_display="${YELLOW}Compatible${RESET}"           ;;
            *)      pref_display="${CYAN}Auto (detect each run)${RESET}" ;;
        esac
        printf "   Saved default: %b\n\n" "$pref_display"
        # Auto page needs to show what auto would currently resolve to.
        local detected_desc
        case "$OUTPUT_MODE" in
            full)
                case "$_TERM_PROFILE" in
                    ttyd) detected_desc="ttyd (browser) → Full mode" ;;
                    wt)   detected_desc="Windows Terminal → Full mode" ;;
                    *)    detected_desc="macOS/Linux Terminal → Full mode" ;;
                esac
                ;;
            *) detected_desc="Compatible terminal → Compatible mode" ;;
        esac

        _display_settings_screen "$_page" "$detected_desc"

        # Footer / navigation (mirrors the Hardware Info pager)
        printf "\n ──────────────────────────────────────────────────────────────────────────────\n"
        printf " [P] Prev   "
        local i=1
        while [ "$i" -le "$total" ]; do
            if [ "$i" -eq "$_page" ]; then
                printf "%b[%d]%b " "${BOLD}" "$i" "${RESET}"
            else
                printf "%b[%d]%b " "${GREY}" "$i" "${RESET}"
            fi
            i=$((i + 1))
        done
        printf "  [N] Next   [C] Confirm   [0] Back  "

        local nav_choice
        nav_choice=$(read_single_char)
        printf "\n"

        case "$nav_choice" in
            p|P|b|B) [ "$_page" -gt 1 ] && _page=$((_page - 1)) ;;
            n|N)     [ "$_page" -lt "$total" ] && _page=$((_page + 1)) ;;
            1|2|3)   _page="$nav_choice" ;;
            c|C)
                local new_pref
                case "$_page" in
                    1) new_pref="full"   ;;
                    2) new_pref="compat" ;;
                    3) new_pref="auto"   ;;
                esac
                local pref_label
                case "$new_pref" in
                    full)   pref_label="Full"       ;;
                    compat) pref_label="Compatible" ;;
                    auto)   pref_label="Auto"        ;;
                    *)      pref_label="$new_pref"   ;;
                esac
                printf "\n"
                print_info "Set display mode to $pref_label."
                printf "   Save as default? [Y/n]: "
                read -r ds_save
                printf "\n"
                case "$ds_save" in
                    n|N)
                        OUTPUT_PREF="$new_pref"
                        detect_output_mode
                        print_info "Applied for this session only (not saved)."
                        ;;
                    *)
                        sed -i "s/^OUTPUT_PREF=\"[^\"]*\"/OUTPUT_PREF=\"$new_pref\"/" "$SCRIPT_PATH"
                        OUTPUT_PREF="$new_pref"
                        detect_output_mode
                        print_success "Saved as default: $pref_label"
                        ;;
                esac
                press_any_key
                ;;
            0) return ;;
        esac
    done
}

manage_toolkit() {
    while true; do
        clear
        print_centered_header "Toolkit Management"

        local installed_status persistence_status running_from install_label persist_label
        if toolkit_is_installed; then
            installed_status="${GREEN}INSTALLED${RESET}"
            install_label="Uninstall"
        else
            installed_status="${RED}NOT INSTALLED${RESET}"
            install_label="Install"
        fi
        if toolkit_persistence_enabled; then
            persistence_status="${GREEN}ENABLED${RESET}"
            persist_label="Disable Persistence"
        else
            persistence_status="${YELLOW}DISABLED${RESET}"
            persist_label="Enable Persistence"
        fi
        if [ "$SCRIPT_PATH" = "$INSTALL_PATH" ]; then
            running_from="${GREEN}$INSTALL_PATH${RESET}"
        else
            running_from="${YELLOW}$SCRIPT_PATH${RESET} (local)"
        fi
        local mode_display
        case "$OUTPUT_MODE" in
            full)   mode_display="${GREEN}Full${RESET}"        ;;
            compat) mode_display="${YELLOW}Compatible${RESET}" ;;
            *)      mode_display="$OUTPUT_MODE"                ;;
        esac
        if [ "$OUTPUT_PREF" = "auto" ]; then
            case "$OUTPUT_MODE" in
                full)
                    case "$_TERM_PROFILE" in
                        ttyd)  mode_display="$mode_display  [auto: ttyd]" ;;
                        wt)    mode_display="$mode_display  [auto: Windows Terminal]" ;;
                        *)     mode_display="$mode_display  [auto: macOS/Linux]" ;;
                    esac
                    ;;
                *) mode_display="$mode_display  [auto]" ;;
            esac
        fi

        local update_display update_label local_ver
        local_ver="$(grep -m1 '^# Version:' "$SCRIPT_PATH" | awk '{print $3}' | tr -d '\r')"
        [ -z "$local_ver" ] && local_ver="unknown"
        case "${UPDATE_STATUS:-unknown}" in
            available) update_display="${YELLOW}${REMOTE_VERSION} available${RESET}"; update_label="View Change Log & Update" ;;
            current)   update_display="${GREEN}Up to date${RESET}";                   update_label="View Change Log" ;;
            *)         update_display="${GREY}Unknown (offline)${RESET}";              update_label="View Change Log" ;;
        esac

        printf " %b\n" "${CYAN}STATUS${RESET}"
        printf "   Display mode: %b\n"   "$mode_display"
        printf "   Terminal:     %b\n"   "${GREEN}${TERM:-unknown}${RESET}"
        printf "   Installation: %b\n"   "$installed_status"
        printf "   Persistence:  %b\n"   "$persistence_status"
        printf "   Running from: %b\n"   "$running_from"
        printf "   Version:      %b\n"   "${GREEN}${local_ver}${RESET}"
        printf "   Update:       %b\n\n" "$update_display"

        printf "%s  %s\n" "$N1" "$install_label"
        printf "%s  %s\n" "$N2" "$persist_label"
        printf "%s  Display Settings\n"          "$N3"
        printf "%s  %s\n"                        "$N4" "$update_label"
        printf "%s  Back\n"                      "$N0"
        printf "%s Help\n"                       "$NQ"
        printf "\nChoose [1-4/0/?]: "
        read -r tk_choice
        printf "\n"

        case "$tk_choice" in
            1)
                if toolkit_is_installed; then
                    # Uninstall path
                    print_warning "This will remove $INSTALL_PATH from the system."
                    if [ "$SCRIPT_PATH" = "$INSTALL_PATH" ]; then
                        print_warning "You are currently running the installed copy."
                        printf "   After removal, run the script directly from its local path.\n"
                    fi
                    printf "   Remove the toolkit? [y/N]: "; read -r c; printf "\n"
                    case "$c" in
                        y|Y)
                            rm -f "$INSTALL_PATH"
                            set_toolkit_persistence 0
                            print_success "Uninstalled."
                            press_any_key
                            ;;
                        *) print_info "No change."; press_any_key ;;
                    esac
                else
                    # Install path
                if [ "$SCRIPT_PATH" = "$INSTALL_PATH" ]; then
                    print_info "Already running from the installed location."
                    press_any_key
                else
                        do_install_to_sbin "$@"
                    fi
                fi
                ;;
            2)
                if ! toolkit_is_installed; then
                    print_error "Not installed — install first (option 1)."
                    sleep 2; continue
                fi
                if toolkit_persistence_enabled; then
                    printf "   Disable sysupgrade persistence? [y/N]: "; read -r c; printf "\n"
                    case "$c" in y|Y) set_toolkit_persistence 0 ;; *) print_info "No change." ;; esac
                else
                    printf "   Enable sysupgrade persistence? [y/N]: "; read -r c; printf "\n"
                    case "$c" in y|Y) set_toolkit_persistence 1 ;; *) print_info "No change." ;; esac
                fi
                press_any_key
                ;;
            3) manage_display_settings ;;
            4)
                CL_EXIT_LABEL="Back"
                if ! show_changelog "$@"; then
                    print_warning "Unable to fetch the change log (network or GitHub issue)."
                    press_any_key
                fi
                CL_EXIT_LABEL=""
                ;;
            \?|h|H|❓) show_toolkit_help ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

system_tweaks() {
    while true; do
        clear
        print_centered_header "System Tweaks"
        printf "%s  Device Fan Settings\n" "$N1"
        printf "%s  Manage Zram Swap\n" "$N2"
        printf "%s  Guest Network Bandwidth Limiter\n" "$N3"
        printf "%s  Web-UI Terminal Interface\n" "$N4"
        printf "%s  Package and Persistence Manager\n" "$N5"
        printf "%s  SSH Key Management\n" "$N6"
        printf "%s  Toolkit Management\n" "$N7"
        printf "%s  Main menu\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-7/0/?]: "
        read -r st_choice
        printf "\n"
        case $st_choice in
            1) manage_fan_settings ;;
            2) manage_zram ;;
            3) manage_guest_limiter ;;
            4) manage_web_terminal ;;
            5) manage_packages ;;
            6) manage_ssh_keys ;;
            7) manage_toolkit ;;
            \?|h|H|❓) show_system_tweaks_help ;;
            0) return ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# System Benchmarks
# -----------------------------

show_benchmarks_help() {
    clear
    print_centered_header "System Benchmarks - Help"
    
    cat << 'HELPEOF'
System Benchmarks – Quick Help

Overview
────────
This menu provides a suite of tools to validate hardware performance, thermal 
stability, and network throughput. These tests help identify if your router 
is throttling due to heat or if your storage/RAM is underperforming.

Benchmark Categories:
─────────────────────
• CPU & Thermal: Options 1 and 2 test the processor. The Stress Test pushes
  all cores to 100% to test heat soak, while the VPN & Crypto Benchmark ranks
  this device against saved routers for WireGuard, OpenVPN and RSA throughput.
• Storage & Memory: Options 3 and 4 measure I/O speeds. Use these to test 
  the performance of the internal NAND vs. attached USB 3.0 drives or to 
  check if RAM bandwidth is saturated.
• Connectivity: Options 5 and 6 measure latency and external WAN speeds. 
  Essential for troubleshooting "slow internet" vs. "slow DNS."
• Local Servers: Options 7, 8, and 9 turn the router into a speedtest target. 
  These are used to test Wi-Fi/LAN limits without ISP interference.

Technical Details:
──────────────────
• Stress Testing: The script attempts to use 'stress' primarily. If missing, 
  it installs 'stress-ng' and creates a symlink to maintain compatibility.
• Baselines: The VPN & Crypto Benchmark is a leaderboard - its "vs yours"
  column compares saved devices to the one you are on. Disk and Memory tests
  use a fixed Beryl 7 (0.0%) reference point.
• Timing: Disk and Memory tests use /proc/uptime millisecond offsets for 
  precise Speed (MB/s) calculations rather than relying on 'dd' output.

Note on Local Servers:
──────────────────────
iPerf3 is the industry standard for CLI testing. LibreSpeed and OpenSpeedTest 
provide a browser-based UI for testing from phones and tablets without apps.
HELPEOF
    
    press_any_key
}

show_librespeed_help() {
    clear
    print_centered_header "LibreSpeed Speed Test - Help"
    
    cat << 'HELPEOF'
LibreSpeed Speed Test Server – Quick Help

What is LibreSpeed?
───────────────────
LibreSpeed is a lightweight, open-source speed test server written in Go. Unlike 
traditional speed tests that rely on external servers, this runs locally on your 
router. This allows you to test the actual throughput of your LAN and Wi-Fi 
without being limited by your ISP's internet speed.

Main features on GL.iNet routers:
• Zero Dependencies: Standalone Go binary; does not require Nginx or PHP.
• Lightweight: Extremely low CPU and RAM footprint, ideal for travel routers.
• Privacy Focused: No telemetry, no ads, and no data collection.
• Local Benchmarking: Perfect for testing Wi-Fi 6/7 performance and signal dead zones.

LibreSpeed vs. OpenSpeedTest:
─────────────────────────────
• LibreSpeed: Best for background monitoring and 1Gbps wireless audits. 
  It is much lighter on system resources (RAM/CPU).
• OpenSpeedTest: Better for high-stress 2.5G/10G throughput testing on 
  powerful hardware (like the Flint 2/3) due to its multi-threaded nature.
• Better Together: Both can run simultaneously on different ports (e.g., 8989 
  and 8888) to allow A/B testing of your wireless environment.

When should you use it?
Yes → To find Wi-Fi dead zones or verify the max speed of your local network.
Yes → To check if your VPN or SQM settings are bottlenecking your local speeds.
No  → If you only care about your ISP's "Internet" speed (use Ookla for that).

Important notes:
• Listen Port: Defaults to :8989. Access via http://<router-ip>:8989
• Persistence: Enabling persistence ensures the binary and settings survive 
  firmware updates, preventing manual re-installation.
• Procd Jail: Runs in a secure sandbox for improved router security.
HELPEOF
    
    press_any_key
}

manage_librespeed() {
    while true; do
        clear
        print_centered_header "LibreSpeed Speed Test Management"
        
        LAN_IP=$(get_lan_ip)
        LISTEN_PORT=":8989"
        UP_CONF="/etc/sysupgrade.conf"
        
        # Determine installation status once for the whole loop
		hash -r 
        if command -v librespeed-go >/dev/null 2>&1; then
            IS_INSTALLED=1
        else
            IS_INSTALLED=0
        fi

        printf " %b\n" "${CYAN}STATUS${RESET}"
        if [ "$IS_INSTALLED" -eq 1 ]; then
            if [ "$(uci -q get librespeed-go.config.enabled)" = "1" ]; then
                printf "   Service: %bENABLED%b\n" "${GREEN}" "${RESET}"
                if netstat -ltn 2>/dev/null | grep -q "${LISTEN_PORT#:}"; then
                    printf "   Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                    printf "   URL: %bhttp://$LAN_IP${LISTEN_PORT}%b\n" "${CYAN}" "${RESET}"
                else
                    printf "   Status: %bSTARTING/ERROR%b\n" "${YELLOW}" "${RESET}"
                fi
            else
                printf "   Service: %bDISABLED%b\n" "${YELLOW}" "${RESET}"
            fi
            
            # Check Persistence Status
            persist_ok="1"
            for entry in "/usr/bin/librespeed-go" "/etc/init.d/librespeed-go" "/etc/config/librespeed-go"; do
                if ! grep -qFx "$entry" "$UP_CONF" 2>/dev/null; then
                    persist_ok="0"
                    break
                fi
            done
            
            if [ "$persist_ok" -eq "1" ]; then
                printf "   Persistence: %bENABLED%b\n" "${GREEN}" "${RESET}"
            else
                printf "   Persistence: %bDISABLED%b\n" "${RED}" "${RESET}"
            fi
        else
            printf "   Service: %bNOT INSTALLED%b\n" "${RED}" "${RESET}"
        fi
        
        local ls_persist_label="Enable Persistence"
        [ "$IS_INSTALLED" -eq 1 ] && [ "$persist_ok" -eq 1 ] && ls_persist_label="Disable Persistence"
        printf "\n%s  Install and Enable\n" "$N1"
        printf "%s  Disable Service\n" "$N2"
        printf "%s  %s\n" "$N3" "$ls_persist_label"
        printf "%s  Uninstall Package\n" "$N4"
        printf "%s  Back\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-4/0/?]: "
        read -r ls_choice
        printf "\n"
        
        case $ls_choice in
            1)
                if [ "$IS_INSTALLED" -eq 0 ]; then
                    install_package librespeed-go "LibreSpeed" || { press_any_key; continue; }
                    grep -q "librespeed" /etc/passwd || echo "librespeed:x:500:500:librespeed:/var/run/librespeed-go:/bin/false" >> /etc/passwd
                    IS_INSTALLED=1
                fi

                if [ ! -f "/etc/config/librespeed-go" ]; then
                    touch /etc/config/librespeed-go
                fi
                
                if ! uci -q get librespeed-go.config >/dev/null; then
                    uci set librespeed-go.config=librespeed-go
                fi

                uci set librespeed-go.config.listen_addr="$LISTEN_PORT"
                uci set librespeed-go.config.enabled='1'
                uci commit librespeed-go
                
                /etc/init.d/librespeed-go restart >/dev/null 2>&1
                print_success "LibreSpeed enabled at http://$LAN_IP${LISTEN_PORT}"
                press_any_key
                ;;
            2)
                if [ "$IS_INSTALLED" -eq 1 ]; then
                    uci set librespeed-go.config.enabled='0'
                    uci commit librespeed-go
                    /etc/init.d/librespeed-go stop >/dev/null 2>&1
                    print_success "LibreSpeed disabled"
                else
                    print_error "Nothing to disable: LibreSpeed is not installed."
                fi
                press_any_key
                ;;
            3)
                if [ "$IS_INSTALLED" -eq 1 ]; then
                    if [ "$persist_ok" -eq "0" ]; then
                        for entry in "/usr/bin/librespeed-go" "/etc/init.d/librespeed-go" "/etc/config/librespeed-go"; do
                            grep -qFx "$entry" "$UP_CONF" || echo "$entry" >> "$UP_CONF"
                        done
                        print_success "Persistence enabled in $UP_CONF"
                    else
                        sed -i "\|/usr/bin/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/init.d/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/config/librespeed-go|d" "$UP_CONF"
                        print_success "Persistence disabled"
                    fi
                else
                    print_error "Nothing to persist: LibreSpeed is not installed."
                fi
                press_any_key
                ;;
            4)
                if [ "$IS_INSTALLED" -eq 1 ]; then
                    printf "%b" "${YELLOW}Remove LibreSpeed package? [y/N]: ${RESET}"; read -r confirm
                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        /etc/init.d/librespeed-go stop >/dev/null 2>&1
                        opkg remove --autoremove librespeed-go >/dev/null 2>&1
                        # Always clean up persistence entries on uninstall
                        sed -i "\|/usr/bin/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/init.d/librespeed-go|d" "$UP_CONF"
                        sed -i "\|/etc/config/librespeed-go|d" "$UP_CONF"
                        print_success "LibreSpeed removed"
                    fi
                else
                    print_error "Nothing to remove: LibreSpeed is not installed."
                fi
                press_any_key
                ;;
            0) return ;;
            \?|h|H|❓) show_librespeed_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

install_ookla_speedtest() {
    if ! command -v speedtest >/dev/null 2>&1 || ! speedtest --version 2>&1 | grep -qi "ookla"; then
        arch=$(uname -m)
        case "$arch" in
            aarch64) suffix="aarch64" ;;
            armv7*)  suffix="armhf"   ;;
            armv8*)  suffix="aarch64" ;;
            mips*)   suffix="mips"    ;;
            x86_64)  suffix="x86_64"  ;;
            *) print_error "Unsupported Arch: $arch"; press_any_key; return 1 ;;
        esac

        _ookla_fetch() {
            local ver url
            ver=$(wget -qO- https://www.speedtest.net/apps/cli | grep -oE "ookla-speedtest-[0-9.]+-linux-$suffix.tgz" | head -n1)
            [ -z "$ver" ] && ver="ookla-speedtest-1.2.0-linux-$suffix.tgz"
            url="https://install.speedtest.net/app/cli/$ver"
            wget -qO- "$url" | tar xz -C /usr/bin speedtest
            chmod +x /usr/bin/speedtest
        }

        spin_run "Installing Ookla Speedtest" _ookla_fetch
        rm -f "$SPIN_LOG" 2>/dev/null

        if command -v speedtest >/dev/null 2>&1; then
            print_success "Installed: $(speedtest --version | head -n1)"
        else
            print_error "Failed to install Ookla Speedtest."
            check_connectivity
            press_any_key
            return 1
        fi
    fi
}

# --- VPN & Crypto Benchmark helpers ---
# Throughput data is OpenSSL's "1000s of bytes per second" (KB/s); rsa in ops/s.

# Measure one EVP cipher at one block size into BENCH_RESULT (numeric, no
# trailing 'k'). Sets a global rather than echoing because spin_run animates on
# stdout - capturing it in $(...) would swallow the spinner. Name/case-agnostic
# so it works across OpenSSL 1.1.x and 3.x; empty on failure -> caller uses 0.
bench_measure() {   # cipher size -> BENCH_RESULT
    spin_run "Measuring $1 @ ${2}B" openssl speed -evp "$1" -bytes "$2"
    BENCH_RESULT=$(awk '/[0-9]k$/{v=$NF} END{sub(/k$/,"",v); print v}' "$SPIN_LOG")
}

# Render one cipher leaderboard table: rows sorted by throughput (1420 B)
# descending, this device highlighted. Args: title small_col tput_col ceil_col
# datafile my_id. Columns in datafile are 1=id 2=label 3=cpu 4..9=cipher sizes.
bench_render_cipher() {
    local title="$1" sc="$2" tc="$3" cc="$4" df="$5" id="$6" base
    base=$(awk -F'|' -v id="$id" -v c="$tc" '$1==id{print $c; exit}' "$df")
    printf '\n %b%s%b\n' "$CYAN" "$title" "$RESET"
    printf '  %-10s %-7s %-10s  %-10s  %-10s %-8s  %-10s\n' "Device" "CPU" "64 B" "1420 B" "vs yours" "" "16 K"
    printf ' %s\n' "───────────────────────────────────────────────────────────────────────────"
    awk -F'|' -v c="$tc" '{print $c"\t"$0}' "$df" | sort -rn | cut -f2- | awk -F'|' \
        -v id="$id" -v sc="$sc" -v tc="$tc" -v cc="$cc" -v base="$base" \
        -v cur="${BOLD}${GREEN}" -v res="$RESET" '
        function unit(k,  v,u){ v=k*8; u="Kb/s"; if(v>=10000){v/=1000;u="Mb/s"} if(v>=10000){v/=1000;u="Gb/s"}
            if(v>=1000)return sprintf("%.0f %s",v,u); if(v>=100)return sprintf("%.1f %s",v,u);
            if(v>=10)return sprintf("%.2f %s",v,u); return sprintf("%.3f %s",v,u) }
        function bar(v,mx,  n,i,s){ if(mx<=0)return "          "; n=int(v/mx*10+0.5); if(n>10)n=10; if(n<0)n=0;
            s=""; for(i=0;i<n;i++)s=s"█"; for(i=n;i<10;i++)s=s"░"; return s }
        NR==1{mx=$tc}
        { if($1==id)d="  ---   "; else if(base>0)d=sprintf("%+6.1f%%",($tc-base)/base*100); else d="";
          mark=($1==id)?"> ":"  ";
          line=sprintf("%s%-10.10s %-7.7s %-10s  %-10s  %-10s %-8s  %-10s",mark,$2,$3,unit($sc),unit($tc),bar($tc,mx),d,unit($cc));
          if($1==id)printf "%s%s%s\n",cur,line,res; else print line }'
}

# Render the RSA connection-setup table (sorted by sign/s). Args: datafile my_id.
bench_render_rsa() {
    local df="$1" id="$2" base
    base=$(awk -F'|' -v id="$id" '$1==id{print $10; exit}' "$df")
    printf '\n %b%s%b\n' "$CYAN" "Connection setup · RSA-2048" "$RESET"
    printf '  %-10s %-7s %-10s  %-10s %-8s  %-10s\n' "Device" "CPU" "sign/s" "vs yours" "" "verify/s"
    printf ' %s\n' "───────────────────────────────────────────────────────────────"
    awk -F'|' '{print $10"\t"$0}' "$df" | sort -rn | cut -f2- | awk -F'|' -v id="$id" -v base="$base" \
        -v cur="${BOLD}${GREEN}" -v res="$RESET" '
        function bar(v,mx,  n,i,s){ if(mx<=0)return "          "; n=int(v/mx*10+0.5); if(n>10)n=10; if(n<0)n=0;
            s=""; for(i=0;i<n;i++)s=s"█"; for(i=n;i<10;i++)s=s"░"; return s }
        NR==1{mx=$10}
        { if($1==id)d="  ---   "; else if(base>0)d=sprintf("%+6.1f%%",($10-base)/base*100); else d="";
          mark=($1==id)?"> ":"  ";
          line=sprintf("%s%-10.10s %-7.7s %-10.1f  %-10s %-8s  %-10.1f",mark,$2,$3,$10,bar($10,mx),d,$11);
          if($1==id)printf "%s%s%s\n",cur,line,res; else print line }'
}

# Render the Disk I/O leaderboard, sorted by Write (the cross-device-reliable
# metric - Read may reflect a storage controller's own cache, see caller's
# footnote). Args: datafile my_id. Columns: 1=id 2=label 3=cpu 4=write 5=read.
bench_render_disk() {
    local df="$1" id="$2" base
    base=$(awk -F'|' -v id="$id" '$1==id{print $4; exit}' "$df")
    printf '\n %b%s%b\n' "$CYAN" "Disk I/O (Sequential)" "$RESET"
    printf '  %-10s %-7s %-10s  %-10s  %-10s %-8s\n' "Device" "CPU" "Write" "Read" "vs yours" ""
    printf ' %s\n' "───────────────────────────────────────────────────────────────"
    awk -F'|' '{print $4"\t"$0}' "$df" | sort -rn | cut -f2- | awk -F'|' \
        -v id="$id" -v base="$base" -v cur="${BOLD}${GREEN}" -v res="$RESET" '
        function unit(v,  u){ u="MB/s"; if(v>=10000){v/=1000;u="GB/s"}
            if(v>=1000)return sprintf("%.0f %s",v,u); if(v>=100)return sprintf("%.1f %s",v,u);
            if(v>=10)return sprintf("%.2f %s",v,u); return sprintf("%.3f %s",v,u) }
        function bar(v,mx,  n,i,s){ if(mx<=0)return "          "; n=int(v/mx*10+0.5); if(n>10)n=10; if(n<0)n=0;
            s=""; for(i=0;i<n;i++)s=s"█"; for(i=n;i<10;i++)s=s"░"; return s }
        NR==1{mx=$4}
        { if($1==id)d="  ---   "; else if(base>0)d=sprintf("%+6.1f%%",($4-base)/base*100); else d="";
          mark=($1==id)?"> ":"  ";
          line=sprintf("%s%-10.10s %-7.7s %-10s  %-10s  %-10s %-8s",mark,$2,$3,unit($4),unit($5),bar($4,mx),d);
          if($1==id)printf "%s%s%s\n",cur,line,res; else print line }'
}

# Render the Memory I/O leaderboard (single Read/Write throughput metric).
# Args: datafile my_id. Columns: 1=id 2=label 3=cpu 4=mem_mbs.
bench_render_mem() {
    local df="$1" id="$2" base
    base=$(awk -F'|' -v id="$id" '$1==id{print $4; exit}' "$df")
    printf '\n %b%s%b\n' "$CYAN" "Memory I/O (Read/Write)" "$RESET"
    printf '  %-10s %-7s %-10s  %-10s %-8s\n' "Device" "CPU" "Speed" "vs yours" ""
    printf ' %s\n' "───────────────────────────────────────────────────"
    awk -F'|' '{print $4"\t"$0}' "$df" | sort -rn | cut -f2- | awk -F'|' \
        -v id="$id" -v base="$base" -v cur="${BOLD}${GREEN}" -v res="$RESET" '
        function unit(v,  u){ u="MB/s"; if(v>=10000){v/=1000;u="GB/s"}
            if(v>=1000)return sprintf("%.0f %s",v,u); if(v>=100)return sprintf("%.1f %s",v,u);
            if(v>=10)return sprintf("%.2f %s",v,u); return sprintf("%.3f %s",v,u) }
        function bar(v,mx,  n,i,s){ if(mx<=0)return "          "; n=int(v/mx*10+0.5); if(n>10)n=10; if(n<0)n=0;
            s=""; for(i=0;i<n;i++)s=s"█"; for(i=n;i<10;i++)s=s"░"; return s }
        NR==1{mx=$4}
        { if($1==id)d="  ---   "; else if(base>0)d=sprintf("%+6.1f%%",($4-base)/base*100); else d="";
          mark=($1==id)?"> ":"  ";
          line=sprintf("%s%-10.10s %-7.7s %-10s  %-10s %-8s",mark,$2,$3,unit($4),bar($4,mx),d);
          if($1==id)printf "%s%s%s\n",cur,line,res; else print line }'
}

benchmark_system() {
    while true; do
        clear
        print_centered_header "System Benchmarks"
        printf "%s  CPU Thermal Stress Test\n" "$N1"
        printf "%s  VPN & Crypto Benchmark\n" "$N2"
        printf "%s  Disk I/O Benchmark\n" "$N3"
        printf "%s  Memory I/O Benchmark\n" "$N4"
        printf "%s  DNS Latency Benchmark\n" "$N5"
        printf "%s  Ookla Internet Speedtest\n" "$N6"
        printf "%s  LibreSpeed Speed Test Server\n" "$N7"
        printf "%s  iPerf3 Network Speed Test Server\n" "$N8"
        printf "%s  OpenSpeedTest Server\n" "$N9"
        printf "%s  Main menu\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-9/0/?]: "
        read -r bench_choice
        printf "\n"
        
        case $bench_choice in
            1)
                clear
                print_centered_header "CPU Thermal Stress Test"
                
                if ! command -v stress >/dev/null 2>&1; then
                    install_package stress
                    if ! command -v stress >/dev/null 2>&1; then
                        install_package stress-ng
                        if ! command -v stress-ng >/dev/null 2>&1; then
                            print_error "Could not install a CPU stress tool."
                            press_any_key
                            continue
                        else
                            ln -s "$(which stress-ng)" /usr/bin/stress
                        fi
                    fi
                fi

                get_temp() {
                    local raw_temp
                    raw_temp=$(get_cpu_temp)
                    if [ "$raw_temp" != "unknown" ]; then
                        local celsius=$(awk "BEGIN {printf \"%.2f\", $raw_temp}")
                        local fahrenheit=$(awk "BEGIN {printf \"%.2f\", ($raw_temp * 1.8) + 32}")
                        printf "%s°C (%s°F)" "$celsius" "$fahrenheit"
                    else
                        printf "N/A"
                    fi
                }
                
                cpu_cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null)
                [ -z "$cpu_cores" ] && cpu_cores=1
                
                printf "\nHow many seconds to run stress test? [default: 60]: "
                read -r duration
                [ -z "$duration" ] && duration=60
                
                case "$duration" in
                    ''|*[!0-9]*) duration=60 ;;
                esac

                raw_start=$(get_cpu_temp)
                start_temp_str=$(get_temp)
                start_fan_str=$(get_fan_speed)
                
                printf "\n"
                countdown_run "Stress testing $cpu_cores cores" "$duration" stress --cpu "$cpu_cores" --timeout "${duration}s"

                raw_end=$(get_cpu_temp)
                end_temp_str=$(get_temp)
                end_fan_str=$(get_fan_speed)
                usleep 3000000
                raw_post=$(get_cpu_temp)
                post_temp_str=$(get_temp)
                post_fan_str=$(get_fan_speed)
                
                printf "\n"
                print_success "Stress test completed"
                printf "\n"
                if [ "$raw_start" != "unknown" ] && [ "$raw_end" != "unknown" ]; then
                    diff_c=$(awk "BEGIN {printf \"%+.2f\", $raw_end - $raw_start}")
                    diff_f=$(awk "BEGIN {printf \"%+.1f\", ($raw_end - $raw_start) * 1.8}")
                    post_diff_c=$(awk "BEGIN {printf \"%+.2f\", $raw_post - $raw_start}")
                    post_diff_f=$(awk "BEGIN {printf \"%+.1f\", ($raw_post - $raw_start) * 1.8}")
                    
                    # Fan % Changes
                    if [ "$start_fan_str" = "N/A" ] || [ "$start_fan_str" -eq 0 ] 2>/dev/null; then
                        fan_p="+0.0"
                        fan_post_p="+0.0"
                    else
                        fan_p=$(awk "BEGIN {printf \"%+.1f\", (($end_fan_str - $start_fan_str) / $start_fan_str) * 100}")
                        fan_post_p=$(awk "BEGIN {printf \"%+.1f\", (($post_fan_str - $start_fan_str) / $start_fan_str) * 100}")
                    fi

                    # --- TABLE RENDER ---
                    # Left-justified: exactly 3 fixed rows about ONE test run
                    # (a status report, not an open-ended comparison list), so
                    # this fails the "genuinely comparing many values" test -
                    # same category as the leaderboards, not DNS Benchmark.
                    # printf's %Ns counts UTF-8 BYTES, not characters, on this
                    # platform (confirmed: ${#}/wc -m/wc -c/awk length() ALL
                    # miscount multi-byte glyphs like ° identically - there is
                    # no reliable char-counting tool here). ljust() sidesteps
                    # this: it never measures a string containing a multi-byte
                    # char - the caller supplies the true length, computed from
                    # ASCII-only numeric substrings + a known-constant offset
                    # for the fixed °C/°F skeleton around them.
                    ljust() {
                        local width="$1" s="$2" true_len="$3" pad="" i=0
                        while [ "$i" -lt "$((width - true_len))" ]; do pad="${pad} "; i=$((i + 1)); done
                        printf '%s%s' "$s" "$pad"
                    }

                    c_start=$(awk "BEGIN {printf \"%.2f\", $raw_start}")
                    f_start=$(awk "BEGIN {printf \"%.2f\", ($raw_start * 1.8) + 32}")
                    c_end=$(awk "BEGIN {printf \"%.2f\", $raw_end}")
                    f_end=$(awk "BEGIN {printf \"%.2f\", ($raw_end * 1.8) + 32}")
                    c_post=$(awk "BEGIN {printf \"%.2f\", $raw_post}")
                    f_post=$(awk "BEGIN {printf \"%.2f\", ($raw_post * 1.8) + 32}")
                    # "°C (°F)" skeleton = 7 real characters around the two ASCII numbers
                    temp_len_start=$((${#c_start} + ${#f_start} + 7))
                    temp_len_end=$((${#c_end} + ${#f_end} + 7))
                    temp_len_post=$((${#c_post} + ${#f_post} + 7))

                    delta_end="${diff_c}°C (${diff_f}°F)"
                    delta_post="${post_diff_c}°C (${post_diff_f}°F)"
                    delta_len_end=$((${#diff_c} + ${#diff_f} + 7))
                    delta_len_post=$((${#post_diff_c} + ${#post_diff_f} + 7))

                    fan_start="${start_fan_str} RPM"
                    fan_end="${end_fan_str} RPM (${fan_p}%)"
                    fan_post="${post_fan_str} RPM (${fan_post_p}%)"

                    printf "%-10s %s %s %s\n" "PHASE" "$(ljust 22 "TEMPERATURE" 11)" "$(ljust 18 "Δ CHANGE" 8)" "$(ljust 18 "FAN SPEED (Δ%)" 14)"
                    printf "%s\n" "───────────────────────────────────────────────────────────────────────"
                    printf "%-10s %s %s %-18s\n" "Start" "$(ljust 22 "$start_temp_str" "$temp_len_start")" "       ---        " "$fan_start"
                    printf "%-10s %s %s %-18s\n" "End" "$(ljust 22 "$end_temp_str" "$temp_len_end")" "$(ljust 18 "$delta_end" "$delta_len_end")" "$fan_end"
                    printf "%-10s %s %s %-18s\n" "End + 3s" "$(ljust 22 "$post_temp_str" "$temp_len_post")" "$(ljust 18 "$delta_post" "$delta_len_post")" "$fan_post"
                fi         
                press_any_key
                ;;
            2)
                clear
                print_centered_header "VPN & Crypto Benchmark"

                if ! command -v openssl >/dev/null 2>&1; then
                    print_error "OpenSSL not found"
                    press_any_key
                    continue
                fi

                # Reference results, keyed on /proc/gl-hw-info/model. Add a tested
                # device by appending one line in the same column order:
                # id|label|cpu|aes64|aes1420|aes16k|cha64|cha1420|cha16k|rsa_sign|rsa_verify
                bench_ref='mt3600be|Beryl 7|MT7987a|267728|621208|721917|126357|258082|323188|182.9|6850.8
be3600|Slate 7|IPQ5332|148704|390262|469676|68462|158269|185704|103.4|3908.5
mt6000|Flint 2|MT7986a|35969|403625|784938|128188|285938|336125|186.4|6906.5
mt3000|Beryl AX|MT7981|174738|403199|465470|84051|166484|209360|118.7|4446.3
mt5000|Brume 3|MT7987a|268078|621323|723411|126278|257233|323477|181.8|6816.4
be9300|Flint 3|IPQ5332|186703|533571|639020|84930|216067|250916|139.7|5180.6
mt1300|Beryl|MT7621|5522|5944|5759|21915|27148|27613|10.4|397.6'

                my_id=$(cat /proc/gl-hw-info/model 2>/dev/null)
                [ -z "$my_id" ] && my_id="thisdevice"
                my_label=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $2; exit}')
                my_cpu=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $3; exit}')
                [ -z "$my_label" ] && my_label="$my_id"
                [ -z "$my_cpu" ] && my_cpu=$(get_cpu_vendor_model | awk '{print $NF}')

                print_info "Measuring this device - stop VPN, SQM and heavy traffic for accurate, comparable numbers."
                printf "\n"

                bench_measure aes-256-gcm 64;          a64=$BENCH_RESULT
                bench_measure aes-256-gcm 1420;        a1420=$BENCH_RESULT
                bench_measure aes-256-gcm 16384;       a16k=$BENCH_RESULT
                bench_measure chacha20-poly1305 64;    c64=$BENCH_RESULT
                bench_measure chacha20-poly1305 1420;  c1420=$BENCH_RESULT
                bench_measure chacha20-poly1305 16384; c16k=$BENCH_RESULT
                spin_run "Measuring RSA-2048 (connection setup)" openssl speed rsa2048
                rs=$(awk '/^rsa 2048 bits/{print $6; exit}' "$SPIN_LOG")
                rv=$(awk '/^rsa 2048 bits/{print $7; exit}' "$SPIN_LOG")
                rm -f "$SPIN_LOG" 2>/dev/null

                bench_data="/tmp/.glnet-bench.$$"
                {
                    printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$my_id" "$my_label" "$my_cpu" \
                        "${a64:-0}" "${a1420:-0}" "${a16k:-0}" "${c64:-0}" "${c1420:-0}" "${c16k:-0}" "${rs:-0}" "${rv:-0}"
                    printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" 'NF>=11 && $1!=id'
                } > "$bench_data"

                bench_page=1
                while true; do
                    clear
                    print_centered_header "VPN & Crypto Benchmark"
                    case "$bench_page" in
                        1)
                            bench_render_cipher "WireGuard · ChaCha20-Poly1305" 7 8 9 "$bench_data" "$my_id"
                            printf '\n %b64 B = small packets (VoIP/gaming/DNS)      1420 B = VPN throughput (downloads/streaming)%b\n' "$GREY" "$RESET"
                            printf ' %b16 K = raw cipher ceiling, larger than any VPN packet%b\n' "$GREY" "$RESET"
                            printf '\n %bNote: each device uses its own OpenSSL build. WireGuard runs kernel ChaCha20, so that%b\n' "$GREY" "$RESET"
                            printf ' %bcolumn is a proxy; OpenVPN/IPsec uses OpenSSL directly.%b\n' "$GREY" "$RESET"
                            ;;
                        2)
                            bench_render_cipher "OpenVPN / IPsec · AES-256-GCM" 4 5 6 "$bench_data" "$my_id"
                            printf '\n %b64 B = small packets (VoIP/gaming/DNS)      1420 B = VPN throughput (downloads/streaming)%b\n' "$GREY" "$RESET"
                            printf ' %b16 K = raw cipher ceiling, larger than any VPN packet%b\n' "$GREY" "$RESET"
                            ;;
                        3)
                            bench_render_rsa "$bench_data" "$my_id"
                            ;;
                    esac
                    printf " ──────────────────────────────────────────────────────────────────────────────\n"
                    printf " [P] Previous   "
                    bpi=1
                    while [ $bpi -le 3 ]; do
                        if [ $bpi -eq $bench_page ]; then
                            printf "%b[%d]%b " "${BOLD}" "$bpi" "${RESET}"
                        else
                            printf "%b[%d]%b " "${GREY}" "$bpi" "${RESET}"
                        fi
                        bpi=$((bpi + 1))
                    done
                    printf "  [N] Next   [0] Back  "
                    bp=$(read_single_char)
                    printf '\n'
                    case "$bp" in
                        p|P|b|B) [ "$bench_page" -gt 1 ] && bench_page=$((bench_page - 1)) ;;
                        n|N) [ "$bench_page" -lt 3 ] && bench_page=$((bench_page + 1)) ;;
                        1|2|3) bench_page="$bp" ;;
                        0) break ;;
                    esac
                done
                rm -f "$bench_data"
                ;;
            3)
                clear
                print_centered_header "Disk I/O Benchmark"

                available_kb=$(df -Pk . | awk 'NR==2 {print $4}')

                if [ "$available_kb" -ge 1024000 ]; then test_size=1000; test_name="1GB"
                elif [ "$available_kb" -ge 512000 ]; then test_size=500; test_name="500MB"
                elif [ "$available_kb" -ge 256000 ]; then test_size=250; test_name="250MB"
                elif [ "$available_kb" -ge 128000 ]; then test_size=125; test_name="125MB"
                elif [ "$available_kb" -ge 64000 ]; then test_size=64; test_name="64MB"
                elif [ "$available_kb" -ge 32000 ]; then test_size=32; test_name="32MB"
                else test_size=16; test_name="16MB"; fi

                printf "Test size: %b%s%b\n\n" "${GREEN}" "$test_name" "${RESET}"

                get_ms() { read ut _ < /proc/uptime; awk -v t="$ut" 'BEGIN {print int(t * 1000)}'; }

                sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
                w_start=$(get_ms)
                spin_run "Running write test ($test_name)" dd if=/dev/zero of=./testfile bs=1M count=$test_size conv=fsync
                w_end=$(get_ms)

                sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
                r_start=$(get_ms)
                spin_run "Running read test ($test_name)" dd if=./testfile of=/dev/null bs=1M
                r_end=$(get_ms)
                rm -f ./testfile

                w_ms=$((w_end - w_start)); [ "$w_ms" -le 0 ] && w_ms=1
                r_ms=$((r_end - r_start)); [ "$r_ms" -le 0 ] && r_ms=1
                write_speed=$(awk -v sz="$test_size" -v ms="$w_ms" 'BEGIN{printf "%.2f", (sz*1000)/ms}')
                read_speed=$(awk -v sz="$test_size" -v ms="$r_ms" 'BEGIN{printf "%.2f", (sz*1000)/ms}')

                # Reference results, keyed on /proc/gl-hw-info/model. Add a tested
                # device by appending one line: id|label|cpu|write_mbs|read_mbs
                bench_ref='mt3600be|Beryl 7|MT7987a|124.70|11.00
be3600|Slate 7|IPQ5332|75.72|51.50
mt6000|Flint 2|MT7986a|52.72|154.00
mt3000|Beryl AX|MT7981|82.78|16.21
mt5000|Brume 3|MT7987a|38.93|42.32
be9300|Flint 3|IPQ5332|13.72|81.70
mt1300|Beryl|MT7621|0.24|12.54'

                my_id=$(cat /proc/gl-hw-info/model 2>/dev/null)
                [ -z "$my_id" ] && my_id="thisdevice"
                my_label=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $2; exit}')
                my_cpu=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $3; exit}')
                [ -z "$my_label" ] && my_label="$my_id"
                [ -z "$my_cpu" ] && my_cpu=$(get_cpu_vendor_model | awk '{print $NF}')

                bench_data="/tmp/.glnet-bench.$$"
                {
                    printf '%s|%s|%s|%s|%s\n' "$my_id" "$my_label" "$my_cpu" "$write_speed" "$read_speed"
                    printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" 'NF>=5 && $1!=id'
                } > "$bench_data"

                bench_render_disk "$bench_data" "$my_id"
                printf "\n %bWrite is the reliable cross-device metric. Read may reflect the storage%b\n" "$GREY" "$RESET"
                printf " %bcontroller's own onboard cache (notably on eMMC), which OS cache-drop can't%b\n" "$GREY" "$RESET"
                printf " %breach - treat Read as indicative, not absolute. Test size scales with free%b\n" "$GREY" "$RESET"
                printf " %bdisk space, so it can differ between devices.%b\n" "$GREY" "$RESET"
                rm -f "$bench_data"

                printf "\n"
                print_success "Disk benchmark completed"
                press_any_key
                ;;
            4)
                clear
                print_centered_header "Memory I/O Benchmark"

                if [ -f /proc/meminfo ]; then
                    total_mem=$(awk '/MemTotal/ {
                        m = $2 / 1024
                        est = m + 30
                        rounded = (int((est + 127) / 128) * 128)
                        print rounded
                    }' /proc/meminfo)
                fi

                total_mem=${total_mem:-512} # Default to 512MB if we can't read it

                # Determine test size (100k blocks of 1M = 100GB of throughput)
                # We want a large enough test to bypass L1/L2 cache saturation
                if [ "$total_mem" -ge 960 ]; then test_size=100000; test_name="100GB"
                elif [ "$total_mem" -ge 460 ]; then test_size=50000; test_name="50GB"
                else test_size=4000; test_name="4GB"; fi

                printf "System RAM: %b%s MB%b\n" "${GREEN}" "$total_mem" "${RESET}"
                printf "Test throughput: %b%s%b\n\n" "${GREEN}" "$test_name" "${RESET}"

                get_ms() { read ut _ < /proc/uptime; awk -v t="$ut" 'BEGIN {print int(t * 1000)}'; }

                m_start=$(get_ms)
                spin_run "Measuring memory controller throughput" dd if=/dev/zero of=/dev/null bs=1M count=$test_size
                m_end=$(get_ms)

                m_ms=$((m_end - m_start)); [ "$m_ms" -le 0 ] && m_ms=1
                mem_speed=$(awk -v sz="$test_size" -v ms="$m_ms" 'BEGIN{printf "%.2f", (sz*1000)/ms}')

                # Reference results, keyed on /proc/gl-hw-info/model. Add a tested
                # device by appending one line: id|label|cpu|mem_mbs
                bench_ref='mt3600be|Beryl 7|MT7987a|4361.12
be3600|Slate 7|IPQ5332|3006.13
mt6000|Flint 2|MT7986a|5401.50
mt3000|Beryl AX|MT7981|2983.29
mt5000|Brume 3|MT7987a|4492.36
be9300|Flint 3|IPQ5332|4277.16
mt1300|Beryl|MT7621|179.39'

                my_id=$(cat /proc/gl-hw-info/model 2>/dev/null)
                [ -z "$my_id" ] && my_id="thisdevice"
                my_label=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $2; exit}')
                my_cpu=$(printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" '$1==id{print $3; exit}')
                [ -z "$my_label" ] && my_label="$my_id"
                [ -z "$my_cpu" ] && my_cpu=$(get_cpu_vendor_model | awk '{print $NF}')

                bench_data="/tmp/.glnet-bench.$$"
                {
                    printf '%s|%s|%s|%s\n' "$my_id" "$my_label" "$my_cpu" "$mem_speed"
                    printf '%s\n' "$bench_ref" | awk -F'|' -v id="$my_id" 'NF>=4 && $1!=id'
                } > "$bench_data"

                bench_render_mem "$bench_data" "$my_id"
                printf "\n %bMeasures raw memcpy-style throughput via dd, not a full memory-latency%b\n" "$GREY" "$RESET"
                printf " %bbenchmark; test size scales with device RAM to avoid cache saturation.%b\n" "$GREY" "$RESET"
                rm -f "$bench_data"

                printf "\n"
                print_success "Memory benchmark completed"
                press_any_key
                ;;
            5)
                clear
                print_centered_header "DNS Benchmark"

                print_info "Starting Comprehensive DNS Benchmark..."
                printf "\n"
                
                # Pre-check: Can we resolve anything at all?
                if ! nslookup google.com >/dev/null 2>&1; then
                    print_error "DNS is not responding. Check your internet connection or DNS settings."
                    press_any_key
                    continue
                fi

                # Check for Hijacking
                is_proxied=0
                if nslookup "detect${RANDOM}.com" 1.2.3.4 >/dev/null 2>&1; then
                    is_proxied=1
                    print_warning "DNS Interception Active: Traffic is being redirected locally."
                    printf "\n"
                fi
                
                # Servers to test
                SERVERS="127.0.0.1 1.1.1.1 8.8.8.8 9.9.9.9"
                SAMPLES=20  # Number of tests per server
                
                printf " %-22s %8s %8s %8s\n" "DNS Server" "Min" "Avg" "Max"
                printf " ────────────────────────────────────────────────────\n"

                for server in $SERVERS; do
                    case $server in
                        "127.0.0.1") label="Local (AdGuard/Cache)" ;;
                        "1.1.1.1")   label="Cloudflare" ;;
                        "8.8.8.8")   label="Google" ;;
                        "9.9.9.9")   label="Quad9" ;;
                    esac

                    total=0; min=9999; max=0; BURST=5

                    for i in $(seq 1 10); do
                        test_domain="bench${RANDOM}.net"

                        read ut _ < /proc/uptime
                        start_t=$ut
                        
                        # Execute a burst of lookups to exceed the 10ms clock tick
                        for b in $(seq 1 $BURST); do
                            nslookup "$test_domain" "$server" >/dev/null 2>&1
                        done
                        
                        read ut _ < /proc/uptime
                        end_t=$ut
                        
                        # Calculate per-query msec: ((end - start) * 1000) / BURST
                        msec=$(awk -v s="$start_t" -v e="$end_t" -v b="$BURST" \
                              'BEGIN { printf "%.2f", ((e - s) * 1000) / b }')

                        # Update stats
                        min=$(awk -v m="$msec" -v cur="$min" 'BEGIN { print (m < cur ? m : cur) }')
                        max=$(awk -v m="$msec" -v cur="$max" 'BEGIN { print (m > cur ? m : cur) }')
                        total=$(awk -v m="$msec" -v t="$total" 'BEGIN { print t + m }')
                    done

                    avg=$(awk -v t="$total" 'BEGIN { printf "%.2f", t / 10 }')

                    COLOR=$CYAN
                    if [ $(awk -v a="$avg" 'BEGIN {print (a < 15.0 ? 1 : 0)}') -eq 1 ]; then 
                        COLOR=$GREEN
                    fi
                        
                    printf " %-22s %b%8s %8s %8s%b ms\n" "$label" "$COLOR" "$min" "$avg" "$max" "$RESET"
                done
                
                printf "\n"
                print_success "DNS Benchmark completed"
                press_any_key
                ;;
            6)
                clear
                print_centered_header "Ookla Network Speedtest"
                install_ookla_speedtest
                
                printf "\n%b\n" "${YELLOW}⏳ Running Ookla Speedtest...${RESET}"
                printf "──────────────────────────────────────────────────────────────────────────────────────────\n"

                speedtest -a --accept-license --accept-gdpr 2>/dev/null
                
                printf "\n──────────────────────────────────────────────────────────────────────────────────────────\n"
                print_success "Ookla Speedtest completed"
                press_any_key
                ;;
            7)  manage_librespeed ;;
            8)  
                lan_ipaddr=$(get_lan_ip)
                clear
                print_centered_header "iperf3 Network Speed Test Server"
                
                if ! command -v iperf3 >/dev/null 2>&1; then
                    install_package iperf3
                fi
                
                printf "%b\n\n" "${YELLOW}⏳ Starting iperf3 Server on port 5201...${RESET}"
                print_info "Client usage:"
                printf "   Download:  %biperf3 -c %s -P 6 -R -t 60%b\n" "${CYAN}" "$lan_ipaddr" "${RESET}"
                printf "   Upload:    %biperf3 -c %s -P 4 -t 60%b\n" "${CYAN}" "$lan_ipaddr" "${RESET}"
                
                printf "\n%bPress Ctrl+C to stop the server and return to menu.%b\n" "${YELLOW}" "${RESET}"
                trap 'printf "\n%s\n" "──────────────────────────────────────────────────────────────────────"' INT
                iperf3 -s
                trap - INT
                print_success "iperf3 Server stopped"
                press_any_key
                ;;
            9)  install_openspeedtest ;;
            0)
                return
                ;;
            \?|h|H|❓) show_benchmarks_help ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# UCI Configuration Viewer
# -----------------------------
show_uci_help() {
    clear
    print_centered_header "System Configuration Viewer - Help"

    cat << 'HELPEOF'
What is this?
─────────────
A READ-ONLY viewer for the router's UCI configuration. Choosing a category
prints its current settings so you can inspect them — nothing is changed,
saved or committed from this screen.

Getting around:
• Type the number shown beside a category and press Enter to view it.
• [0] returns to the Main menu.
• [?] shows this help.
HELPEOF

    press_any_key
}

view_uci_config() {
    while true; do
        clear
        print_centered_header "System Configuration Viewer"
        printf "%s  Wireless Networks\n" "$N1"
        printf "%s  Network Configuration\n" "$N2"
        printf "%s  VPN Configuration\n" "$N3"
        printf "%s  System Settings\n" "$N4"
        printf "%s  Cloud Services\n" "$N5"
        printf "%s  Main menu\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-5/0/?]: "
        read -r config_choice
        printf "\n"
        
        case $config_choice in
            \?|h|H|❓) show_uci_help ;;
            1)
                clear
                print_centered_header "Wireless Networks"
                
                all_ifaces=""
                for iface in $(uci show wireless 2>/dev/null | grep "wifi-iface" | cut -d'.' -f2 | cut -d'=' -f1 | sort -u); do
                    ssid=$(uci get wireless.${iface}.ssid 2>/dev/null)
                    [ -n "$ssid" ] && all_ifaces="$all_ifaces $iface"
                done
                
                mlo_ifaces=""
                five_ifaces=""
                two_ifaces=""
                
                for iface in $all_ifaces; do
                    device=$(uci get wireless.${iface}.device 2>/dev/null)
                    band=$(uci get wireless.${device}.band 2>/dev/null)
                    
                    if uci get wireless.${iface}.mlo 2>/dev/null | grep -q "1"; then
                        mlo_ifaces="$mlo_ifaces $iface"
                    elif [ "$band" = "5g" ] || [ "$band" = "6g" ]; then
                        five_ifaces="$five_ifaces $iface"
                    elif [ "$band" = "2g" ]; then
                        two_ifaces="$two_ifaces $iface"
                    else
                        two_ifaces="$two_ifaces $iface"
                    fi
                done
                
                count=0
                for iface in $mlo_ifaces $five_ifaces $two_ifaces; do

                    if [ $((count % 2)) -eq 0 ] && [ $count -gt 0 ]; then
                       press_any_key
                       clear
                       print_centered_header "Wireless Networks"
                    fi
                    
                    ssid=$(uci get wireless.${iface}.ssid 2>/dev/null)
                    key=$(uci get wireless.${iface}.key 2>/dev/null)
                    encryption=$(uci get wireless.${iface}.encryption 2>/dev/null)
                    disabled=$(uci get wireless.${iface}.disabled 2>/dev/null)
                    hidden=$(uci get wireless.${iface}.hidden 2>/dev/null)
                    device=$(uci get wireless.${iface}.device 2>/dev/null)
                    mode=$(uci get wireless.${iface}.mode 2>/dev/null)
                    
                    band=$(uci get wireless.${device}.band 2>/dev/null)
                    htmode=$(uci get wireless.${device}.htmode 2>/dev/null)
                    channel=$(uci get wireless.${device}.channel 2>/dev/null)
                    
                    case "$band" in
                        2g) band_name="2.4GHz" ;;
                        5g) band_name="5GHz" ;;
                        6g) band_name="6GHz" ;;
                        *) band_name="Unknown" ;;
                    esac
                    
                    if uci get wireless.${iface}.mlo 2>/dev/null | grep -q "1"; then
                        band_name="MLO (Multi-Link)"
                    fi
                    
                    printf "%b\n" "${CYAN}Interface: $iface ($band_name)${RESET}"
                    printf "  SSID: %b%s%b\n" "${GREEN}" "$ssid" "${RESET}"
                    [ -n "$key" ] && printf "  Password: %b%s%b\n" "${YELLOW}" "$key" "${RESET}"
                    [ -n "$encryption" ] && printf "  Encryption: %s\n" "$encryption"
                    
                    if [ "$hidden" = "1" ]; then
                        printf "  Visibility: %bHidden%b\n" "${YELLOW}" "${RESET}"
                    else
                        printf "  Visibility: %bVisible%b\n" "${GREEN}" "${RESET}"
                    fi
                    
                    [ -n "$mode" ] && printf "  Mode: %s\n" "$mode"
                    [ -n "$htmode" ] && printf "  Bandwidth: %s\n" "$htmode"
                    [ -n "$channel" ] && printf "  Channel: %s\n" "$channel"
                    
                    if [ "$disabled" = "1" ]; then
                        printf "  Status: %bDisabled%b\n" "${RED}" "${RESET}"
                    else
                        printf "  Status: %bEnabled%b\n" "${GREEN}" "${RESET}"
                    fi
                    printf "\n"
                    count=$((count + 1))
                done
                
                press_any_key
                ;;
            2)
                clear
                print_centered_header "Network Configuration"
                
                printf "%b\n" "${CYAN}WAN Configuration:${RESET}"
                wan_proto=$(uci get network.wan.proto 2>/dev/null)
                wan_ipaddr=$(uci get network.wan.ipaddr 2>/dev/null)
                wan_netmask=$(uci get network.wan.netmask 2>/dev/null)
                wan_gateway=$(uci get network.wan.gateway 2>/dev/null)
                wan_dns=$(uci get network.wan.dns 2>/dev/null)
                
                [ -n "$wan_proto" ] && printf "  Protocol: %s\n" "$wan_proto"
                [ -n "$wan_ipaddr" ] && printf "  IP Address: %b%s%b\n" "${GREEN}" "$wan_ipaddr" "${RESET}"
                [ -n "$wan_netmask" ] && printf "  Netmask: %s\n" "$wan_netmask"
                [ -n "$wan_gateway" ] && printf "  Gateway: %s\n" "$wan_gateway"
                [ -n "$wan_dns" ] && printf "  DNS: %s\n" "$wan_dns"
                
                printf "\n%b\n" "${CYAN}LAN Configuration:${RESET}"
                lan_ipaddr=$(get_lan_ip)
                lan_netmask=$(uci get network.lan.netmask 2>/dev/null)
                lan_proto=$(uci get network.lan.proto 2>/dev/null)
                
                [ -n "$lan_proto" ] && printf "  Protocol: %s\n" "$lan_proto"
                [ -n "$lan_ipaddr" ] && printf "  IP Address: %b%s%b\n" "${GREEN}" "$lan_ipaddr" "${RESET}"
                [ -n "$lan_netmask" ] && printf "  Netmask: %s\n" "$lan_netmask"
                
                printf "\n%b\n" "${CYAN}DHCP Server:${RESET}"
                dhcp_start=$(uci get dhcp.lan.start 2>/dev/null)
                dhcp_limit=$(uci get dhcp.lan.limit 2>/dev/null)
                dhcp_leasetime=$(uci get dhcp.lan.leasetime 2>/dev/null)
                
                [ -n "$dhcp_start" ] && printf "  Start: %s\n" "$dhcp_start"
                [ -n "$dhcp_limit" ] && printf "  Limit: %s\n" "$dhcp_limit"
                [ -n "$dhcp_leasetime" ] && printf "  Lease Time: %s\n" "$dhcp_leasetime"
                printf "\n"
                
                press_any_key
                ;;
            3)
                clear
                print_centered_header "VPN Configuration"
                
                found_vpn=0
                
                if uci show network 2>/dev/null | grep -q "proto='wireguard'"; then
                    printf "%b\n" "${CYAN}WireGuard Servers:${RESET}"
                    for iface in $(uci show network | grep "proto='wireguard'" | cut -d'.' -f2 | cut -d'=' -f1); do
                        private_key=$(uci get network.${iface}.private_key 2>/dev/null)
                        listen_port=$(uci get network.${iface}.listen_port 2>/dev/null)
                        addresses=$(uci get network.${iface}.addresses 2>/dev/null)
                        
                        printf "  Interface: %b%s%b\n" "${GREEN}" "$iface" "${RESET}"
                        [ -n "$listen_port" ] && printf "    Listen Port: %s\n" "$listen_port"
                        [ -n "$addresses" ] && printf "    Addresses: %s\n" "$addresses"
                        [ -n "$private_key" ] && printf "    Private Key: %b[configured]%b\n" "${YELLOW}" "${RESET}"
                        printf "\n"
                        found_vpn=1
                    done
                fi
                
                if uci show wireguard 2>/dev/null | grep -q "=peers"; then
                    printf "%b\n" "${CYAN}WireGuard Clients:${RESET}"
                    for peer in $(uci show wireguard 2>/dev/null | grep "=peers" | cut -d'.' -f2 | cut -d'=' -f1); do
                        name=$(uci get wireguard.${peer}.name 2>/dev/null)
                        endpoint=$(uci get wireguard.${peer}.end_point 2>/dev/null)
                        addr_v4=$(uci get wireguard.${peer}.address_v4 2>/dev/null)
                        allowed=$(uci get wireguard.${peer}.allowed_ips 2>/dev/null)
                        keepalive=$(uci get wireguard.${peer}.persistent_keepalive 2>/dev/null)
                        
                        printf "  Peer: %b%s%b\n" "${GREEN}" "${name:-$peer}" "${RESET}"
                        [ -n "$endpoint" ] && printf "    Endpoint: %s\n" "$endpoint"
                        [ -n "$addr_v4" ] && printf "    Address: %s\n" "$addr_v4"
                        [ -n "$allowed" ] && printf "    Allowed IPs: %s\n" "$allowed"
                        [ -n "$keepalive" ] && printf "    Keepalive: %s sec\n" "$keepalive"
                        printf "\n"
                        found_vpn=1
                    done
                fi
                
                if [ -f /etc/config/openvpn ] && uci show openvpn 2>/dev/null | grep -q "enabled='1'"; then
                    printf "%b\n" "${CYAN}OpenVPN Instances:${RESET}"
                    for instance in $(uci show openvpn | grep "enabled='1'" | cut -d'.' -f2 | cut -d'=' -f1); do
                        config=$(uci get openvpn.${instance}.config 2>/dev/null)
                        proto=$(uci get openvpn.${instance}.proto 2>/dev/null)
                        port=$(uci get openvpn.${instance}.port 2>/dev/null)
                        
                        printf "  Instance: %b%s%b\n" "${GREEN}" "$instance" "${RESET}"
                        [ -n "$config" ] && printf "    Config: %s\n" "$config"
                        [ -n "$proto" ] && printf "    Protocol: %s\n" "$proto"
                        [ -n "$port" ] && printf "    Port: %s\n" "$port"
                        printf "\n"
                        found_vpn=1
                    done
                fi
                
                if [ "$found_vpn" -eq 0 ]; then
                    print_warning "No active VPN configurations found"
                    printf "\n"
                fi
                
                press_any_key
                ;;
            4)
                clear
                print_centered_header "System Settings"
                
                printf "%b\n" "${CYAN}System Information:${RESET}"
                hostname=$(uci get system.@system[0].hostname 2>/dev/null)
                timezone=$(uci get system.@system[0].timezone 2>/dev/null)
                zonename=$(uci get system.@system[0].zonename 2>/dev/null)
                
                [ -n "$hostname" ] && printf "  Hostname: %b%s%b\n" "${GREEN}" "$hostname" "${RESET}"
                [ -n "$zonename" ] && printf "  Timezone: %s\n" "$zonename"
                [ -n "$timezone" ] && printf "  TZ String: %s\n" "$timezone"
                
                printf "\n%b\n" "${CYAN}Root Access:${RESET}"
                if grep -q "^root:[^\*!]" /etc/shadow 2>/dev/null; then
                    printf "  Root Password: %b%s%b\n" "${GREEN}" "Set" "${RESET}"
                else
                    printf "  Root Password: %b%s%b\n" "${RED}" "Not Set" "${RESET}"
                fi
                
                ssh_port=$(uci get dropbear.@dropbear[0].Port 2>/dev/null)
                ssh_interface=$(uci get dropbear.@dropbear[0].Interface 2>/dev/null)
                ssh_pass=$(uci get dropbear.@dropbear[0].PasswordAuth 2>/dev/null)
                ssh_root=$(uci get dropbear.@dropbear[0].RootPasswordAuth 2>/dev/null)
                
                printf "\n%b\n" "${CYAN}SSH Configuration:${RESET}"
                [ -n "$ssh_port" ] && printf "  Port: %s\n" "$ssh_port" || printf "  Port: 22 (default)\n"
                [ -n "$ssh_interface" ] && printf "  Interface: %s\n" "$ssh_interface"
                
                if [ "$ssh_pass" = "0" ]; then
                    printf "  Password Auth: %b%s%b\n" "${RED}" "Disabled" "${RESET}"
                else
                    printf "  Password Auth: %b%s%b\n" "${GREEN}" "Enabled" "${RESET}"
                fi
                
                if [ "$ssh_root" = "0" ]; then
                    printf "  Root Login: %b%s%b\n" "${RED}" "Disabled" "${RESET}"
                else
                    printf "  Root Login: %b%s%b\n" "${GREEN}" "Enabled" "${RESET}"
                fi
                printf "\n"
                
                press_any_key
                ;;
            5)
                clear
                print_centered_header "Cloud Services"
                
                printf "%b\n" "${CYAN}GoodCloud:${RESET}"
                if [ -f /etc/config/gl-cloud ]; then
                    gc_enable=$(uci get gl-cloud.@cloud[0].enable 2>/dev/null)
                    gc_deviceid=$(uci get gl-cloud.@cloud[0].token 2>/dev/null)
                    gc_server=$(uci get gl-cloud.@cloud[0].server 2>/dev/null)
                    gc_email=$(uci get gl-cloud.@cloud[0].email 2>/dev/null)
                    
                    if [ "$gc_enable" = "1" ]; then
                        printf "  Status: %bENABLED%b\n" "${GREEN}" "${RESET}"
                    else
                        printf "  Status: %bDISABLED%b\n" "${RED}" "${RESET}"
                    fi
                    
                    [ -n "$gc_email" ] && printf "  Account: %b%s%b\n" "${GREEN}" "$gc_email" "${RESET}"
                    [ -n "$gc_server" ] && printf "  Server: %s\n" "$gc_server"
                    if [ -n "$gc_deviceid" ]; then
                        token_short=$(printf "%s" "$gc_deviceid" | cut -c1-16)
                        printf "  Token: %s\n" "${token_short}..."
                    fi
                else
                    print_warning "GoodCloud not configured"
                fi
                
                printf "\n%b\n" "${CYAN}AstroWarp:${RESET}"
                if ip link show mptun0 >/dev/null 2>&1 && ip -4 addr show mptun0 | grep -q 'inet '; then
                    printf "  Status: %bACTIVE%b\n" "${GREEN}" "${RESET}"
                    mptun_ip=$(ip -4 addr show mptun0 | grep 'inet ' | awk '{print $2}')
                    [ -n "$mptun_ip" ] && printf "  Interface: mptun0 (%s)\n" "$mptun_ip"
                else
                    printf "  Status: %bNOT ACTIVE%b\n" "${RED}" "${RESET}"
                    printf "  (No mptun0 interface or no IP assigned)\n"
                fi
                
                press_any_key
                ;;
            0)
                return
                ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

install_openspeedtest() {
    local script_url="https://raw.githubusercontent.com/phantasm22/OpenSpeedTestServer/main/install_openspeedtest.sh"
    local script_name="install_openspeedtest.sh"
    local expected_header="Author: phantasm22"

    clear
    print_centered_header "OpenSpeedTest Server Installation"

    # Check if we need to download (file missing OR invalid header)
    if [ ! -f "$script_name" ] || ! grep -q "$expected_header" "$script_name"; then
        _ost_fetch() { wget -q -O "$script_name" "$script_url" && [ -s "$script_name" ]; }

        if spin_run "Downloading OpenSpeedTest installer" _ost_fetch; then
            rm -f "$SPIN_LOG" 2>/dev/null
            chmod +x "$script_name"
            print_success "Download successful."
        else
            rm -f "$SPIN_LOG" 2>/dev/null
            print_error "Failed to download installer. Please check your connection."
            rm -f "$script_name"
            press_any_key
            return 1
        fi
    fi

    # Execute the script
    print_info "Launching installer..."
    printf "\n"
    sleep 2
    
    # Check for execution bit just in case
    [ ! -x "$script_name" ] && chmod +x "$script_name"
    
    ./"$script_name"
    
    # Handle post-execution status
    if [ $? -eq 0 ]; then
        print_success "OpenSpeedTest setup sequence finished."
    else
        print_warning "Installer exited with a non-zero status."
    fi

    press_any_key
}

# -----------------------------
# Startup
# -----------------------------
# Splash + terminal detection already ran at load time (see detect_output_mode).
check_install_prompt "$@"
printf "\n"
check_self_update "$@"

# -----------------------------
# Service Verification
# -----------------------------

if [ ! -f "$AGH_INIT" ]; then
    clear
    printf "%b\n" "$SPLASH"
    if [ ! -f "/rom$AGH_INIT" ]; then
        print_warning "AdGuardHome not found/supported. AdGuardHome features will be disabled." 
        AGH_DISABLED=1
        press_any_key
    else
        print_error "AdGuardHome startup script missing! Will attempt AGH factory reset to restore it."
        sub_confirm_factory_reset
        if [ ! -f "$AGH_INIT" ]; then
            AGH_DISABLED=1
            printf "\n"
            print_warning "Recovery failed or cancelled. AdGuardHome features will be disabled."
            press_any_key
        fi
    fi
fi


# -----------------------------
# Main Menu
# -----------------------------
show_main_help() {
    clear
    print_centered_header "GL.iNet Toolkit - Main Menu Help"

    cat << 'HELPEOF'
What is this?
─────────────
The top-level menu of the GL.iNet router toolkit. Each entry opens a dedicated
area of the toolkit:

• Hardware Information      – read-only system, CPU, memory and thermal details
• AdGuardHome Control Center – DNS filtering, backups and service control
• System Tweaks             – hardware, network, package and toolkit settings
• System Benchmarks         – CPU, memory, disk and network speed tests
• System Configuration      – read-only view of the router's UCI config

Getting around (the same keys work on every screen):
• Type the number shown beside an item and press Enter to open it.
• [0] leaves the current screen — here it exits the toolkit; on inner screens
  it goes Back, or returns to the Main menu.
• [?] shows the help for whichever screen you are on.
HELPEOF

    press_any_key
}

show_menu() {
    while true; do
        clear
        printf "%b\n" "$SPLASH"
        printf "%b\n" "${CYAN}Please select an option:${RESET}\n"
        printf "%s  Show Hardware Information\n" "$N1"
        printf "%s  AdGuardHome Control Center\n" "$N2"
        printf "%s  System Tweaks\n" "$N3"
        printf "%s  System Benchmarks\n" "$N4"
        printf "%s  View System Configuration (UCI)\n" "$N5"
        printf "%s  Exit\n" "$N0"
        printf "%s Help\n" "$NQ"
        printf "\nChoose [1-5/0/?]: "
        read opt
        
        case $opt in
            \?|h|H|❓) show_main_help ;;
            1) show_hardware_info ;;
            2) [ $AGH_DISABLED != 1 ] && agh_control_center || { print_error "AGH not found. Feature disabled."; sleep 2; } ;;
            3) system_tweaks ;;
            4) benchmark_system ;;
            5) view_uci_config ;;
            0) clear; printf "\n"; print_success "Thanks for using GL.iNet Toolkit!"; printf "\n"; exit 0 ;;
            *) print_error "Invalid option"; sleep 1 ;;
        esac
    done
}

# -----------------------------
# Start
# -----------------------------
show_menu
