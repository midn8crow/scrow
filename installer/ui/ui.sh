#!/usr/bin/env bash
# =============================================================================
# SCROW - terminal UI primitives
# =============================================================================
# Restrained, boxed, keyboard-driven TUI. No raw command output in the UI.
# =============================================================================

export UI_INTERACTIVE=0
[[ -t 0 ]] && UI_INTERACTIVE=1

# When set, routine ui_* status lines are suppressed (used while the in-place
# progress panel is on screen). ui_confirm temporarily forces output back on.
export UI_QUIET=0

_ui_cols() {
    local c
    c="$(tput cols 2>/dev/null)"
    [[ "$c" =~ ^[0-9]+$ ]] && echo "$c" || echo 80
}

_ui_rows() {
    local r
    r="$(tput lines 2>/dev/null)"
    [[ "$r" =~ ^[0-9]+$ ]] && echo "$r" || echo 24
}

# Truncate a string to at most $2 visible characters, adding an ellipsis.
_ui_trunc() {
    local text="$1" max="$2" vis
    (( max < 0 )) && max=0
    vis=$(_ui_vislen "$text")
    (( vis <= max )) && { printf '%s' "$text"; return; }
    (( max > 0 )) || return 0
    printf '%s' "${text:0:$(( max - 1 ))}…"
}

_ui_vislen() {
    printf '%s' "$1" | sed $'s/\033\[[0-9;]*m//g' | awk '{ print length }'
}

_ui_pad_to() {
    local target="$1" text="$2" vis
    vis="$(_ui_vislen "$text")"
    if (( vis >= target )); then
        printf '%s' "$text"
        return
    fi
    printf '%s%*s' "$text" "$(( target - vis ))" ""
}

_ui_center_text() {
    local text="$1" width="$2" vis pad
    vis="$(_ui_vislen "$text")"
    (( vis >= width )) && { printf '%s' "$text"; return; }
    pad=$(( (width - vis) / 2 ))
    printf '%*s%s%*s' "$pad" "" "$text" "$(( width - vis - pad ))" ""
}

# -----------------------------------------------------------------------------
# Panels
# -----------------------------------------------------------------------------
ui_box_begin() {
    local title="${1:-}" W rem
    W=$(( $(_ui_cols) - 2 ))
    (( W < 4 )) && W=4
    printf '\033[2J\033[H'
    printf '%s╭' "$C_ACCENT"
    if [[ -n "$title" ]]; then
        title="$(_ui_trunc "$title" $(( W - 4 )))"
        printf '─ %s%s%s' "$C_BOLD" "$title" "$C_ACCENT"
        rem=$(( W - 3 - $(_ui_vislen "$title") ))
        (( rem > 0 )) && printf '─%.0s' $(seq 1 "$rem")
    else
        printf '─%.0s' $(seq 1 "$(( W - 2 ))")
    fi
    printf '╮%s\n' "$C_RESET"
}

ui_box_line() {
    local text="$1" W inner
    W=$(( $(_ui_cols) - 2 ))
    (( W < 4 )) && W=4
    inner=$(( W - 2 ))
    printf '%s│ %s%s%s │%s\n' "$C_ACCENT" "$(_ui_pad_to "$inner" "$text")" "$C_RESET" "$C_ACCENT" "$C_RESET"
}

ui_box_line_raw() {
    local text="$1" hint="$2" W inner vis
    W=$(( $(_ui_cols) - 2 ))
    (( W < 4 )) && W=4
    inner=$(( W - 2 ))
    vis=$(_ui_vislen "$text")
    printf '%s│ %s%s%s%s%s%s%s │%s\n' "$C_ACCENT" \
        "$text" "$C_RESET" "$C_DIM" "$(_ui_pad_to "$(( inner - vis ))" "$hint")" "$C_RESET" \
        "$C_ACCENT" "$C_RESET"
}

ui_box_end() {
    local W
    W=$(( $(_ui_cols) - 2 ))
    (( W < 4 )) && W=4
    printf '%s╰%s╯%s\n' "$C_ACCENT" "$(printf '─%.0s' $(seq 1 $(( W - 2 ))))" "$C_RESET"
}

ui_box_blank() { ui_box_line " "; }

ui_clear() { printf '\033[2J\033[H'; }

# -----------------------------------------------------------------------------
# Status lines
# -----------------------------------------------------------------------------
ui_info() { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s ›%s %s\n' "$C_ACCENT" "$C_RESET" "$1"; }
ui_ok()   { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s✓%s %s\n'  "$C_OK"    "$C_RESET" "$1"; }
ui_warn() { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s⚠%s %s\n'  "$C_WARN"  "$C_RESET" "$1"; }
ui_err()  { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s✗%s %s\n'  "$C_ERR"   "$C_RESET" "$1"; }
ui_step() { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s▸%s %s\n'  "$C_ACCENT" "$C_RESET" "$1"; }
ui_dim()  { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s%s%s\n'    "$C_FAINT" "$1" "$C_RESET"; }
ui_text() { [[ "$UI_QUIET" == "1" ]] && return 0; printf '%s\n' "$1"; }
ui_error() { ui_err "$1"; }

ui_hr() {
    printf '%s%s%s\n' "$C_DIM" "$(printf '─%.0s' $(seq 1 $(( $(_ui_cols) - 2 ))))" "$C_RESET"
}

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
            ""|"enter") UI_KEY="enter" ;;
            "y"|"Y")    UI_KEY="y" ;;
            "n"|"N")    UI_KEY="n" ;;
            [0-9])      UI_KEY="num$line" ;;
            *)          UI_KEY="enter" ;;
        esac
        return
    fi
    local key rest
    IFS= read -r -s -n1 key 2>/dev/null
    case "$key" in
        $'\033')
            IFS= read -r -s -n2 -t 0.05 rest 2>/dev/null
            case "$rest" in
                "[A"|"OA") UI_KEY="up" ;;
                "[B"|"OB") UI_KEY="down" ;;
                "[C"|"OC") UI_KEY="right" ;;
                "[D"|"OD") UI_KEY="left" ;;
                *) UI_KEY="esc" ;;
            esac
            ;;
        $'\n'|$'\r'|"") UI_KEY="enter" ;;
        " ") UI_KEY="space" ;;
        $'\t') UI_KEY="tab" ;;
        "q"|"Q") UI_KEY="q" ;;
        "k"|"K") UI_KEY="up" ;;
        "j"|"J") UI_KEY="down" ;;
        "l"|"L") UI_KEY="right" ;;
        "h"|"H") UI_KEY="left" ;;
        "y"|"Y") UI_KEY="y" ;;
        "n"|"N") UI_KEY="n" ;;
        "1"|"2"|"3"|"4"|"5"|"6"|"7"|"8"|"9") UI_KEY="num$key" ;;
        *) UI_KEY="$key" ;;
    esac
}

ui_pause() {
    printf '%s%s  [Enter] to continue%s\n' "$C_DIM" "${1:-Press}" "$C_RESET"
    ui_readkey
}

# -----------------------------------------------------------------------------
# Confirmation prompt
# -----------------------------------------------------------------------------
# ui_confirm <message> <default: y|n>  -> 0 yes, 1 no
# The default is shown as an explicit tag: "[Y/n]  (default: Yes)" so the
# keyboard shortcut is never ambiguous.
ui_confirm() {
    local msg="${1:-}" def="${2:-y}" opts tag
    local saved="$UI_QUIET"; UI_QUIET=0
    if [[ "$def" == "y" ]]; then
        opts="[Y/n]"
        tag="default: Yes"
    else
        opts="[y/N]"
        tag="default: No"
    fi
    printf '%s%s%s %s%s%s  %s%s%s ' "$C_ACCENT" "$msg" "$C_RESET" "$C_DIM" "$opts" "$C_RESET" "$C_FAINT" "$tag" "$C_RESET"
    ui_readkey
    UI_QUIET="$saved"
    case "$UI_KEY" in
        "y") echo; return 0 ;;
        "n") echo; return 1 ;;
        "eof") echo; return 1 ;;
        *)   echo; [[ "$def" == "y" ]]; return ;;
    esac
}

# -----------------------------------------------------------------------------
# Selection menu
# -----------------------------------------------------------------------------
# Items: UI_MENU_ITEMS=( "label::hint" ... ). Selected index -> UI_MENU_SELECTED
# (0-based), or -1 when cancelled.
UI_MENU_ITEMS=()
UI_MENU_SELECTED=-1

_ui_menu_item() {
    local num="$1" label="$2" hint="$3" sel="$4" inner="$5"
    local left right lw_base avail rw hint_w
    lw_base=$(_ui_vislen " ${num}  ")
    avail=$(( inner - lw_base ))
    if [[ -n "$hint" ]]; then
        label="$(_ui_trunc "$label" $(( avail - 8 )))"
        hint_w=$(( avail - $(_ui_vislen " ${label} ") - 2 ))
        (( hint_w < 0 )) && hint_w=0
        hint="$(_ui_trunc "$hint" "$hint_w")"
    else
        label="$(_ui_trunc "$label" "$avail")"
    fi
    left=" ${num}  ${label} "
    if [[ -n "$hint" ]]; then
        rw=$(_ui_vislen " ${hint} ")
        right="$(printf '%*s' "$(( inner - $(_ui_vislen "$left") - rw ))" "") ${hint} "
    else
        right="$(printf '%*s' "$(( inner - $(_ui_vislen "$left") ))" "")"
    fi
    if [[ "$sel" == "1" ]]; then
        printf '%s%s%s%s%s%s%s' "${C_REV}${C_ACCENT}${C_BOLD}" "$left" "${C_DIM}" "$right" "${C_RESET}"
    else
        printf '%s%s%s%s%s' "${C_BOLD}" "$left" "${C_RESET}${C_DIM}" "$right" "${C_RESET}"
    fi
}

# Boxed line content (no trailing newline), padded to the box inner width.
_ui_box_line_str() {
    local text="$1" inner
    inner=$(( $(_ui_cols) - 4 ))
    (( inner < 2 )) && inner=2
    printf '%s│ %s%s%s │%s' "$C_ACCENT" "$(_ui_pad_to "$inner" "$text")" "$C_RESET" "$C_ACCENT" "$C_RESET"
}

# Rewrite a single terminal line in place (row is 1-based).
_ui_line_at() {
    printf '\033[%d;1H\033[K' "$1"
    printf '%s' "$2"
}

_ui_menu_item_row() {
    local idx="$1" subtitle="$2" top="$3" base=1
    [[ -n "$subtitle" ]] && base=$(( base + 2 ))
    echo $(( base + 2 + idx - top ))
}

_ui_menu_redraw_item() {
    local idx="$1" subtitle="$2" top="$3" inner="$4" sel="$5"
    local row label hint
    row="$(_ui_menu_item_row "$idx" "$subtitle" "$top")"
    label="${UI_MENU_ITEMS[$idx]%%::*}"
    hint=""
    [[ "${UI_MENU_ITEMS[$idx]}" == *"::"* ]] && hint="${UI_MENU_ITEMS[$idx]#*::}"
    _ui_line_at "$row" "$(_ui_box_line_str "$(_ui_menu_item "$(( idx + 1 ))" "$label" "$hint" "$sel" "$inner")")"
}

_ui_menu_draw() {
    local title="$1" subtitle="$2" cancel_label="$3" cur="$4" top="$5" inner="$6" item_avail="$7"
    local i total=${#UI_MENU_ITEMS[@]}
    ui_box_begin "$title"
    if [[ -n "$subtitle" ]]; then
        ui_box_blank
        ui_box_line "${C_DIM}  $subtitle${C_RESET}"
    fi
    if (( top > 0 )); then
        ui_box_line "${C_DIM}  ↑ more${C_RESET}"
    else
        ui_box_blank
    fi
    for (( i = top; i < top + item_avail && i < total; i++ )); do
        local label hint
        label="${UI_MENU_ITEMS[$i]%%::*}"
        hint=""
        [[ "${UI_MENU_ITEMS[$i]}" == *"::"* ]] && hint="${UI_MENU_ITEMS[$i]#*::}"
        ui_box_line "$(_ui_menu_item "$(( i + 1 ))" "$label" "$hint" "$(( i == cur ))" "$inner")"
    done
    if (( top + item_avail < total )); then
        ui_box_line "${C_DIM}  ↓ more${C_RESET}"
    else
        ui_box_blank
    fi
    if [[ -n "$cancel_label" ]]; then
        ui_box_line "${C_DIM}  0  ${cancel_label}${C_RESET}"
    fi
    ui_box_blank
    ui_box_line "${C_DIM}↑↓ Navigate    Enter Select    Esc Back${C_RESET}"
    ui_box_end
}

ui_menu() {
    local title="$1" subtitle="${2:-}" cancel_label="${3-Back}"
    local cur=0 total=${#UI_MENU_ITEMS[@]} key num_key
    local cols lines inner fixed item_avail top=0
    local last_cols=0 last_lines=0 last_top=0 last_cur=-1 first=1 redraw=0
    [[ $total -eq 0 ]] && return 1
    while :; do
        cols=$(_ui_cols); lines=$(_ui_rows)
        inner=$(( cols - 4 ))
        (( inner < 4 )) && inner=4
        fixed=1
        [[ -n "$subtitle" ]] && fixed=$(( fixed + 2 ))
        fixed=$(( fixed + 2 ))
        [[ -n "$cancel_label" ]] && fixed=$(( fixed + 1 ))
        fixed=$(( fixed + 3 ))
        item_avail=$(( lines - fixed ))
        (( item_avail < 1 )) && item_avail=1
        (( cur < 0 )) && cur=0
        (( cur > total - 1 )) && cur=$(( total - 1 ))
        (( cur < top )) && top=$cur
        (( cur >= top + item_avail )) && top=$(( cur - item_avail + 1 ))
        (( top < 0 )) && top=0

        redraw=0
        (( first )) && redraw=1
        (( cols != last_cols || lines != last_lines )) && redraw=1
        (( top != last_top )) && redraw=1
        if (( redraw )); then
            _ui_menu_draw "$title" "$subtitle" "$cancel_label" "$cur" "$top" "$inner" "$item_avail"
            last_cols=$cols; last_lines=$lines; last_top=$top; first=0
        elif (( cur != last_cur )); then
            _ui_menu_redraw_item "$last_cur" "$subtitle" "$top" "$inner" 0
            _ui_menu_redraw_item "$cur" "$subtitle" "$top" "$inner" 1
        fi
        last_cur=$cur

        ui_readkey
        case "$UI_KEY" in
            "up")   (( cur > 0 )) && cur=$(( cur - 1 )) ;;
            "down") (( cur < total - 1 )) && cur=$(( cur + 1 )) ;;
            "right"|"enter"|"space")
                UI_MENU_SELECTED=$cur
                return 0
                ;;
            "left"|"q"|"esc"|"eof")
                UI_MENU_SELECTED=-1
                return 1
                ;;
            num*)
                num_key="${UI_KEY#num}"
                if (( num_key >= 1 && num_key <= total )); then
                    cur=$(( num_key - 1 ))
                fi
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Checklist (custom installation)
# -----------------------------------------------------------------------------
UI_CHECK_ITEMS=()
UI_CHECK_STATE=()

_ui_check_item_row() {
    local idx="$1" subtitle="$2" top="$3" base=1
    [[ -n "$subtitle" ]] && base=$(( base + 2 ))
    echo $(( base + 2 + idx - top ))
}

_ui_checklist_line() {
    local i="$1" sel="$2" inner="$3"
    local label="${UI_CHECK_ITEMS[$i]}" mark line
    label="$(_ui_trunc "$label" $(( inner - 8 )))"
    if [[ "${UI_CHECK_STATE[$i]}" == "1" ]]; then
        mark="${C_OK}[✓]${C_RESET}"
    else
        mark="${C_DIM}[ ]${C_RESET}"
    fi
    if [[ "$sel" == "1" ]]; then
        line="${C_REV}${C_ACCENT} ${mark}  ${label}${C_RESET}"
        line+="$(printf '%*s' "$(( inner - $(_ui_vislen "$line") ))" "")"
    else
        line=" ${mark}  ${label}"
        line+="$(printf '%*s' "$(( inner - $(_ui_vislen "$line") ))" "")"
    fi
    printf '%s' "$line"
}

_ui_check_redraw_item() {
    local idx="$1" subtitle="$2" top="$3" inner="$4" sel="$5" row
    row="$(_ui_check_item_row "$idx" "$subtitle" "$top")"
    _ui_line_at "$row" "$(_ui_box_line_str "$(_ui_checklist_line "$idx" "$sel" "$inner")")"
}

_ui_checklist_draw() {
    local title="$1" subtitle="$2" cur="$3" top="$4" inner="$5" item_avail="$6"
    local i total=${#UI_CHECK_ITEMS[@]}
    ui_box_begin "$title"
    if [[ -n "$subtitle" ]]; then
        ui_box_blank
        ui_box_line "${C_DIM}  $subtitle${C_RESET}"
    fi
    if (( top > 0 )); then
        ui_box_line "${C_DIM}  ↑ more${C_RESET}"
    else
        ui_box_blank
    fi
    for (( i = top; i < top + item_avail && i < total; i++ )); do
        ui_box_line "$(_ui_checklist_line "$i" "$(( i == cur ))" "$inner")"
    done
    if (( top + item_avail < total )); then
        ui_box_line "${C_DIM}  ↓ more${C_RESET}"
    else
        ui_box_blank
    fi
    ui_box_blank
    ui_box_line "${C_DIM}Space Toggle    Enter Continue    Esc Cancel${C_RESET}"
    ui_box_end
}

ui_checklist() {
    local title="$1" subtitle="${2:-}" cur=0 total=${#UI_CHECK_ITEMS[@]} key num_key
    local cols lines inner fixed item_avail top=0
    local last_cols=0 last_lines=0 last_top=0 last_cur=-1 first=1 redraw=0
    [[ $total -eq 0 ]] && return 1
    while :; do
        cols=$(_ui_cols); lines=$(_ui_rows)
        inner=$(( cols - 4 ))
        (( inner < 4 )) && inner=4
        fixed=1
        [[ -n "$subtitle" ]] && fixed=$(( fixed + 2 ))
        fixed=$(( fixed + 5 ))
        item_avail=$(( lines - fixed ))
        (( item_avail < 1 )) && item_avail=1
        (( cur < 0 )) && cur=0
        (( cur > total - 1 )) && cur=$(( total - 1 ))
        (( cur < top )) && top=$cur
        (( cur >= top + item_avail )) && top=$(( cur - item_avail + 1 ))
        (( top < 0 )) && top=0

        redraw=0
        (( first )) && redraw=1
        (( cols != last_cols || lines != last_lines )) && redraw=1
        (( top != last_top )) && redraw=1
        if (( redraw )); then
            _ui_checklist_draw "$title" "$subtitle" "$cur" "$top" "$inner" "$item_avail"
            last_cols=$cols; last_lines=$lines; last_top=$top; first=0
        elif (( cur != last_cur )); then
            _ui_check_redraw_item "$last_cur" "$subtitle" "$top" "$inner" 0
            _ui_check_redraw_item "$cur" "$subtitle" "$top" "$inner" 1
        fi
        last_cur=$cur

        ui_readkey
        case "$UI_KEY" in
            "up")   (( cur > 0 )) && cur=$(( cur - 1 )) ;;
            "down") (( cur < total - 1 )) && cur=$(( cur + 1 )) ;;
            "space"|"right")
                [[ "${UI_CHECK_STATE[$cur]}" == "1" ]] && UI_CHECK_STATE[$cur]="0" || UI_CHECK_STATE[$cur]="1"
                _ui_check_redraw_item "$cur" "$subtitle" "$top" "$inner" 1
                ;;
            "enter")
                return 0
                ;;
            "left"|"q"|"esc"|"eof")
                return 1
                ;;
            num*)
                num_key="${UI_KEY#num}"
                if (( num_key >= 1 && num_key <= total )); then
                    local idx=$(( num_key - 1 ))
                    [[ "${UI_CHECK_STATE[$idx]}" == "1" ]] && UI_CHECK_STATE[$idx]="0" || UI_CHECK_STATE[$idx]="1"
                    if (( idx == cur )); then
                        _ui_check_redraw_item "$idx" "$subtitle" "$top" "$inner" 1
                    fi
                    cur=$idx
                fi
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Progress panel (in-place, no flicker)
# -----------------------------------------------------------------------------
# Usage:
#   ui_progress_start "Installing SCROW"
#   ui_progress_add "Checking system"
#   ui_progress_run
#   ui_progress_set 0 2     # 0=pending 1=ok 2=running 3=error 4=warn
#   ui_progress_finish
# -----------------------------------------------------------------------------
UI_PROGRESS_TITLE=""
UI_PROGRESS_STEPS=()
UI_PROGRESS_STATUS=()
UI_PROGRESS_ACTIVE=0

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

ui_progress_run() {
    local i
    UI_PROGRESS_ACTIVE=1
    ui_clear
    printf '%s SCROW%s %s%s\n' "$C_BOLD" "$C_RESET" "${C_BOLD}${UI_PROGRESS_TITLE}${C_RESET}"
    printf '%s%s%s\n' "$C_DIM" "$(printf '─%.0s' $(seq 1 $(( $(_ui_cols) - 2 ))))" "$C_RESET"
    for i in "${!UI_PROGRESS_STEPS[@]}"; do
        printf '  %s○%s %s%s\n' "$C_DIM" "$C_RESET" "${UI_PROGRESS_STEPS[$i]}" "$C_RESET"
    done
}

ui_progress_set() {
    local idx="$1" status="$2"
    UI_PROGRESS_STATUS[$idx]="$status"
    _ui_progress_update "$idx"
}

_ui_progress_update() {
    local idx="$1" total="${#UI_PROGRESS_STEPS[@]}" icon color up
    icon="$(_ui_progress_icon "${UI_PROGRESS_STATUS[$idx]}")"
    color="$(_ui_progress_color "${UI_PROGRESS_STATUS[$idx]}")"
    if [[ "$UI_INTERACTIVE" == "1" ]] && command -v tput >/dev/null 2>&1; then
        up=$(( total - idx ))
        (( up > 0 )) && tput cuu "$up"
        printf '\r\033[2K  %s%s%s %s%s' "$color" "$icon" "$C_RESET" "${UI_PROGRESS_STEPS[$idx]}" "$C_RESET"
        (( up > 0 )) && tput cud "$up"
        printf '\r'
    else
        printf '  %s%s%s %s%s\n' "$color" "$icon" "$C_RESET" "${UI_PROGRESS_STEPS[$idx]}" "$C_RESET"
    fi
}

ui_progress_finish() {
    printf '\n'
    UI_PROGRESS_ACTIVE=0
}

# -----------------------------------------------------------------------------
# Message / alert panel
# -----------------------------------------------------------------------------
ui_alert() {
    local kind="$1" title="$2" body="$3"
    local W inner color icon
    W=$(( $(_ui_cols) - 2 ))
    inner=$(( W - 2 ))
    case "$kind" in
        ok)   color="$C_OK";   icon="✓" ;;
        warn) color="$C_WARN"; icon="⚠" ;;
        err)  color="$C_ERR";  icon="✗" ;;
        *)    color="$C_ACCENT"; icon="›" ;;
    esac
    ui_box_begin "${color}${icon} ${title}${C_ACCENT}"
    ui_box_blank
    while IFS= read -r line; do
        ui_box_line "$line"
    done <<< "$body"
    ui_box_blank
    ui_box_end
}
