#!/usr/bin/env bash
# =============================================================================
# SCROW - UI widgets
# =============================================================================
# Selection menus, checklists and dialogs. All widgets share the same
# selection language: ❯ marks the focused row, Enter activates, Esc goes
# back, and the footer always states the current key bindings.
# =============================================================================

# -----------------------------------------------------------------------------
# Selection menu
# -----------------------------------------------------------------------------
# Items (UI_MENU_ITEMS): "label", "label::hint" or "label::hint::section".
# Result: UI_MENU_SELECTED (0-based) and return 0; or -1 / return 1 on back.
UI_MENU_ITEMS=()
UI_MENU_SELECTED=-1

_ui_menu_item_meta() {
    # $1 = item; sets _M_LABEL, _M_HINT, _M_SEC
    local item="$1" rest
    _M_LABEL="${item%%::*}"
    _M_HINT=""
    _M_SEC=""
    if [[ "$item" == *"::"* ]]; then
        rest="${item#*::}"
        _M_HINT="${rest%%::*}"
        [[ "$rest" == *"::"* ]] && _M_SEC="${rest#*::}"
    fi
}

_ui_menu_row_str() {
    local num="$1" label="$2" hint="$3" sel="$4" inner left right content
    inner=$(_ui_inner)
    label="$(_ui_trunc "$label" $(( inner - 16 )))"
    hint="$(_ui_trunc "$hint" $(( inner / 3 )))"
    if [[ "$sel" == "1" ]]; then
        left="${C_ACCENT}❯${C_RESET} ${C_BOLD}${num}${C_RESET}  ${C_BOLD}${label}${C_RESET}"
    else
        left="  ${C_DIM}${num}${C_RESET}  ${label}"
    fi
    right=""
    [[ -n "$hint" ]] && right="${C_DIM}${hint}${C_RESET}"
    content="$(_ui_fill "$left" "$right" "$inner")"
    _ui_line_str "$content" "$sel"
}

# Terminal row for a menu item (1-based), so it can be redrawn in place.
_ui_menu_item_row() {
    local idx="$1" top="$2" row i prev="" sec
    row=3
    [[ -n "$UI_MENU_SUBTITLE" ]] && row=$(( row + 1 ))
    (( top > 0 )) && row=$(( row + 1 ))
    for (( i = top; i < idx; i++ )); do
        _ui_menu_item_meta "${UI_MENU_ITEMS[$i]}"
        sec="$_M_SEC"
        if [[ -n "$sec" && "$sec" != "$prev" ]]; then
            row=$(( row + 2 ))
        fi
        [[ -n "$sec" ]] && prev="$sec"
    done
    echo $(( row + idx - top ))
}

_ui_menu_redraw_item() {
    local idx="$1" top="$2" sel="$3" row
    _ui_menu_item_meta "${UI_MENU_ITEMS[$idx]}"
    row="$(_ui_menu_item_row "$idx" "$top")"
    _ui_line_at "$row" "$(_ui_menu_row_str "$(( idx + 1 ))" "$_M_LABEL" "$_M_HINT" "$sel")"
}

_ui_menu_draw() {
    local cur="$1" top="$2" item_avail="$3" cancel_label="$4"
    local i total=${#UI_MENU_ITEMS[@]} prev_sec="" sec
    ui_clear
    _ui_screen_header "$UI_MENU_TITLE" "$UI_MENU_RIGHT" "$UI_MENU_SUBTITLE"
    if (( top > 0 )); then
        printf '  %s↑ more%s\n' "$C_DIM" "$C_RESET"
    fi
    for (( i = top; i < top + item_avail && i < total; i++ )); do
        _ui_menu_item_meta "${UI_MENU_ITEMS[$i]}"
        sec="$_M_SEC"
        if [[ -n "$sec" && "$sec" != "$prev_sec" ]]; then
            _ui_blank
            _ui_section "$sec"
            prev_sec="$sec"
        fi
        [[ -n "$sec" ]] && prev_sec="$sec"
        printf '%s\n' "$(_ui_menu_row_str "$(( i + 1 ))" "$_M_LABEL" "$_M_HINT" "$(( i == cur ))" )"
    done
    if (( top + item_avail < total )); then
        printf '  %s↓ more%s\n' "$C_DIM" "$C_RESET"
    fi
    if [[ -n "$cancel_label" ]]; then
        _ui_blank
        printf '%s\n' "$(_ui_menu_row_str "0" "$cancel_label" "" 0)"
    fi
    _ui_blank
    _ui_hintbar "↑↓ Navigate    ↵ Select    esc Back"
}

ui_menu() {
    UI_MENU_TITLE="${1:-Menu}"
    UI_MENU_SUBTITLE="${2:-}"
    UI_MENU_RIGHT="${3:-}"
    local cancel_label="${4:-}"
    local cur=0 total=${#UI_MENU_ITEMS[@]} key num_key
    local cols lines item_avail top=0 attempt fixed_top fixed_bottom
    local last_cols=0 last_lines=0 last_top=0 last_cur=-1 first=1 redraw=0
    [[ $total -eq 0 ]] && return 1
    while :; do
        cols=$(_ui_cols); lines=$(_ui_rows)
        for (( attempt = 0; attempt < 2; attempt++ )); do
            fixed_top=3
            [[ -n "$UI_MENU_SUBTITLE" ]] && fixed_top=$(( fixed_top + 1 ))
            (( top > 0 )) && fixed_top=$(( fixed_top + 1 ))
            fixed_bottom=3
            [[ -n "$cancel_label" ]] && fixed_bottom=$(( fixed_bottom + 2 ))
            item_avail=$(( lines - fixed_top - fixed_bottom ))
            (( item_avail < 1 )) && item_avail=1
            (( cur < 0 )) && cur=0
            (( cur > total - 1 )) && cur=$(( total - 1 ))
            (( cur < top )) && top=$cur
            (( cur >= top + item_avail )) && top=$(( cur - item_avail + 1 ))
            (( top < 0 )) && top=0
        done

        redraw=0
        (( first )) && redraw=1
        (( cols != last_cols || lines != last_lines )) && redraw=1
        (( top != last_top )) && redraw=1
        if (( redraw )); then
            _ui_menu_draw "$cur" "$top" "$item_avail" "$cancel_label"
            last_cols=$cols; last_lines=$lines; last_top=$top; first=0
        elif (( cur != last_cur )); then
            _ui_menu_redraw_item "$last_cur" "$top" 0
            _ui_menu_redraw_item "$cur" "$top" 1
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
# Checklist
# -----------------------------------------------------------------------------
UI_CHECK_ITEMS=()
UI_CHECK_STATE=()

_ui_check_row_str() {
    local idx="$1" sel="$2" inner label mark left
    inner=$(_ui_inner)
    label="${UI_CHECK_ITEMS[$idx]}"
    label="$(_ui_trunc "$label" $(( inner - 14 )))"
    if [[ "${UI_CHECK_STATE[$idx]}" == "1" ]]; then
        mark="${C_OK}[✓]${C_RESET}"
    else
        mark="${C_DIM}[ ]${C_RESET}"
    fi
    if [[ "$sel" == "1" ]]; then
        left="${C_ACCENT}❯${C_RESET} ${C_BOLD}${mark}${C_RESET}  ${C_BOLD}${label}${C_RESET}"
    else
        left="  ${mark}  ${label}"
    fi
    _ui_line_str "$left" "$sel"
}

_ui_check_item_row() {
    local idx="$1" top="$2" row
    row=3
    [[ -n "$UI_CHECK_SUBTITLE" ]] && row=$(( row + 1 ))
    (( top > 0 )) && row=$(( row + 1 ))
    echo $(( row + idx - top ))
}

_ui_check_redraw_item() {
    local idx="$1" top="$2" sel="$3" row
    row="$(_ui_check_item_row "$idx" "$top")"
    _ui_line_at "$row" "$(_ui_check_row_str "$idx" "$sel")"
}

_ui_checklist_draw() {
    local cur="$1" top="$2" item_avail="$3"
    local i total=${#UI_CHECK_ITEMS[@]} nsel=0
    ui_clear
    _ui_screen_header "$UI_CHECK_TITLE" "$UI_CHECK_RIGHT" "$UI_CHECK_SUBTITLE"
    for i in "${!UI_CHECK_STATE[@]}"; do
        [[ "${UI_CHECK_STATE[$i]}" == "1" ]] && nsel=$(( nsel + 1 ))
    done
    if (( top > 0 )); then
        printf '  %s↑ more%s\n' "$C_DIM" "$C_RESET"
    fi
    for (( i = top; i < top + item_avail && i < total; i++ )); do
        printf '%s\n' "$(_ui_check_row_str "$i" "$(( i == cur ))" )"
    done
    if (( top + item_avail < total )); then
        printf '  %s↓ more%s\n' "$C_DIM" "$C_RESET"
    fi
    _ui_blank
    _ui_hintbar "$nsel selected — Space toggle    ↵ Continue    esc Back"
}

ui_checklist() {
    UI_CHECK_TITLE="${1:-Checklist}"
    UI_CHECK_SUBTITLE="${2:-}"
    UI_CHECK_RIGHT="${3:-}"
    local cur=0 total=${#UI_CHECK_ITEMS[@]} key num_key
    local cols lines item_avail top=0 attempt fixed_top fixed_bottom
    local last_cols=0 last_lines=0 last_top=0 last_cur=-1 first=1 redraw=0
    [[ $total -eq 0 ]] && return 1
    while :; do
        cols=$(_ui_cols); lines=$(_ui_rows)
        for (( attempt = 0; attempt < 2; attempt++ )); do
            fixed_top=3
            [[ -n "$UI_CHECK_SUBTITLE" ]] && fixed_top=$(( fixed_top + 1 ))
            (( top > 0 )) && fixed_top=$(( fixed_top + 1 ))
            fixed_bottom=3
            item_avail=$(( lines - fixed_top - fixed_bottom ))
            (( item_avail < 1 )) && item_avail=1
            (( cur < 0 )) && cur=0
            (( cur > total - 1 )) && cur=$(( total - 1 ))
            (( cur < top )) && top=$cur
            (( cur >= top + item_avail )) && top=$(( cur - item_avail + 1 ))
            (( top < 0 )) && top=0
        done

        redraw=0
        (( first )) && redraw=1
        (( cols != last_cols || lines != last_lines )) && redraw=1
        (( top != last_top )) && redraw=1
        if (( redraw )); then
            _ui_checklist_draw "$cur" "$top" "$item_avail"
            last_cols=$cols; last_lines=$lines; last_top=$top; first=0
        elif (( cur != last_cur )); then
            _ui_check_redraw_item "$last_cur" "$top" 0
            _ui_check_redraw_item "$cur" "$top" 1
        fi
        last_cur=$cur

        ui_readkey
        case "$UI_KEY" in
            "up")   (( cur > 0 )) && cur=$(( cur - 1 )) ;;
            "down") (( cur < total - 1 )) && cur=$(( cur + 1 )) ;;
            "space"|"right")
                [[ "${UI_CHECK_STATE[$cur]}" == "1" ]] && UI_CHECK_STATE[$cur]="0" || UI_CHECK_STATE[$cur]="1"
                _ui_check_redraw_item "$cur" "$top" 1
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
                        _ui_check_redraw_item "$idx" "$top" 1
                    else
                        cur=$idx
                    fi
                fi
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Dialog
# -----------------------------------------------------------------------------
# ui_dialog <kind: ok|warn|err|info> <title> <body> <button...>
# Result: UI_DIALOG_SELECTED (button index) + return 0; -1 / return 1 on Esc.
UI_DIALOG_SELECTED=-1
UI_DIALOG_FOCUS=0

_ui_dialog_meta() {
    case "$1" in
        ok)   UI_DL_COLOR="$C_OK";    UI_DL_ICON="✓" ;;
        warn) UI_DL_COLOR="$C_WARN";  UI_DL_ICON="⚠" ;;
        err)  UI_DL_COLOR="$C_ERR";   UI_DL_ICON="✗" ;;
        *)    UI_DL_COLOR="$C_ACCENT"; UI_DL_ICON="›" ;;
    esac
}

_ui_wrap() {
    local width="$1" line w cur curlen wlen
    for line in "$@"; do
        cur=""
        for w in $line; do
            if [[ -z "$cur" ]]; then
                cur="$w"
            else
                curlen=$(_ui_vislen "$cur")
                wlen=$(_ui_vislen "$w")
                if (( curlen + 1 + wlen <= width )); then
                    cur="$cur $w"
                else
                    printf '%s\n' "$cur"
                    cur="$w"
                fi
            fi
        done
        printf '%s\n' "$cur"
    done
}

_ui_dialog_draw() {
    local kind="$1" title="$2" body="$3"
    shift 3
    local -a buttons=("$@")
    local inner i b line pad total_w btn
    local -a blines=()
    inner=$(_ui_inner)
    (( inner < 24 )) && inner=24
    mapfile -t blines <<< "$body"
    ui_clear
    _ui_title_line "SCROW"
    _ui_rule
    _ui_blank
    printf '  %s%s%s  %s%s%s\n' "$UI_DL_COLOR" "$UI_DL_ICON" "$C_RESET" "$C_BOLD" "$title" "$C_RESET"
    _ui_rule
    _ui_blank
    while IFS= read -r line; do
        printf '  %s\n' "$line"
    done < <(_ui_wrap "$(( inner - 4 ))" "${blines[@]}")
    _ui_blank
    btn=""
    for i in "${!buttons[@]}"; do
        b="${buttons[$i]}"
        if (( i == UI_DIALOG_FOCUS )); then
            btn+="${C_REV} ${b} ${C_RESET}"
        else
            btn+="${C_DIM} ${b} ${C_RESET}"
        fi
        (( i < ${#buttons[@]} - 1 )) && btn+="   "
    done
    total_w=$(_ui_vislen "$btn")
    pad=$(( (inner - total_w) / 2 ))
    (( pad < 0 )) && pad=0
    printf '  %s%s\n' "$(printf '%*s' "$pad" "")" "$btn"
    _ui_blank
    _ui_hintbar "← → Switch    ↵ Select    esc Cancel"
}

ui_dialog() {
    local kind="$1" title="$2" body="$3"
    shift 3
    local -a buttons=("$@")
    local total=${#buttons[@]}
    (( total == 0 )) && return 1
    (( UI_DIALOG_FOCUS >= total )) && UI_DIALOG_FOCUS=0
    while :; do
        _ui_dialog_meta "$kind"
        _ui_dialog_draw "$kind" "$title" "$body" "${buttons[@]}"
        ui_readkey
        case "$UI_KEY" in
            left|h) (( UI_DIALOG_FOCUS > 0 )) && UI_DIALOG_FOCUS=$(( UI_DIALOG_FOCUS - 1 )) ;;
            right|l) (( UI_DIALOG_FOCUS < total - 1 )) && UI_DIALOG_FOCUS=$(( UI_DIALOG_FOCUS + 1 )) ;;
            enter|space)
                UI_DIALOG_SELECTED=$UI_DIALOG_FOCUS
                return 0
                ;;
            esc|eof|q)
                UI_DIALOG_SELECTED=-1
                return 1
                ;;
            *) ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Confirm / notice / alert
# -----------------------------------------------------------------------------
# ui_confirm <message> <default: y|n>  -> 0 yes, 1 no/esc
ui_confirm() {
    local msg="${1:-}" def="${2:-y}" saved
    if [[ "$UI_PROGRESS_ACTIVE" == "1" ]]; then
        # A prompt while the progress panel is live: keep it inline and simple.
        saved="$UI_QUIET"; UI_QUIET=0
        printf '  %s%s%s  %s[y/n]%s  ' "$C_ACCENT" "$msg" "$C_RESET" "$C_DIM" "$C_RESET"
        ui_readkey
        UI_QUIET="$saved"
        case "$UI_KEY" in
            "y") echo; return 0 ;;
            "n"|"esc"|"eof") echo; return 1 ;;
            *) echo; [[ "$def" == "y" ]] && return 0 || return 1 ;;
        esac
    fi
    UI_DIALOG_FOCUS=0
    [[ "$def" == "n" ]] && UI_DIALOG_FOCUS=1
    ui_dialog info "Confirm" "$msg" "Yes" "No" || return 1
    [[ "$UI_DIALOG_SELECTED" == "0" ]]
}

# ui_notice <kind> <title> <body>  -> single-OK dialog
ui_notice() {
    local kind="$1" title="$2" body="$3"
    UI_DIALOG_FOCUS=0
    ui_dialog "$kind" "$title" "$body" "OK"
}

# Backwards-compatible alias.
ui_alert() { ui_notice "$@"; }
