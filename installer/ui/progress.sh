#!/usr/bin/env bash
# =============================================================================
# SCROW - progress panel
# =============================================================================
# A single-screen status panel for long operations (install, update, reset,
# restore, uninstall). Each phase is one line that flips between:
#     ○ pending      ▸ running (bold)      ✓ done      ✗ failed      ⚠ warn
# A status line at the bottom names the phase that is currently executing.
# Output from phase functions is redirected to the SCROW log (UI_QUIET=1);
# nothing leaks onto this panel.
# =============================================================================

UI_PROGRESS_TITLE=""
UI_PROGRESS_STEPS=()
UI_PROGRESS_STATUS=()
UI_PROGRESS_ACTIVE=0
UI_PROGRESS_BASE=4
UI_PROGRESS_STATUS_ROW=0

ui_progress_start() {
    UI_PROGRESS_TITLE="$1"
    UI_PROGRESS_STEPS=()
    UI_PROGRESS_STATUS=()
    UI_PROGRESS_ACTIVE=0
}

ui_progress_add() {
    UI_PROGRESS_STEPS+=("$1")
    UI_PROGRESS_STATUS+=(0)
}

_ui_progress_icon() {
    case "$1" in
        1) printf '✓' ;;
        2) printf '▸' ;;
        3) printf '✗' ;;
        4) printf '⚠' ;;
        *) printf '○' ;;
    esac
}

_ui_progress_color() {
    case "$1" in
        1) printf '%s' "$C_OK" ;;
        2) printf '%s' "$C_ACCENT" ;;
        3) printf '%s' "$C_ERR" ;;
        4) printf '%s' "$C_WARN" ;;
        *) printf '%s' "$C_DIM" ;;
    esac
}

_ui_progress_mark() {
    local idx="$1" icon color num label
    icon="$(_ui_progress_icon "${UI_PROGRESS_STATUS[$idx]}")"
    color="$(_ui_progress_color "${UI_PROGRESS_STATUS[$idx]}")"
    num=$(( idx + 1 ))
    label="${UI_PROGRESS_STEPS[$idx]}"
    if [[ "${UI_PROGRESS_STATUS[$idx]}" == "2" ]]; then
        printf '%s▸%s %s%s%s  %s%s%s' "$color" "$C_RESET" "$C_BOLD" "$num" "$C_RESET" "$C_BOLD" "$label" "$C_RESET"
    else
        printf '%s %s%s%s %s%s%s  %s' "$color" "$icon" "$C_RESET" "$C_DIM" "$num" "$C_RESET" "$label" "$C_RESET"
    fi
}

_ui_progress_inplace() {
    local row="$1" text="$2"
    if [[ "$_UI_TTY_OUT" == "1" ]]; then
        printf '\033[%d;1H\033[K  %s' "$row" "$text"
    else
        printf '  %s\n' "$text"
    fi
}

ui_progress_run() {
    local i n=${#UI_PROGRESS_STEPS[@]}
    UI_PROGRESS_ACTIVE=1
    ui_clear
    printf '  %s%s%s\n' "$C_BOLD" "${UI_PROGRESS_TITLE:-SCROW}" "$C_RESET"
    _ui_rule
    _ui_blank
    UI_PROGRESS_BASE=4
    for (( i = 0; i < n; i++ )); do
        _ui_progress_inplace "$(( UI_PROGRESS_BASE + i ))" "$(_ui_progress_mark "$i")"
        [[ "$_UI_TTY_OUT" == "1" ]] && printf '\n'
    done
    _ui_blank
    _ui_rule
    UI_PROGRESS_STATUS_ROW=$(( UI_PROGRESS_BASE + n + 2 ))
    if [[ "$_UI_TTY_OUT" == "1" ]]; then
        printf '\033[%d;1H\033[K' "$UI_PROGRESS_STATUS_ROW"
    else
        printf '\n'
    fi
}

ui_progress_note() {
    local text="${1:-}"
    local content
    if [[ -n "$text" ]]; then
        content="${C_ACCENT}▸${C_RESET} ${text}"
    else
        content=""
    fi
    _ui_progress_inplace "$UI_PROGRESS_STATUS_ROW" "$content"
}

ui_progress_set() {
    local idx="$1" status="$2"
    if (( idx < 0 || idx >= ${#UI_PROGRESS_STEPS[@]} )); then
        return
    fi
    UI_PROGRESS_STATUS[$idx]="$status"
    _ui_progress_inplace "$(( UI_PROGRESS_BASE + idx ))" "$(_ui_progress_mark "$idx")"
}

ui_progress_finish() {
    UI_PROGRESS_ACTIVE=0
    if [[ "$_UI_TTY_OUT" == "1" ]]; then
        printf '\033[%d;1H\033[K\n' "$UI_PROGRESS_STATUS_ROW"
    else
        printf '\n'
    fi
}
