#!/usr/bin/env bash
# =============================================================================
# SCROW - UI core
# =============================================================================
# Terminal ownership, input handling, sizing and the shared render helpers
# used by every SCROW screen. This is the only module that talks to the
# terminal directly. Widgets live in widgets.sh, the progress panel in
# progress.sh (both sourced at the bottom of this file).
#
# Render contract:
#   - screens are built from full-width lines (2-space side margins)
#   - every widget owns the full terminal while it is active
#   - ui_init()/ui_cleanup() guarantee the terminal is restored on exit
# =============================================================================

export UI_INTERACTIVE=0
[[ -t 0 ]] && UI_INTERACTIVE=1

export UI_QUIET=0          # set by flows while the progress panel is live
export UI_RESIZED=0        # set by SIGWINCH; consumed as a "none" key

_UI_TTY_OUT=0
[[ -t 1 ]] && _UI_TTY_OUT=1

# -----------------------------------------------------------------------------
# Terminal ownership / cleanup
# -----------------------------------------------------------------------------
_UI_INITIALIZED=0
_UI_STTY_SAVED=""

ui_init() {
    [[ "$_UI_INITIALIZED" == "1" ]] && return 0
    _UI_INITIALIZED=1
    if [[ "$_UI_TTY_OUT" == "1" ]]; then
        _UI_STTY_SAVED="$(stty -g 2>/dev/null)"
        printf '\033[?25l'   # hide cursor while the application is active
    fi
    trap 'ui_cleanup' EXIT
    trap 'ui_cleanup; exit 130' INT
    trap 'ui_cleanup; exit 143' TERM HUP
    trap 'UI_RESIZED=1' WINCH
}

ui_cleanup() {
    [[ "$_UI_INITIALIZED" == "0" ]] && return 0
    _UI_INITIALIZED=0
    if [[ "$_UI_TTY_OUT" == "1" ]]; then
        printf '\033[?25h\033[0m'   # restore cursor and attributes
        [[ -n "$_UI_STTY_SAVED" ]] && stty "$_UI_STTY_SAVED" 2>/dev/null
    fi
    trap - EXIT INT TERM HUP WINCH
}

# -----------------------------------------------------------------------------
# Sizing
# -----------------------------------------------------------------------------
_ui_cols() {
    local c
    c="$(tput cols 2>/dev/null)"
    [[ "$c" =~ ^[0-9]+$ ]] || c="${COLUMNS:-}"
    [[ "$c" =~ ^[0-9]+$ ]] || c=80
    (( c < 20 )) && c=20
    printf '%s' "$c"
}

_ui_rows() {
    local r
    r="$(tput lines 2>/dev/null)"
    [[ "$r" =~ ^[0-9]+$ ]] || r="${LINES:-}"
    [[ "$r" =~ ^[0-9]+$ ]] || r=24
    (( r < 6 )) && r=6
    printf '%s' "$r"
}

# -----------------------------------------------------------------------------
# String helpers (all width math is visible-width based)
# -----------------------------------------------------------------------------
_ui_vislen() {
    local s="$1"
    [[ "$s" != *$'\033['* ]] && { printf '%s' "${#s}"; return; }
    printf '%s' "$s" | sed $'s/\033\[[0-9;]*m//g' | awk '{ print length }'
}

_ui_trunc() {
    local text="$1" max="$2" out="" ch
    (( max < 0 )) && max=0
    local vis
    vis=$(_ui_vislen "$text")
    (( vis <= max )) && { printf '%s' "$text"; return; }
    (( max > 0 )) || return 0
    while [[ -n "$text" ]]; do
        [[ "${#out}" -ge $(( max - 1 )) ]] && break
        ch="${text:0:1}"
        [[ "$ch" == $'\033' ]] && break
        out+="$ch"
        text="${text:1}"
    done
    printf '%s…' "$out"
}

_ui_pad_to() {
    local target="$1" text="$2" vis
    vis=$(_ui_vislen "$text")
    (( vis >= target )) && { printf '%s' "$text"; return; }
    printf '%s%*s' "$text" "$(( target - vis ))" ""
}

_ui_center_text() {
    local text="$1" width="$2" vis pad
    vis=$(_ui_vislen "$text")
    (( vis >= width )) && { printf '%s' "$text"; return; }
    pad=$(( (width - vis) / 2 ))
    printf '%*s%s%*s' "$pad" "" "$text" "$(( width - vis - pad ))" ""
}

# left-aligned $1, right-aligned $2, into $3 columns
_ui_fill() {
    local left="$1" right="$2" inner="$3" lv rv pad
    lv=$(_ui_vislen "$left"); rv=$(_ui_vislen "$right")
    pad=$(( inner - lv - rv )); (( pad < 0 )) && pad=0
    printf '%s%s%s' "$left" "$(printf '%*s' "$pad" "")" "$right"
}

# -----------------------------------------------------------------------------
# Line primitives
# -----------------------------------------------------------------------------
_ui_inner() {
    local inner
    inner=$(( $(_ui_cols) - 4 ))
    (( inner < 2 )) && inner=2
    printf '%s' "$inner"
}

# Padded full-width line. $1 = text, $2 = "1" for reverse (selected) row.
_ui_line() {
    local text="$1" rev="${2:-0}"
    if [[ "$rev" == "1" ]]; then
        printf '\033[7m  %s  \033[0m\n' "$(_ui_pad_to "$(_ui_inner)" "$text")"
    else
        printf '  %s\n' "$(_ui_pad_to "$(_ui_inner)" "$text")"
    fi
}

# Like _ui_line but without the trailing newline (for in-place redraws).
_ui_line_str() {
    local text="$1" rev="${2:-0}"
    if [[ "$rev" == "1" ]]; then
        printf '\033[7m  %s  \033[0m' "$(_ui_pad_to "$(_ui_inner)" "$text")"
    else
        printf '  %s' "$(_ui_pad_to "$(_ui_inner)" "$text")"
    fi
}

# Rewrite one terminal line in place (row is 1-based).
_ui_line_at() {
    printf '\033[%d;1H\033[K' "$1"
    printf '%s' "$2"
}

_ui_rule() {
    printf '%s%s%s\n' "$C_DIM" "$(printf '─%.0s' $(seq 1 "$(_ui_cols)"))" "$C_RESET"
}

_ui_blank() { printf '\n'; }

_ui_section() {
    printf '  %s%s%s\n' "$C_BOLD$C_ACCENT" "$1" "$C_RESET"
}

_ui_hintbar() {
    printf '  %s%s%s\n' "$C_DIM" "$1" "$C_RESET"
}

# Title line with the leading word in the accent brand color.
# $1 = title ("SCROW Manager" -> accent SCROW + bold Manager)
# $2 = optional right-aligned text (dim).
_ui_title_line() {
    local title="$1" right="${2:-}" w first rest left
    w=$(_ui_cols)
    first="${title%% *}"
    rest="${title#* }"
    if [[ -n "$rest" ]]; then
        left="  ${C_ACCENT}${first}${C_RESET} ${C_BOLD}${rest}${C_RESET}"
    else
        left="  ${C_ACCENT}${first}${C_RESET}"
    fi
    if [[ -n "$right" ]]; then
        local pad
        pad=$(( w - $(_ui_vislen "$left") - $(_ui_vislen "$right") ))
        (( pad < 1 )) && pad=1
        printf '%s%s%s\n' "$left" "$(printf '%*s' "$pad" "")" "${C_DIM}${right}${C_RESET}"
    else
        printf '%s\n' "$left"
    fi
}

# Standard screen header used by every screen.
# $1 = title, $2 = right-aligned text, $3 = subtitle (dim).
_ui_screen_header() {
    local title="$1" right="${2:-}" subtitle="${3:-}"
    _ui_title_line "$title" "$right"
    [[ -n "$subtitle" ]] && printf '  %s%s%s\n' "$C_DIM" "$subtitle" "$C_RESET"
    _ui_rule
    _ui_blank
}

ui_clear() { printf '\033[2J\033[H'; }

# -----------------------------------------------------------------------------
# Status-line API (plain, suppressed while the progress panel is active)
# -----------------------------------------------------------------------------
ui_info()  { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s %s%s\n' "$C_ACCENT" "›" "$C_RESET $1"; }
ui_ok()    { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s %s%s %s\n' "$C_OK" "✓" "$C_RESET" "$1"; }
ui_warn()  { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s %s%s %s\n' "$C_WARN" "⚠" "$C_RESET" "$1"; }
ui_err()   { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s %s%s %s\n' "$C_ERR" "✗" "$C_RESET" "$1"; }
ui_step()  { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s %s%s %s\n' "$C_ACCENT" "▸" "$C_RESET" "$1"; }
ui_dim()   { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s%s%s\n' "$C_FAINT" "$1" "$C_RESET"; }
ui_text()  { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s\n' "$1"; }
ui_error() { ui_err "$1"; }
ui_hr()    { _ui_rule; }

# -----------------------------------------------------------------------------
# Key input
# -----------------------------------------------------------------------------
UI_KEY=""

ui_readkey() {
    UI_KEY=""
    if [[ "$UI_INTERACTIVE" != "1" ]]; then
        local line
        if ! IFS= read -r line; then
            UI_KEY="eof"
            return
        fi
        case "$line" in
            ""|"enter")           UI_KEY="enter" ;;
            "y"|"Y")              UI_KEY="y" ;;
            "n"|"N")              UI_KEY="n" ;;
            "q"|"Q")              UI_KEY="q" ;;
            "esc"|"back"|"x")     UI_KEY="esc" ;;
            "eof"|"quit")         UI_KEY="eof" ;;
            " "|"space"|"toggle") UI_KEY="space" ;;
            "up"|"u"|"k")         UI_KEY="up" ;;
            "down"|"d"|"j")       UI_KEY="down" ;;
            "left"|"h")           UI_KEY="left" ;;
            "right"|"l")          UI_KEY="right" ;;
            [0-9])                UI_KEY="num$line" ;;
            *)                    UI_KEY="none" ;;
        esac
        return
    fi

    local key rest
    IFS= read -r -s -n1 key 2>/dev/null
    if [[ -z "$key" ]]; then
        # A signal (e.g. SIGWINCH) interrupted read: don't treat as Enter.
        if (( UI_RESIZED )); then
            UI_RESIZED=0
            UI_KEY="none"
        else
            UI_KEY="enter"
        fi
        return
    fi
    case "$key" in
        $'\033')
            IFS= read -r -s -n2 -t 0.05 rest 2>/dev/null
            case "$rest" in
                "[A"|"OA") UI_KEY="up" ;;
                "[B"|"OB") UI_KEY="down" ;;
                "[C"|"OC") UI_KEY="right" ;;
                "[D"|"OD") UI_KEY="left" ;;
                *)         UI_KEY="esc" ;;
            esac
            ;;
        $'\n'|$'\r')   UI_KEY="enter" ;;
        " ")           UI_KEY="space" ;;
        $'\t')         UI_KEY="tab" ;;
        $'\x03')       UI_KEY="int" ;;
        $'\x04')       UI_KEY="eof" ;;
        "q"|"Q")       UI_KEY="q" ;;
        "k"|"K")       UI_KEY="up" ;;
        "j"|"J")       UI_KEY="down" ;;
        "l"|"L")       UI_KEY="right" ;;
        "h"|"H")       UI_KEY="left" ;;
        "y"|"Y")       UI_KEY="y" ;;
        "n"|"N")       UI_KEY="n" ;;
        [0-9])         UI_KEY="num$key" ;;
        *)             UI_KEY="$key" ;;
    esac
}

ui_pause() {
    printf '  %s%s%s\n' "$C_DIM" "${1:-Press}  Enter to continue" "$C_RESET"
    ui_readkey
}

# -----------------------------------------------------------------------------
# Load the widget / progress modules
# -----------------------------------------------------------------------------
_UI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "$(dirname "${BASH_SOURCE[0]}")")"
. "$_UI_DIR/widgets.sh"
. "$_UI_DIR/progress.sh"
