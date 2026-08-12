#!/usr/bin/env bash
# =============================================================================
# SCROW - terminal UI primitives
# =============================================================================
# Restrained, boxed, keyboard-driven TUI. No raw command output in the UI.
# =============================================================================

export UI_INTERACTIVE=0
[[ -t 0 ]] && UI_INTERACTIVE=1

_ui_cols() {
    local c
    c="$(tput cols 2>/dev/null)"
    [[ "$c" =~ ^[0-9]+$ ]] && echo "$c" || echo 80
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
    W=$(( _ui_cols - 2 ))
    printf '\033[2J\033[H'
    printf '%s╭' "$C_ACCENT"
    if [[ -n "$title" ]]; then
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
    W=$(( _ui_cols - 2 ))
    inner=$(( W - 2 ))
    printf '%s│ %s%s%s │%s\n' "$C_ACCENT" "$(_ui_pad_to "$inner" "$text")" "$C_RESET" "$C_ACCENT" "$C_RESET"
}

ui_box_line_raw() {
    local text="$1" hint="$2" W inner vis
    W=$(( _ui_cols - 2 ))
    inner=$(( W - 2 ))
    vis=$(_ui_vislen "$text")
    printf '%s│ %s%s%s%s%s%s%s │%s\n' "$C_ACCENT" \
        "$text" "$C_RESET" "$C_DIM" "$(_ui_pad_to "$(( inner - vis ))" "$hint")" "$C_RESET" \
        "$C_ACCENT" "$C_RESET"
}

ui_box_end() {
    local W
    W=$(( _ui_cols - 2 ))
    printf '%s╰%s╯%s\n' "$C_ACCENT" "$(printf '─%.0s' $(seq 1 $(( W - 2 ))))" "$C_RESET"
}

ui_box_blank() { ui_box_line " "; }

ui_clear() { printf '\033[2J\033[H'; }

# -----------------------------------------------------------------------------
# Status lines
# -----------------------------------------------------------------------------
ui_info() { printf '%s ›%s %s\n' "$C_ACCENT" "$C_RESET" "$1"; }
ui_ok()   { printf '%s✓%s %s\n'  "$C_OK"    "$C_RESET" "$1"; }
ui_warn() { printf '%s⚠%s %s\n'  "$C_WARN"  "$C_RESET" "$1"; }
ui_err()  { printf '%s✗%s %s\n'  "$C_ERR"   "$C_RESET" "$1"; }
ui_step() { printf '%s▸%s %s\n'  "$C_ACCENT" "$C_RESET" "$1"; }
ui_dim()  { printf '%s%s%s\n'    "$C_FAINT" "$1" "$C_RESET"; }
ui_text() { printf '%s\n' "$1"; }

ui_hr() {
    printf '%s%s%s\n' "$C_DIM" "$(printf '─%.0s' $(seq 1 $(( _ui_cols - 2 ))))" "$C_RESET"
}

# -----------------------------------------------------------------------------
# Key input
# -----------------------------------------------------------------------------
UI_KEY=""

ui_readkey() {
    UI_KEY=""
    if [[ "$UI_INTERACTIVE" != "1" ]]; then
        local line
        IFS= read -r line
        case "$line" in
            ""|"enter") UI_KEY="enter" ;;
            "y"|"Y")    UI_KEY="y" ;;
            "n"|"N")    UI_KEY="n" ;;
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
ui_confirm() {
    local msg="$1" def="${2:-y}" opts
    [[ "$def" == "y" ]] && opts="[Y/n]" || opts="[y/N]"
    printf '%s%s%s %s%s%s ' "$C_ACCENT" "$msg" "$C_RESET" "$C_DIM" "$opts" "$C_RESET"
    ui_readkey
    case "$UI_KEY" in
        "y") echo; return 0 ;;
        "n") echo; return 1 ;;
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
    local left right lw rw
    left=" ${num}  ${label} "
    lw=$(_ui_vislen "$left")
    if [[ -n "$hint" ]]; then
        rw=$(_ui_vislen " ${hint} ")
        right="$(printf '%*s' "$(( inner - lw - rw ))" "") ${hint} "
    else
        right="$(printf '%*s' "$(( inner - lw ))" "")"
    fi
    if [[ "$sel" == "1" ]]; then
        printf '%s%s%s%s%s%s%s' "${C_REV}${C_ACCENT}${C_BOLD}" "$left" "${C_DIM}" "$right" "${C_RESET}"
    else
        printf '%s%s%s%s%s' "${C_BOLD}" "$left" "${C_RESET}${C_DIM}" "$right" "${C_RESET}"
    fi
}

ui_menu() {
    local title="$1" subtitle="$2" cancel_label="${3:-Back}"
    local cur=0 total=${#UI_MENU_ITEMS[@]} key num_key
    while :; do
        _ui_menu_render "$title" "$subtitle" "$cancel_label" "$cur"
        ui_readkey
        case "$UI_KEY" in
            "up")   (( cur > 0 )) && cur=$(( cur - 1 )) ;;
            "down") (( cur < total - 1 )) && cur=$(( cur + 1 )) ;;
            "right"|"enter"|"space")
                UI_MENU_SELECTED=$cur
                return 0
                ;;
            "left"|"q"|"esc")
                UI_MENU_SELECTED=-1
                return 1
                ;;
            num*)
                num_key="${UI_KEY#num}"
                if (( num_key >= 1 && num_key <= total )); then
                    UI_MENU_SELECTED=$(( num_key - 1 ))
                    return 0
                fi
                ;;
        esac
    done
}

_ui_menu_render() {
    local title="$1" subtitle="$2" cancel_label="$3" cur="$4"
    local i label hint num W inner
    W=$(( _ui_cols - 2 ))
    inner=$(( W - 2 ))
    ui_box_begin "$title"
    if [[ -n "$subtitle" ]]; then
        ui_box_blank
        ui_box_line "${C_DIM}  $subtitle${C_RESET}"
    fi
    ui_box_blank
    for i in "${!UI_MENU_ITEMS[@]}"; do
        label="${UI_MENU_ITEMS[$i]%%::*}"
        hint=""
        [[ "${UI_MENU_ITEMS[$i]}" == *"::"* ]] && hint="${UI_MENU_ITEMS[$i]#*::}"
        num=$(( i + 1 ))
        ui_box_line "$(_ui_menu_item "$num" "$label" "$hint" "$(( i == cur ))" "$inner")"
    done
    if [[ -n "$cancel_label" ]]; then
        ui_box_blank
        ui_box_line "${C_DIM}  0  ${cancel_label}${C_RESET}"
    fi
    ui_box_blank
    ui_box_line "${C_DIM}↑↓ Navigate    Enter Select    Esc Back${C_RESET}"
    ui_box_end
}

# -----------------------------------------------------------------------------
# Checklist (custom installation)
# -----------------------------------------------------------------------------
UI_CHECK_ITEMS=()
UI_CHECK_STATE=()

ui_checklist() {
    local title="$1" subtitle="$2" cur=0 total=${#UI_CHECK_ITEMS[@]} key num_key
    [[ $total -eq 0 ]] && return 1
    while :; do
        _ui_checklist_render "$title" "$subtitle" "$cur"
        ui_readkey
        case "$UI_KEY" in
            "up")   (( cur > 0 )) && cur=$(( cur - 1 )) ;;
            "down") (( cur < total - 1 )) && cur=$(( cur + 1 )) ;;
            "space"|"right"|"enter")
                [[ "$UI_KEY" == "space" || "$UI_KEY" == "right" ]] && {
                    [[ "${UI_CHECK_STATE[$cur]}" == "1" ]] && UI_CHECK_STATE[$cur]="0" || UI_CHECK_STATE[$cur]="1"
                }
                if [[ "$UI_KEY" == "enter" ]]; then
                    return 0
                fi
                ;;
            "left"|"q"|"esc")
                return 1
                ;;
            num*)
                num_key="${UI_KEY#num}"
                if (( num_key >= 1 && num_key <= total )); then
                    local idx=$(( num_key - 1 ))
                    [[ "${UI_CHECK_STATE[$idx]}" == "1" ]] && UI_CHECK_STATE[$idx]="0" || UI_CHECK_STATE[$idx]="1"
                    cur=$idx
                fi
                ;;
        esac
    done
}

_ui_checklist_render() {
    local title="$1" subtitle="$2" cur="$3"
    local i label W inner mark line
    W=$(( _ui_cols - 2 ))
    inner=$(( W - 2 ))
    ui_box_begin "$title"
    if [[ -n "$subtitle" ]]; then
        ui_box_blank
        ui_box_line "${C_DIM}  $subtitle${C_RESET}"
    fi
    ui_box_blank
    for i in "${!UI_CHECK_ITEMS[@]}"; do
        label="${UI_CHECK_ITEMS[$i]}"
        if [[ "${UI_CHECK_STATE[$i]}" == "1" ]]; then
            mark="${C_OK}[✓]${C_RESET}"
        else
            mark="${C_DIM}[ ]${C_RESET}"
        fi
        if (( i == cur )); then
            line="${C_REV}${C_ACCENT} ${mark}  ${label}${C_RESET}"
            line+="$(printf '%*s' "$(( inner - $(_ui_vislen "$mark") - 2 - $(_ui_vislen "$label") - 2 ))" "")"
        else
            line=" ${mark}  ${label}"
            line+="$(printf '%*s' "$(( inner - $(_ui_vislen "$line") ))" "")"
        fi
        ui_box_line "$line"
    done
    ui_box_blank
    ui_box_line "${C_DIM}Space Toggle    Enter Continue    Esc Cancel${C_RESET}"
    ui_box_end
}

# -----------------------------------------------------------------------------
# Progress steps
# -----------------------------------------------------------------------------
UI_PROGRESS_TITLE=""
UI_PROGRESS_STEPS=()
UI_PROGRESS_STATUS=()

ui_progress_start() {
    UI_PROGRESS_TITLE="$1"
    UI_PROGRESS_STEPS=()
    UI_PROGRESS_STATUS=()
}

ui_progress_add() {
    UI_PROGRESS_STEPS+=("$1")
    UI_PROGRESS_STATUS+=(0)
}

ui_progress_set() {
    local idx="$1" status="$2"
    UI_PROGRESS_STATUS[$idx]="$status"
    _ui_progress_render
}

_ui_progress_render() {
    local i icon status W inner
    W=$(( _ui_cols - 2 ))
    inner=$(( W - 2 ))
    ui_box_begin "$UI_PROGRESS_TITLE"
    ui_box_blank
    for i in "${!UI_PROGRESS_STEPS[@]}"; do
        status="${UI_PROGRESS_STATUS[$i]}"
        case "$status" in
            1) icon="${C_OK}✓${C_RESET}" ;;
            2) icon="${C_ACCENT}▸${C_RESET}" ;;
            3) icon="${C_ERR}✗${C_RESET}" ;;
            4) icon="${C_WARN}⚠${C_RESET}" ;;
            *) icon="${C_DIM}○${C_RESET}" ;;
        esac
        ui_box_line "  ${icon}  ${UI_PROGRESS_STEPS[$i]}"
    done
    ui_box_blank
    ui_box_end
}

# -----------------------------------------------------------------------------
# Message / alert panel
# -----------------------------------------------------------------------------
ui_alert() {
    local kind="$1" title="$2" body="$3"
    local W inner color icon
    W=$(( _ui_cols - 2 ))
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
