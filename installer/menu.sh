#!/usr/bin/env bash
# =============================================================================
# SCROW — interactive manager (keyboard-driven TUI)
# =============================================================================
# Thin presentation layer over the SCROW engine. All navigation reads only
# in-memory state (components table, install state) — no git, curl, pacman,
# paru or systemctl while moving through menus. Operations leave the TUI,
# run against the real terminal, then return to a result screen.

SCROW_TUI_ROWS=24
SCROW_TUI_COLS=80
SCROW_TUI_KEY=""
SCROW_TUI_RESIZED=0
SCROW_TUI_SIZE_SET=0

# -----------------------------------------------------------------------------
# Terminal
# -----------------------------------------------------------------------------
# Terminal dimensions are probed only when the TUI starts and on SIGWINCH.
# scrow_ui_size() is a no-op otherwise (navigation never forks a subprocess).
scrow_ui_size() {
    (( SCROW_TUI_SIZE_SET == 1 && SCROW_TUI_RESIZED == 0 )) && return
    SCROW_TUI_SIZE_SET=1
    SCROW_TUI_RESIZED=0
    local sz rows cols
    SCROW_TUI_ROWS=24; SCROW_TUI_COLS=80
    if sz="$(stty size 2>/dev/null </dev/tty)" && [[ -n "$sz" ]]; then
        rows="${sz%% *}"; cols="${sz##* }"
        [[ "$rows" =~ ^[0-9]+$ && "$cols" =~ ^[0-9]+$ ]] && { SCROW_TUI_ROWS=$rows; SCROW_TUI_COLS=$cols; }
    fi
    (( SCROW_TUI_ROWS < 5 )) && SCROW_TUI_ROWS=5
    (( SCROW_TUI_COLS < 20 )) && SCROW_TUI_COLS=20
}

scrow_ui_enter() {
    trap 'SCROW_TUI_RESIZED=1' WINCH
    SCROW_TUI_RESIZED=1
    printf '\033[?1049h\033[?25l'
    scrow_ui_size
}

scrow_ui_leave() {
    trap - WINCH
    printf '\033[?25h\033[?1049l'
}

scrow_ui_key() {
    SCROW_TUI_KEY=""
    local c rest
    if ! IFS= read -rsn1 c; then
        if [[ "${SCROW_TUI_RESIZED:-0}" == "1" ]]; then
            SCROW_TUI_KEY="none"
        else
            SCROW_TUI_KEY="eof"
        fi
        return
    fi
    if [[ "$c" == $'\033' ]]; then
        IFS= read -rsn2 -t 0.1 rest
        case "$rest" in
            '[A') SCROW_TUI_KEY=up ;;
            '[B') SCROW_TUI_KEY=down ;;
            '[C') SCROW_TUI_KEY=right ;;
            '[D') SCROW_TUI_KEY=left ;;
            '[H') SCROW_TUI_KEY=home ;;
            '[F') SCROW_TUI_KEY=end ;;
            *)    SCROW_TUI_KEY=esc ;;
        esac
        return
    fi
    case "$c" in
        $'\r'|$'\n'|'') SCROW_TUI_KEY=enter ;;
        ' ')         SCROW_TUI_KEY=space ;;
        q|Q)         SCROW_TUI_KEY=q ;;
        *)           SCROW_TUI_KEY="$c" ;;
    esac
}

# -----------------------------------------------------------------------------
# Canvas
# -----------------------------------------------------------------------------
declare -a SCROW_TUI_FRAME=()

scrow_ui_frame() {
    scrow_ui_size
    SCROW_TUI_FRAME=()
    local -i y
    for ((y=0; y<SCROW_TUI_ROWS; y++)); do SCROW_TUI_FRAME+=(""); done
}

scrow_ui_put() {
    local -i y=$1
    local text="$2"
    (( y >= 0 && y < SCROW_TUI_ROWS )) || return 0
    scrow_ui_clip "$text"
    SCROW_TUI_FRAME[y]="$SCROW_TUI_CLIPPED"
}

SCROW_TUI_CLIPPED=""
scrow_ui_clip() {
    local text="$1" ch
    scrow_ui_vislen "$text"
    if (( scrow_ui_vislen_out <= SCROW_TUI_COLS )); then
        SCROW_TUI_CLIPPED="$text"
        return
    fi
    local -i i=0 n=${#text} vis=0
    SCROW_TUI_CLIPPED=""
    while (( i < n )); do
        ch="${text:i:1}"
        if [[ "$ch" == $'\033' ]]; then
            SCROW_TUI_CLIPPED+="$ch"
            (( i++ ))
            while (( i < n )) && [[ "${text:i:1}" != "m" ]]; do
                SCROW_TUI_CLIPPED+="${text:i:1}"
                (( i++ ))
            done
            if (( i < n )); then
                SCROW_TUI_CLIPPED+="m"
                (( i++ ))
            fi
            continue
        fi
        (( vis >= SCROW_TUI_COLS )) && break
        SCROW_TUI_CLIPPED+="$ch"
        vis+=1
        (( i++ ))
    done
}

scrow_ui_spaces() { printf -v scrow_ui_spaces_out '%*s' "$1" ""; }

scrow_ui_hline() {
    local -i y=$1
    local color="${2:-$C_HAIR}"
    (( y >= 0 && y < SCROW_TUI_ROWS )) || return 0
    printf -v scrow_ui_hline_line '%*s' "$SCROW_TUI_COLS" ""
    scrow_ui_put "$y" "${color}${scrow_ui_hline_line// /─}${C_RESET}"
}

scrow_ui_dash() {
    local -i n=$1
    printf -v scrow_ui_dash_line '%*s' "$n" ""
    printf '%s' "${scrow_ui_dash_line// /─}"
}

scrow_ui_center_in() {
    local -i x0=$1 x1=$2
    local text="$3"
    local -i w=$(( x1 - x0 + 1 ))
    scrow_ui_vislen "$text"
    local -i len=$scrow_ui_vislen_out
    local -i pad=$(( (w - len) / 2 ))
    (( pad < 0 )) && pad=0
    scrow_ui_spaces $(( x0 + pad ))
    printf '%s%s' "$scrow_ui_spaces_out" "$text"
}

scrow_ui_render() {
    scrow_ui_size
    printf '\033[H'
    local -i y
    local s
    for ((y=0; y<SCROW_TUI_ROWS-1; y++)); do
        s="${SCROW_TUI_FRAME[y]:-}"
        printf '%s\033[K\r\n' "$s"
    done
    printf '%s\033[K\033[H' "${SCROW_TUI_FRAME[SCROW_TUI_ROWS-1]:-}"
}

scrow_ui_vislen() {
    local s="$1" t="$1" pre=""
    local -i vis=0
    while [[ "$t" == *$'\033['* ]]; do
        pre="${t%%$'\033['*}"
        vis+="${#pre}"
        t="${t#*$'\033['}"
        t="${t#*m}"
    done
    vis+="${#t}"
    printf -v scrow_ui_vislen_out '%d' "$vis"
}

scrow_ui_center_p() {
    local text="$1"
    local -i plen=${2:-0}
    (( plen == 0 )) && { scrow_ui_vislen "$text"; plen=$scrow_ui_vislen_out; }
    local -i pad=$(( (SCROW_TUI_COLS - plen) / 2 ))
    (( pad < 0 )) && pad=0
    scrow_ui_spaces "$pad"
    printf -v scrow_ui_center_p_out '%s%s' "$scrow_ui_spaces_out" "$text"
}

declare -a SCROW_TUI_WRAPPED=()
scrow_ui_wrap() {
    local text="$1" maxlen=$2 word out=""
    SCROW_TUI_WRAPPED=()
    for word in $text; do
        if [[ -z "$out" ]]; then
            out="$word"
        else
            scrow_ui_vislen "$out"
            local -i wl=$scrow_ui_vislen_out
            scrow_ui_vislen "$word"
            if (( wl + 1 + scrow_ui_vislen_out <= maxlen )); then
                out="$out $word"
            else
                SCROW_TUI_WRAPPED+=("$out")
                out="$word"
            fi
        fi
    done
    [[ -n "$out" ]] && SCROW_TUI_WRAPPED+=("$out")
}

# -----------------------------------------------------------------------------
# Buttons / dialogs
# -----------------------------------------------------------------------------
scrow_ui_buttons() {
    local -i y=$1 sel=$2
    shift 2
    local -a labs=("$@")
    local -i n=${#labs[@]} total=0 i gap=2
    for ((i=0; i<n; i++)); do total+=$(( ${#labs[i]} + 2 )); done
    (( n > 1 )) && total+=$(( gap * (n - 1) ))
    # Adapt spacing to the terminal width: shrink gaps, then padding, then labels.
    while (( total > SCROW_TUI_COLS && gap > 1 )); do
        gap=$(( gap - 1 ))
        total=$(( total - (n - 1) ))
    done
    if (( total > SCROW_TUI_COLS )); then
        total=$(( total - 2 * n ))
        for ((i=0; i<n; i++)); do total+=$(( ${#labs[i]} )); done
    fi
    local -i pad=$(( (SCROW_TUI_COLS - total) / 2 ))
    (( pad < 0 )) && pad=0
    local row
    scrow_ui_spaces "$pad"
    row="$scrow_ui_spaces_out"
    local content
    for ((i=0; i<n; i++)); do
        if (( total > SCROW_TUI_COLS )); then
            content="${labs[i]}"
        else
            content=" ${labs[i]} "
        fi
        if (( i == sel )); then
            row+="${C_BTN_BG}${C_BTN_FG}${content}${C_RESET}"
        else
            row+="${C_DIM}${content}${C_RESET}"
        fi
        if (( i < n - 1 )); then scrow_ui_spaces "$gap"; row+="$scrow_ui_spaces_out"; fi
    done
    scrow_ui_put "$y" "$row"
}

scrow_ui_confirm() {
    local title="$1" ok="$2" no="$3" danger=$4
    shift 4
    local -a msg=("$@")
    local -i sel=0
    (( danger == 1 )) && sel=1
    local -i y
    local line w
    while true; do
        scrow_ui_frame
        scrow_ui_put 2 "  ${C_WARN}${C_BOLD}!  ${title}${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=5
        for line in "${msg[@]}"; do
            scrow_ui_wrap "$line" $((SCROW_TUI_COLS - 8))
            for w in "${SCROW_TUI_WRAPPED[@]}"; do
                (( y < SCROW_TUI_ROWS - 7 )) || break
                scrow_ui_put "$y" "  ${C_DIM}${w}${C_RESET}"
                y+=1
            done
            (( y >= SCROW_TUI_ROWS - 7 )) && break
        done
        scrow_ui_buttons $((SCROW_TUI_ROWS - 4)) $sel "$ok" "$no"
        scrow_ui_center_p "${C_HAIR}← → choose · Enter confirm · Esc cancel${C_RESET}"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            left|right)  sel=$(( 1 - sel )) ;;
            enter)       return $sel ;;
            esc|q|eof|none) return 2 ;;
        esac
    done
}

scrow_ui_result() {
    local title="$1" status="$2"
    shift 2
    local logfile=""
    if [[ "${1:-}" == "--log" ]]; then logfile="${2:-}"; shift 2; fi
    local -a msg=("$@")
    local color="$C_OK" icon="✓"
    case "$status" in
        warn) color="$C_WARN"; icon="!" ;;
        err)  color="$C_ERR";  icon="✗" ;;
    esac
    local -a labs=("Continue")
    [[ -n "$logfile" ]] && labs+=("View Log")
    local -i sel=0
    local -i y
    local line w
    while true; do
        scrow_ui_frame
        scrow_ui_put 2 "  ${color}${C_BOLD}${icon}  ${title}${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=5
        for line in "${msg[@]}"; do
            scrow_ui_wrap "$line" $((SCROW_TUI_COLS - 8))
            for w in "${SCROW_TUI_WRAPPED[@]}"; do
                (( y < SCROW_TUI_ROWS - 7 )) || break
                scrow_ui_put "$y" "  ${C_DIM}${w}${C_RESET}"
                y+=1
            done
            (( y >= SCROW_TUI_ROWS - 7 )) && break
        done
        scrow_ui_buttons $((SCROW_TUI_ROWS - 4)) $sel "${labs[@]}"
        local footer
        if (( ${#labs[@]} > 1 )); then
            footer="${C_HAIR}← → choose · Enter confirm · Esc back${C_RESET}"
        else
            footer="${C_HAIR}Enter continue · Esc back${C_RESET}"
        fi
        scrow_ui_center_p "$footer"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            left|right)
                sel=$(( 1 - sel ))
                (( sel > ${#labs[@]} - 1 )) && sel=$(( ${#labs[@]} - 1 ))
                ;;
            enter)
                if (( sel == 1 && ${#labs[@]} > 1 )); then
                    scrow_ui_pager "$logfile"
                else
                    return 0
                fi
                ;;
            esc|q|eof|none) return 1 ;;
        esac
    done
}

scrow_ui_pager() {
    local file="$1"
    local -a lines=()
    local line
    if [[ -f "$file" ]]; then
        while IFS= read -r line; do
            lines+=("$line")
        done < <(tail -n 500 "$file" 2>/dev/null)
    fi
    [[ ${#lines[@]} -eq 0 ]] && lines+=("(log is empty or unavailable)")
    local -i cur=0 top=0
    local -i h=$(( SCROW_TUI_ROWS - 6 ))
    (( h < 1 )) && h=1
    local -i i y
    while true; do
        scrow_ui_frame
        scrow_ui_put 1 "  ${C_ACCENT}${C_BOLD}Log — $file${C_RESET}"
        scrow_ui_put 2 "  ${C_DIM}${#lines[@]} lines${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=4
        for ((i=top; i<top+h && i<${#lines[@]}; i++)); do
            scrow_ui_put "$y" "  ${C_DIM}${lines[i]:0:$((SCROW_TUI_COLS - 4))}${C_RESET}"
            y+=1
        done
        scrow_ui_center_p "${C_HAIR}↑ ↓ scroll · q / Esc back${C_RESET}"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            up)   (( cur > 0 )) && (( cur -= 1 )) ;;
            down) (( cur + 1 < ${#lines[@]} )) && cur+=1 ;;
            q|esc|enter|eof|none) return ;;
            *) : ;;
        esac
        (( cur < top )) && top=$cur
        (( cur >= top + h )) && top=$(( cur - h + 1 ))
    done
}

# -----------------------------------------------------------------------------
# Operations
# -----------------------------------------------------------------------------
scrow_ui_op() {
    local title="$1"
    shift
    local fn="$1"
    shift
    scrow_ui_leave
    clear
    echo
    echo "  ${C_ACCENT}${C_BOLD}◆ SCROW — $title${C_RESET}"
    echo "  ${C_DIM}────────────────────────────────────────────────${C_RESET}"
    echo
    "$fn" "$@"
    local rc=$?
    echo
    echo "  ${C_DIM}────────────────────────────────────────────────${C_RESET}"
    scrow_ui_enter
    return $rc
}

# -----------------------------------------------------------------------------
# Installed-component set (in-memory, subprocess-free during navigation)
# -----------------------------------------------------------------------------
declare -a SCROW_TUI_INSTALLED=()
scrow_ui_installed_set() {
    SCROW_TUI_INSTALLED=()
    local name
    for name in $(scrow_state_components); do SCROW_TUI_INSTALLED+=("$name"); done
}

scrow_ui_is_installed() {
    local name="$1" x
    for x in "${SCROW_TUI_INSTALLED[@]:-}"; do
        [[ "$x" == "$name" ]] && return 0
    done
    return 1
}

scrow_ui_ts_fmt() {
    local ts="$1"
    if [[ "$ts" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
        printf '%s-%s-%s %s:%s' "${ts:0:4}" "${ts:4:2}" "${ts:6:2}" "${ts:9:2}" "${ts:11:2}"
    else
        printf '%s' "$ts"
    fi
}

# -----------------------------------------------------------------------------
# Status line (computed once per screen entry — no per-keypress work)
# -----------------------------------------------------------------------------
scrow_ui_plural() {
    local word="$1" n=$2
    if (( n == 1 )); then
        printf '%s' "$word"
    elif [[ "$word" == "${word^^}" ]]; then
        printf '%sS' "$word"
    else
        printf '%ss' "$word"
    fi
}

scrow_ui_join() {
    local d="$1"
    shift
    local out="" x
    for x in "$@"; do
        [[ -n "$out" ]] && out+="$d"
        out+="$x"
    done
    printf '%s' "$out"
}

scrow_ui_num() {
    local n=$1 s out=""
    (( n < 0 )) && n=0
    while (( n >= 1000 )); do
        printf -v s '%03d' $(( n % 1000 ))
        out=",$s$out"
        n=$(( n / 1000 ))
    done
    printf '%d%s' "$n" "$out"
}

scrow_ui_health_cell() {
    local icon="$1" color="$2" count="$3" label="$4" width="$5"
    local n
    n="$(scrow_ui_num "$count")"
    local -i numw=${#n}
    (( numw < 6 )) && numw=6
    printf -v n '%*s' "$numw" "$n"
    local -i labelmax=$(( width - 4 - numw ))
    (( labelmax < 0 )) && labelmax=0
    label="${label:0:$labelmax}"
    local head=" ${color}${icon}${C_RESET} ${color}${C_BOLD}${n}${C_RESET} ${C_DIM}${label}${C_RESET}"
    scrow_ui_vislen "$head"
    local -i pad=$(( width - scrow_ui_vislen_out ))
    (( pad < 1 )) && pad=1
    scrow_ui_spaces "$pad"
    printf '%s%s' "$head" "$scrow_ui_spaces_out"
}

SCROW_UI_STATUS_DOT=""
SCROW_UI_STATUS_TEXT=""
scrow_ui_status_compute() {
    scrow_ui_installed_set
    local name
    local -i total=0 installed=0 b=0
    for name in $(scrow_component_names); do
        total+=1
        scrow_ui_is_installed "$name" && installed+=1
    done
    local latest=""
    while IFS= read -r line; do
        (( b++ ))
        [[ -z "$latest" ]] && latest="$line"
    done < <(scrow_backup_available 2>/dev/null)
    if (( installed > 0 )); then
        SCROW_UI_STATUS_DOT="${C_OK}●${C_RESET}"
    else
        SCROW_UI_STATUS_DOT="${C_ACCENT}●${C_RESET}"
    fi
    SCROW_UI_STATUS_N=$installed
    SCROW_UI_STATUS_TOTAL=$total
    local txt=" $installed/$total components installed"
    local -a seg=()
    local last
    last="$(scrow_state_get INSTALL_DATE)"
    [[ "$last" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && last="${BASH_REMATCH[0]}"
    [[ -n "$last" ]] && seg+=(" · last install $last")
    if (( b > 0 )); then
        seg+=(" · $b $(scrow_ui_plural backup $b)")
        [[ -n "$latest" ]] && seg+=(" — newest $(scrow_ui_ts_fmt "$latest")")
    fi
    local -i avail=$(( SCROW_TUI_COLS - 4 ))
    local cand=""
    local -i k i
    for ((k=${#seg[@]}; k>=0; k--)); do
        cand="$txt"
        for ((i=0; i<k; i++)); do cand+="${seg[i]}"; done
        scrow_ui_vislen "$cand"
        (( scrow_ui_vislen_out <= avail )) && break
    done
    SCROW_UI_STATUS_TEXT="${C_DIM}${cand}${C_RESET}"
}

# -----------------------------------------------------------------------------
# Main menu data
# -----------------------------------------------------------------------------
SCROW_UI_MAIN_LABELS=(
    "Full Installation"
    "Custom Installation"
    "Components"
    "Update"
    "Restore"
    "Reset"
    "Doctor / Repair"
    "Uninstall"
)
SCROW_UI_MAIN_DESC=(
    "Recommended setup — installs every SCROW component, package and service for a complete Hyprland desktop."
    "Choose exactly which components to install. Dependencies are resolved automatically."
    "Inspect components and install, repair or remove them individually."
    "Fetch the latest SCROW, upgrade system packages, or re-apply component files."
    "Return SCROW-managed files to a previous automatic backup."
    "Return SCROW-owned files to the official repository state."
    "Check the health of every SCROW-managed file and repair problems."
    "Remove SCROW and every file it manages. Automatic backups are preserved."
)
SCROW_UI_MAIN_ACTIONS=(
    full
    custom
    components
    update
    restore
    reset
    doctor
    uninstall
)

# One menu item line. The selected item is a compact pill: the "› Label" text
# sits on the selection background while the rest of the row stays untouched.
scrow_ui_main_item_str() {
    local -i item=$1 sel=$2
    local lb="${SCROW_UI_MAIN_LABELS[item]}"
    if (( item == sel )); then
        printf -v scrow_ui_main_item_str_out '%s' "${C_SELBG}${C_ACCENT}${C_BOLD}› ${lb}${C_RESET}"
    else
        printf -v scrow_ui_main_item_str_out '%s' "${C_DIM}  ${lb}${C_RESET}"
    fi
}

# Item line padded to a fixed column width so left/right columns stay aligned.
scrow_ui_main_item_pad() {
    local -i item=$1 sel=$2 blockw=$3
    scrow_ui_main_item_str "$item" "$sel"
    local s="$scrow_ui_main_item_str_out"
    scrow_ui_vislen "$s"
    local -i pad=$(( blockw - scrow_ui_vislen_out ))
    (( pad < 0 )) && pad=0
    scrow_ui_spaces "$pad"
    printf -v scrow_ui_main_item_pad_out '%s%s' "$s" "$scrow_ui_spaces_out"
}

# Brand block: SCROW / Arch Linux · Hyprland / version.
scrow_ui_main_brand() {
    local -i y=$1
    scrow_ui_center_p "${C_ACCENT}${C_BOLD}SCROW${C_RESET}"
    scrow_ui_put "$y" "$scrow_ui_center_p_out"
    y+=1
    scrow_ui_center_p "${C_DIM}Arch Linux · Hyprland${C_RESET}"
    scrow_ui_put "$y" "$scrow_ui_center_p_out"
    y+=1
    scrow_ui_center_p "${C_FAINT}v${SCROW_VERSION}${C_RESET}"
    scrow_ui_put "$y" "$scrow_ui_center_p_out"
}

# Status line: colored dot + "N / TOTAL COMPONENTS", then a hairline rule.
scrow_ui_main_status() {
    local -i y=$1
    scrow_ui_center_p "${SCROW_UI_STATUS_DOT} ${C_DIM}${SCROW_UI_STATUS_N} / ${SCROW_UI_STATUS_TOTAL} COMPONENTS${C_RESET}"
    scrow_ui_put "$y" "$scrow_ui_center_p_out"
    y+=1
    local -i dw=$(( SCROW_TUI_COLS - 10 ))
    (( dw > 40 )) && dw=40
    (( dw < 6 )) && dw=6
    scrow_ui_center_p "${C_HAIR}$(scrow_ui_dash $dw)${C_RESET}"
    scrow_ui_put "$y" "$scrow_ui_center_p_out"
}

# Description block for the selected item: a small "Recommended" badge on a
# fixed reserved row (so nothing shifts), then the wrapped description. Both
# are left-aligned at the column edge `x` so they stay attached to the menu
# above them. Rows are only filled while they stay above the footer.
scrow_ui_main_desc() {
    local -i y=$1 sel=$2 descw=$3 x=$4
    local -i maxy=$(( SCROW_TUI_ROWS - 2 ))
    if (( sel == 0 )); then
        scrow_ui_spaces "$x"
        scrow_ui_put "$y" "${scrow_ui_spaces_out}${C_OK}${C_BOLD}● Recommended${C_RESET}"
    fi
    y+=1
    scrow_ui_wrap "${SCROW_UI_MAIN_DESC[sel]}" "$descw"
    local line
    for line in "${SCROW_TUI_WRAPPED[@]}"; do
        (( y >= maxy )) && break
        scrow_ui_spaces "$x"
        scrow_ui_put "$y" "${scrow_ui_spaces_out}${C_DIM}${line}${C_RESET}"
        y+=1
    done
}

# Underlined section heading (INSTALLATION / MANAGEMENT).
scrow_ui_main_heading() {
    local -i y=$1 x=$2
    local name="$3"
    scrow_ui_spaces "$x"
    scrow_ui_put "$y" "${scrow_ui_spaces_out}${C_ACCENT}${C_BOLD}${name}${C_RESET}"
    y+=1
    scrow_ui_spaces "$x"
    scrow_ui_put "$y" "${scrow_ui_spaces_out}${C_HAIR}$(scrow_ui_dash ${#name})${C_RESET}"
}

# Compact card primitives: rounded hairline edges in the teal structural color
# (C_FRAME). The *_s variants RETURN a row string (no leading spaces) so two
# cards can share one scrow_ui_put row; `w` is the outer width and content is
# padded to w-4 by callers.
scrow_ui_card_edge_s() {
    local -i w=$1
    local l="$2" r="$3"
    local -i inner=$(( w - 2 ))
    (( inner < 1 )) && inner=1
    printf -v scrow_ui_card_edge_s_out '%s%s%s%s' "${C_FRAME}${l}" "$(scrow_ui_dash $inner)" "${r}" "${C_RESET}"
}

scrow_ui_card_row_s() {
    local -i w=$1
    local content="$2"
    local -i inner=$(( w - 2 ))
    scrow_ui_vislen "$content"
    local -i pad=$(( inner - 2 - scrow_ui_vislen_out ))
    (( pad < 0 )) && pad=0
    scrow_ui_spaces "$pad"
    printf -v scrow_ui_card_row_s_out '%s│%s %s%s %s│%s' "${C_FRAME}" "${C_RESET}" "$content" "$scrow_ui_spaces_out" "${C_FRAME}" "${C_RESET}"
}

# Footer for the main menu: optional hairline rule above the key hints. The
# hint text shrinks on narrow terminals so it never clips.
scrow_ui_main_footer() {
    local -i wantrule=$1
    local -i y=$(( SCROW_TUI_ROWS - 1 ))
    if (( wantrule == 1 )); then
        local -i ry=$(( y - 1 ))
        local -i rw=$(( SCROW_TUI_COLS - 6 ))
        (( rw > 40 )) && rw=40
        (( rw < 6 )) && rw=6
        scrow_ui_center_p "${C_HAIR}$(scrow_ui_dash $rw)${C_RESET}"
        scrow_ui_put "$ry" "$scrow_ui_center_p_out"
    fi
    local -a variants=(
        "↑↓ Navigate   Enter Select   Q Quit"
        "↑↓ Navigate  Enter  Q Quit"
        "↑↓ Select  Q Quit"
        "↑↓  Q"
    )
    local hint v
    for hint in "${variants[@]}"; do
        scrow_ui_vislen "$hint"
        if (( scrow_ui_vislen_out <= SCROW_TUI_COLS )); then
            scrow_ui_center_p "${C_HAIR}${hint}${C_RESET}"
            scrow_ui_put "$y" "$scrow_ui_center_p_out"
            return
        fi
    done
}

# -----------------------------------------------------------------------------
# Main menu layouts
# -----------------------------------------------------------------------------
# Borderless two-column layout: brand block, status + hairline divider, then
# INSTALLATION / MANAGEMENT as two equal rounded cards. The selected item is a
# compact accent pill (accent text on the selection background) that never
# spans the full row. Fixed row budgets keep the screen still between
# keystrokes; empty rows simply stay empty. All helpers are pure bash.
scrow_frame_main_cards() {
    local -i sel=$1
    local -i cw=$SCROW_TUI_COLS
    local -i content=0 i v
    for ((i=0; i<8; i++)); do
        v=$(( 2 + ${#SCROW_UI_MAIN_LABELS[i]} ))
        (( v > content )) && content=$v
    done
    local -i w=$(( content + 4 ))
    local -i gap=6
    local -i total=$(( w + gap + w ))
    local -i xA=$(( (cw - total) / 2 ))
    (( xA < 1 )) && xA=1
    local -i xB=$(( xA + w + gap ))
    local -i inner=$(( w - 4 ))
    local -i descw=$(( total - 2 ))
    (( descw > cw - (xA + 1) )) && descw=$(( cw - (xA + 1) ))
    (( descw < 20 )) && descw=20

    local -i y=1
    scrow_ui_main_brand "$y"
    y=5
    scrow_ui_main_status "$y"
    y=8
    local -i hlx=$(( xA + (w - 12) / 2 ))
    (( hlx < xA + 1 )) && hlx=$(( xA + 1 ))
    local -i hrx=$(( xB + (w - 10) / 2 ))
    (( hrx < xB + 1 )) && hrx=$(( xB + 1 ))
    local -i hgap=$(( hrx - hlx - 12 ))
    (( hgap < 2 )) && hgap=2
    scrow_ui_spaces "$hlx"
    local p1="$scrow_ui_spaces_out"
    scrow_ui_spaces "$hgap"
    local p2="$scrow_ui_spaces_out"
    scrow_ui_put "$y" "${p1}${C_ACCENT}${C_BOLD}INSTALLATION${C_RESET}${p2}${C_ACCENT}${C_BOLD}MANAGEMENT${C_RESET}"
    y+=1
    local edge_top edge_bot lrow rrow
    scrow_ui_card_edge_s "$w" "╭" "╮"
    edge_top="$scrow_ui_card_edge_s_out"
    scrow_ui_card_edge_s "$w" "╰" "╯"
    edge_bot="$scrow_ui_card_edge_s_out"
    scrow_ui_spaces "$xA"
    local pA="$scrow_ui_spaces_out"
    scrow_ui_spaces "$gap"
    local pG="$scrow_ui_spaces_out"
    scrow_ui_spaces $((xA + w + gap))
    local pXB="$scrow_ui_spaces_out"
    scrow_ui_spaces $((w + gap))
    local pWG="$scrow_ui_spaces_out"
    scrow_ui_put "$y" "${pA}${edge_top}${pG}${edge_top}"
    y+=1
    local -i k
    for ((k=0; k<3; k++)); do
        scrow_ui_main_item_pad "$k" "$sel" "$inner"
        lrow="$scrow_ui_main_item_pad_out"
        scrow_ui_card_row_s "$w" "$lrow"
        lrow="$scrow_ui_card_row_s_out"
        scrow_ui_main_item_pad $((k+3)) "$sel" "$inner"
        rrow="$scrow_ui_main_item_pad_out"
        scrow_ui_card_row_s "$w" "$rrow"
        rrow="$scrow_ui_card_row_s_out"
        scrow_ui_put "$y" "${pA}${lrow}${pG}${rrow}"
        y+=1
    done
    scrow_ui_main_item_pad 6 "$sel" "$inner"
    rrow="$scrow_ui_main_item_pad_out"
    scrow_ui_card_row_s "$w" "$rrow"
    rrow="$scrow_ui_card_row_s_out"
    scrow_ui_put "$y" "${pA}${edge_bot}${pG}${rrow}"
    y+=1
    scrow_ui_main_item_pad 7 "$sel" "$inner"
    rrow="$scrow_ui_main_item_pad_out"
    scrow_ui_card_row_s "$w" "$rrow"
    rrow="$scrow_ui_card_row_s_out"
    scrow_ui_put "$y" "${pXB}${rrow}"
    y+=1
    scrow_ui_put "$y" "${pA}${pWG}${edge_bot}"
    y+=1
    scrow_ui_main_desc "$y" "$sel" "$descw" "$(( xA + 1 ))"
}

# One-column layout for narrow/short terminals. level 0 = full (brand, status,
# headings, items, description), 1 = compact (no brand/status), 2 = minimal
# (headings + items only).
scrow_frame_main_stack() {
    local -i sel=$1 level=$2
    local -i cw=$SCROW_TUI_COLS
    local -i blockw=0 i v
    for ((i=0; i<8; i++)); do
        v=$(( 2 + ${#SCROW_UI_MAIN_LABELS[i]} ))
        (( v > blockw )) && blockw=$v
    done
    local -i maxw=$(( cw - 4 ))
    (( blockw > maxw )) && blockw=$maxw
    local -i xoff=$(( (cw - blockw) / 2 ))
    (( xoff < 2 )) && xoff=2
    local -i descw=$(( cw - xoff ))
    (( descw < 20 )) && descw=20

    local -i y=1
    if (( level == 0 )); then
        scrow_ui_main_brand "$y"
        y=5
        scrow_ui_main_status "$y"
        y=8
    fi
    scrow_ui_main_heading "$y" "$xoff" "INSTALLATION"
    y+=2
    scrow_ui_spaces "$xoff"
    local pX="$scrow_ui_spaces_out"
    for ((i=0; i<3; i++)); do
        scrow_ui_main_item_pad "$i" "$sel" "$blockw"
        scrow_ui_put "$y" "${pX}${scrow_ui_main_item_pad_out}"
        y+=1
    done
    y+=1
    scrow_ui_main_heading "$y" "$xoff" "MANAGEMENT"
    y+=2
    for ((i=3; i<8; i++)); do
        scrow_ui_main_item_pad "$i" "$sel" "$blockw"
        scrow_ui_put "$y" "${pX}${scrow_ui_main_item_pad_out}"
        y+=1
    done
    y+=1
    (( level <= 1 )) && scrow_ui_main_desc "$y" "$sel" "$descw" "$xoff"
}

# Extremely compact list for tiny terminals: brand + count on one line, then
# the eight items, then the footer.
scrow_frame_main_list() {
    local -i sel=$1
    local -i cw=$SCROW_TUI_COLS
    local -i blockw=0 i v
    for ((i=0; i<8; i++)); do
        v=$(( 2 + ${#SCROW_UI_MAIN_LABELS[i]} ))
        (( v > blockw )) && blockw=$v
    done
    local -i maxw=$(( cw - 2 ))
    (( blockw > maxw )) && blockw=$maxw
    local -i xoff=$(( (cw - blockw) / 2 ))
    (( xoff < 1 )) && xoff=1
    local -i y=1
    scrow_ui_center_p "${C_ACCENT}${C_BOLD}SCROW${C_RESET}  ${C_DIM}${SCROW_UI_STATUS_N}/${SCROW_UI_STATUS_TOTAL}${C_RESET}"
    scrow_ui_put "$y" "$scrow_ui_center_p_out"
    y+=1
    scrow_ui_spaces "$xoff"
    local pX="$scrow_ui_spaces_out"
    for ((i=0; i<8; i++)); do
        (( y >= SCROW_TUI_ROWS - 1 )) && break
        scrow_ui_main_item_pad "$i" "$sel" "$blockw"
        scrow_ui_put "$y" "${pX}${scrow_ui_main_item_pad_out}"
        y+=1
    done
}

scrow_frame_main() {
    local -i sel=$1
    scrow_ui_frame
    local -i cw=$SCROW_TUI_COLS rh=$SCROW_TUI_ROWS

    local -i level=0
    local -i wantrule=0
    if (( rh <= 14 || cw < 38 )); then
        scrow_frame_main_list "$sel"
    elif (( cw >= 66 && rh >= 24 )); then
        scrow_frame_main_cards "$sel"
        wantrule=1
    else
        if (( rh < 20 )); then
            level=2
        elif (( rh < 26 )); then
            level=1
        fi
        scrow_frame_main_stack "$sel" "$level"
    fi
    scrow_ui_main_footer "$wantrule"
}

# -----------------------------------------------------------------------------
# Screens
# -----------------------------------------------------------------------------
scrow_screen_install_full() {
    local -a wanted=()
    local name
    for name in $(scrow_component_names); do
        scrow_ui_is_installed "$name" && continue
        scrow_config_component_skipped "$name" && continue
        wanted+=("$name")
    done
    if [[ ${#wanted[@]} -eq 0 ]]; then
        scrow_ui_result "Full Installation" ok \
            "All components are already installed." \
            "There is nothing left to install."
        return
    fi
    local -i sel=0
    local -i y
    local w
    while true; do
        scrow_ui_frame
        scrow_ui_put 1 "  ${C_ACCENT}${C_BOLD}FULL INSTALLATION${C_RESET}"
        scrow_ui_put 2 "  ${C_FAINT}Recommended — installs every SCROW component.${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=5
        local -i nw=${#wanted[@]}
        scrow_ui_put "$y" "  ${C_DIM}This will install $nw $(scrow_ui_plural component $nw):${C_RESET}"
        y+=1
        for w in "${wanted[@]}"; do
            (( y < SCROW_TUI_ROWS - 10 )) || break
            scrow_ui_put "$y" "   ${C_ACCENT}●${C_RESET}  ${C_DIM}${w}${C_RESET}  ${C_FAINT}$(scrow_component_title "$w")${C_RESET}"
            y+=1
        done
        if (( y >= SCROW_TUI_ROWS - 10 )); then
            scrow_ui_put "$y" "   ${C_DIM}…${C_RESET}"
            y+=1
        fi
        y+=1
        scrow_ui_put "$y" "  ${C_FAINT}Packages are installed automatically and an automatic backup is${C_RESET}"
        y+=1
        scrow_ui_put "$y" "  ${C_FAINT}created before anything is changed.${C_RESET}"
        y+=2
        scrow_ui_buttons "$y" $sel "Install" "Cancel"
        scrow_ui_center_p "${C_HAIR}← → choose · Enter confirm · Esc back${C_RESET}"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            left|right) sel=$(( 1 - sel )) ;;
            enter)
                if (( sel == 0 )); then
                    scrow_ui_op "Full Installation" scrow_engine_install "${wanted[@]}"
                    if (( $? == 0 )); then
                        scrow_ui_result "Full Installation" ok \
                            "SCROW has been installed successfully." \
                            "Installed: $(scrow_ui_join ", " "${wanted[@]}")"
                    else
                        scrow_ui_result "Full Installation" err --log "$SCROW_CURRENT_LOG" \
                            "Something went wrong during installation." \
                            "Check the log for details, then try again."
                    fi
                fi
                return ;;
            esc|q|eof|none) return ;;
        esac
    done
}

scrow_screen_install_custom() {
    local -a names=() sel=()
    local name
    for name in $(scrow_component_names); do
        names+=("$name")
        if scrow_ui_is_installed "$name"; then sel+=(1); else sel+=(0); fi
    done
    local -i n=${#names[@]}
    local -i cur=0 top=0
    local -i h=$(( SCROW_TUI_ROWS - 11 ))
    (( h < 4 )) && h=4
    local -i i y
    local -i chosen=0
    for ((i=0; i<n; i++)); do (( sel[i] == 1 )) && chosen+=1; done
    while true; do
        scrow_ui_frame
        scrow_ui_put 1 "  ${C_ACCENT}${C_BOLD}CUSTOM INSTALLATION${C_RESET}"
        scrow_ui_put 2 "  ${C_FAINT}Choose components — dependencies are added automatically.${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        scrow_ui_put 4 "  ${C_DIM}Selected: ${C_ACCENT}${chosen}${C_DIM} of $n${C_RESET}"
        y=6
        local title sym marker plain
        for ((i=top; i<top+h && i<n; i++)); do
            name="${names[i]}"
            title="$(scrow_component_title "$name")"
            title="${title:0:$((SCROW_TUI_COLS - 16))}"
            marker="  "
            (( i == cur )) && marker="› "
            sym="○"
            (( sel[i] == 1 )) && sym="●"
            plain="${marker}${sym} ${name}  ${title}"
            if (( i == cur )); then
                local -i plen=${#plain}
                local -i gpad=$(( SCROW_TUI_COLS - plen ))
                (( gpad < 2 )) && gpad=2
                scrow_ui_spaces "$gpad"
                scrow_ui_put "$y" "${C_SELBG}${C_ACCENT}${C_BOLD}${plain}${scrow_ui_spaces_out}${C_RESET}"
            elif (( sel[i] == 1 )); then
                scrow_ui_put "$y" "${C_DIM}${marker}${C_ACCENT}${sym}${C_RESET} ${C_DIM}${name}  ${C_FAINT}${title}${C_RESET}"
            else
                scrow_ui_put "$y" "${C_DIM}${marker}${C_HAIR}${sym}${C_RESET} ${C_DIM}${name}  ${C_FAINT}${title}${C_RESET}"
            fi
            y+=1
        done
        scrow_ui_center_p "${C_HAIR}↑ ↓ navigate · Space toggle · Enter continue · Esc back${C_RESET}"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            up)   (( cur > 0 )) && (( cur -= 1 )) ;;
            down) (( cur + 1 < n )) && cur+=1 ;;
            space)
                sel[cur]=$(( 1 - sel[cur] ))
                if (( sel[cur] == 1 )); then chosen+=1; else (( chosen -= 1 )); fi
                ;;
            enter) break ;;
            esc|q|eof|none) return ;;
        esac
        (( cur < top )) && top=$cur
        (( cur >= top + h )) && top=$(( cur - h + 1 ))
    done
    local -a chosen_names=()
    for ((i=0; i<n; i++)); do
        (( sel[i] == 1 )) && chosen_names+=("${names[i]}")
    done
    if [[ ${#chosen_names[@]} -eq 0 ]]; then
        scrow_ui_result "Custom Installation" warn \
            "No components selected." \
            "Nothing to install."
        return
    fi
    local -i confirm_sel=0
    while true; do
        scrow_ui_frame
        scrow_ui_put 1 "  ${C_ACCENT}${C_BOLD}CUSTOM INSTALLATION${C_RESET}"
        scrow_ui_put 2 "  ${C_FAINT}Confirm your selection.${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=5
        local -i nc=${#chosen_names[@]}
        scrow_ui_put "$y" "  ${C_DIM}This will install $nc $(scrow_ui_plural component $nc):${C_RESET}"
        y+=1
        for ((i=0; i<${#chosen_names[@]}; i++)); do
            (( y < SCROW_TUI_ROWS - 9 )) || break
            scrow_ui_put "$y" "   ${C_ACCENT}●${C_RESET}  ${C_DIM}${chosen_names[i]}${C_RESET}  ${C_FAINT}$(scrow_component_title "${chosen_names[i]}")${C_RESET}"
            y+=1
        done
        y+=1
        scrow_ui_put "$y" "  ${C_FAINT}Required dependencies are installed automatically and an${C_RESET}"
        y+=1
        scrow_ui_put "$y" "  ${C_FAINT}automatic backup is created before anything is changed.${C_RESET}"
        y+=2
        scrow_ui_buttons "$y" $confirm_sel "Install" "Cancel"
        scrow_ui_center_p "${C_HAIR}← → choose · Enter confirm · Esc back${C_RESET}"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            left|right) confirm_sel=$(( 1 - confirm_sel )) ;;
            enter)
                if (( confirm_sel == 0 )); then
                    scrow_ui_op "Custom Installation" scrow_engine_install "${chosen_names[@]}"
                    if (( $? == 0 )); then
                        scrow_ui_result "Custom Installation" ok \
                            "Installation finished." \
                            "Installed: $(scrow_ui_join ", " "${chosen_names[@]}")"
                    else
                        scrow_ui_result "Custom Installation" err --log "$SCROW_CURRENT_LOG" \
                            "Something went wrong during installation." \
                            "Check the log for details, then try again."
                    fi
                fi
                return ;;
            esc|q|eof|none) return ;;
        esac
    done
}

scrow_screen_components() {
    local -a names=()
    local name
    for name in $(scrow_component_names); do names+=("$name"); done
    local -i n=${#names[@]}
    local -i cur=0 top=0
    local -i h=$(( SCROW_TUI_ROWS - 10 ))
    (( h < 4 )) && h=4
    local -i i y
    local title desc marker
    while true; do
        scrow_ui_frame
        scrow_ui_put 1 "  ${C_ACCENT}${C_BOLD}COMPONENTS${C_RESET}"
        scrow_ui_put 2 "  ${C_FAINT}Select a component to manage it.${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=5
        for ((i=top; i<top+h && i<n; i++)); do
            name="${names[i]}"
            title="$(scrow_component_title "$name")"
            title="${title:0:$((SCROW_TUI_COLS - 18))}"
            marker="  "
            (( i == cur )) && marker="› "
            local sym_color sym_ch
            if scrow_ui_is_installed "$name"; then
                sym_color="$C_OK"; sym_ch="●"
            else
                sym_color="$C_HAIR"; sym_ch="○"
            fi
            if (( i == cur )); then
                local -i plen=$(( ${#marker} + ${#sym_ch} + 1 + ${#name} + 2 + ${#title} ))
                local -i gpad=$(( SCROW_TUI_COLS - plen ))
                (( gpad < 2 )) && gpad=2
                scrow_ui_spaces "$gpad"
                scrow_ui_put "$y" "${C_SELBG}${C_ACCENT}${C_BOLD}${marker}${sym_color}${sym_ch}${C_ACCENT}${C_BOLD} ${name}  ${title}${scrow_ui_spaces_out}${C_RESET}"
            else
                scrow_ui_put "$y" "${C_DIM}${marker}${sym_color}${sym_ch}${C_RESET} ${C_DIM}${name}  ${C_FAINT}${title}${C_RESET}"
            fi
            y+=1
        done
        name="${names[cur]}"
        desc="$(scrow_component_desc "$name")"
        local pkgs aur
        pkgs="$(scrow_component_packages "$name")"
        aur="$(scrow_component_aur "$name")"
        local -i np=0 na=0
        set -- $pkgs; np=$#
        set -- $aur; na=$#
        local -i info_y=$(( SCROW_TUI_ROWS - 4 ))
        scrow_ui_hline $(( info_y - 1 )) "$C_HAIR"
        scrow_ui_put "$info_y" "  ${C_ACCENT}${C_BOLD}${name}${C_RESET}  ${C_FAINT}${desc}${C_RESET}"
        local status_part
        if scrow_ui_is_installed "$name"; then
            status_part="${C_OK}●${C_RESET} ${C_DIM}installed${C_RESET}"
        else
            status_part="${C_HAIR}○${C_RESET} ${C_DIM}not installed${C_RESET}"
        fi
        scrow_ui_put $(( info_y + 1 )) "  ${status_part}  ·  ${C_DIM}${np} official · ${na} AUR${C_RESET}"
        scrow_ui_center_p "${C_HAIR}↑ ↓ navigate · Enter manage · Esc back${C_RESET}"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            up)   (( cur > 0 )) && (( cur -= 1 )) ;;
            down) (( cur + 1 < n )) && cur+=1 ;;
            enter)
                scrow_screen_component_detail "${names[cur]}"
                scrow_ui_installed_set
                scrow_ui_size
                ;;
            esc|q|eof|none) return ;;
        esac
        (( cur < top )) && top=$cur
        (( cur >= top + h )) && top=$(( cur - h + 1 ))
    done
}

scrow_screen_component_detail() {
    local name="$1"
    local -a acts=(Install)
    scrow_ui_is_installed "$name" && acts+=(Repair Remove)
    acts+=(Back)
    local -i sel=0
    local -i y
    local line w
    while true; do
        scrow_ui_frame
        scrow_ui_put 1 "  ${C_ACCENT}${C_BOLD}${name}${C_RESET}"
        scrow_ui_put 2 "  ${C_FAINT}$(scrow_component_title "$name")${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=5
        if scrow_ui_is_installed "$name"; then
            scrow_ui_put "$y" "  ${C_OK}●  installed${C_RESET}"
        else
            scrow_ui_put "$y" "  ${C_HAIR}○  not installed${C_RESET}"
        fi
        y+=2
        scrow_ui_wrap "$(scrow_component_desc "$name")" $((SCROW_TUI_COLS - 8))
        for w in "${SCROW_TUI_WRAPPED[@]}"; do
            (( y < SCROW_TUI_ROWS - 8 )) || break
            scrow_ui_put "$y" "  ${C_DIM}${w}${C_RESET}"
            y+=1
        done
        y+=1
        local pkgs aur
        pkgs="$(scrow_component_packages "$name")"
        aur="$(scrow_component_aur "$name")"
        local -i np=0 na=0
        set -- $pkgs; np=$#
        set -- $aur; na=$#
        scrow_ui_put "$y" "  ${C_FAINT}official packages: $np   ·   AUR packages: $na${C_RESET}"
        y+=1
        local deps
        deps="$(scrow_component_needs "$name")"
        [[ -z "$deps" ]] && deps="none"
        scrow_ui_put "$y" "  ${C_FAINT}dependencies: $deps${C_RESET}"
        y+=2
        scrow_ui_buttons $((SCROW_TUI_ROWS - 4)) $sel "${acts[@]}"
        scrow_ui_center_p "${C_HAIR}← → choose action · Enter run · Esc back${C_RESET}"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            left|right)
                sel=$(( 1 - sel ))
                (( sel > ${#acts[@]} - 1 )) && sel=$(( ${#acts[@]} - 1 ))
                ;;
            enter)
                case "${acts[sel]}" in
                    Install)
                        scrow_ui_op "Install $name" scrow_engine_install "$name"
                        local rc=$?
                        scrow_ui_result "Install $name" "$([[ $rc -eq 0 ]] && echo ok || echo err)" \
                            "$([[ $rc -eq 0 ]] && echo "Component $name installed." || echo "Installation failed — check the log.")"
                        ;;
                    Repair)
                        if scrow_ui_confirm "Repair $name" "Repair" "Cancel" 0 \
                            "Restores the files of this component to the official repository state." \
                            "An automatic backup is created first."; then
                            scrow_ui_op "Repair $name" scrow_engine_refresh "$name"
                            local rc=$?
                            scrow_ui_result "Repair $name" "$([[ $rc -eq 0 ]] && echo ok || echo err)" \
                                "$([[ $rc -eq 0 ]] && echo "Component $name is back in sync." || echo "Repair failed — check the log.")"
                        fi
                        ;;
                    Remove)
                        if scrow_ui_confirm "Remove $name" "Remove" "Cancel" 1 \
                            "Removes every SCROW-managed file of this component." \
                            "Packages are not removed. An automatic backup is created first."; then
                            local ay="$SCROW_ASSUME_YES"
                            SCROW_ASSUME_YES=1
                            scrow_ui_op "Remove $name" scrow_engine_remove_component "$name"
                            local rc=$?
                            SCROW_ASSUME_YES=$ay
                            scrow_ui_result "Remove $name" "$([[ $rc -eq 0 ]] && echo ok || echo err)" \
                                "$([[ $rc -eq 0 ]] && echo "Component $name removed." || echo "Remove failed — check the log.")"
                        fi
                        ;;
                    Back) return ;;
                esac
                return ;;
            esc|q|eof|none) return ;;
        esac
    done
}

scrow_ui_update_all() {
    # scrow_engine_update already converges every installed component to the
    # newly fetched repository state, so no separate refresh pass is needed.
    scrow_engine_update
}

scrow_screen_update() {
    local -a labels=( "Update SCROW" "Upgrade system packages" "Refresh installed files" "Back" )
    local -a descs=(
        "Fetch the latest SCROW repository and apply updated files (auto-backup first)."
        "Run pacman -Syu plus an AUR upgrade, then re-index SCROW."
        "Re-apply repository files to installed components (auto-backup first)."
        ""
    )
    local -i n=${#labels[@]}
    local -i cur=0
    local -i y
    local w
    while true; do
        scrow_ui_frame
        scrow_ui_put 1 "  ${C_ACCENT}${C_BOLD}UPDATE${C_RESET}"
        scrow_ui_put 2 "  ${C_FAINT}Keep SCROW and your installed components up to date.${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=5
        local marker
        for ((i=0; i<n; i++)); do
            marker="  "
            (( i == cur )) && marker="› "
            if (( i == cur )); then
                local -i plen=$(( ${#marker} + ${#labels[i]} ))
                local -i gpad=$(( SCROW_TUI_COLS - plen - 6 ))
                (( gpad < 2 )) && gpad=2
                scrow_ui_spaces "$gpad"
                scrow_ui_put "$y" "${C_SELBG}${C_ACCENT}${C_BOLD}${marker}${labels[i]}${scrow_ui_spaces_out}${C_RESET}"
            else
                scrow_ui_put "$y" "${C_DIM}${marker}${labels[i]}${C_RESET}"
            fi
            y+=1
        done
        local -i info_y=$(( SCROW_TUI_ROWS - 4 ))
        scrow_ui_hline $(( info_y - 1 )) "$C_HAIR"
        if [[ -n "${descs[cur]}" ]]; then
            scrow_ui_wrap "${descs[cur]}" $((SCROW_TUI_COLS - 8))
            local -i dy=$info_y
            for w in "${SCROW_TUI_WRAPPED[@]}"; do
                (( dy < SCROW_TUI_ROWS - 1 )) || break
                scrow_ui_put "$dy" "  ${C_FAINT}${w}${C_RESET}"
                dy+=1
            done
        fi
        scrow_ui_center_p "${C_HAIR}↑ ↓ navigate · Enter run · Esc back${C_RESET}"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            up)   (( cur > 0 )) && (( cur -= 1 )) ;;
            down) (( cur + 1 < n )) && cur+=1 ;;
            enter)
                case "$cur" in
                    0)
                        if scrow_ui_confirm "Update SCROW" "Update" "Cancel" 0 \
                            "Fetches the latest SCROW repository and applies updated files." \
                            "Files you modified are preserved by an automatic backup."; then
                            scrow_ui_op "Update SCROW" scrow_ui_update_all
                            local rc=$?
                            scrow_ui_result "Update SCROW" "$([[ $rc -eq 0 ]] && echo ok || echo err)" --log "$SCROW_CURRENT_LOG" \
                                "$([[ $rc -eq 0 ]] && echo "SCROW is up to date." || echo "Update failed — check the log.")"
                        fi
                        ;;
                    1)
                        if scrow_ui_confirm "Upgrade system packages" "Upgrade" "Cancel" 0 \
                            "Runs pacman -Syu and an AUR upgrade." \
                            "This upgrades every package on the system and then re-indexes SCROW."; then
                            scrow_ui_op "System upgrade" scrow_engine_upgrade
                            local rc=$?
                            scrow_ui_result "System upgrade" "$([[ $rc -eq 0 ]] && echo ok || echo err)" --log "$SCROW_CURRENT_LOG" \
                                "$([[ $rc -eq 0 ]] && echo "System packages are up to date." || echo "Upgrade failed — check the log.")"
                        fi
                        ;;
                    2)
                        if scrow_ui_confirm "Refresh installed files" "Refresh" "Cancel" 0 \
                            "Re-applies repository files to installed components." \
                            "Files you modified are preserved by an automatic backup."; then
                            scrow_ui_op "Re-sync files" scrow_engine_refresh
                            local rc=$?
                            scrow_ui_result "Re-sync files" "$([[ $rc -eq 0 ]] && echo ok || echo err)" \
                                "$([[ $rc -eq 0 ]] && echo "Components are back in sync." || echo "Re-sync failed — check the log.")"
                        fi
                        ;;
                    3) return ;;
                esac
                return ;;
            esc|q|eof|none) return ;;
        esac
    done
}

scrow_screen_restore() {
    local -a backups=()
    local b
    while IFS= read -r b; do
        [[ -n "$b" ]] && backups+=("$b")
    done < <(scrow_backup_available 2>/dev/null)
    if [[ ${#backups[@]} -eq 0 ]]; then
        scrow_ui_result "Restore" warn \
            "No automatic backups found." \
            "Backups are stored in: $(scrow_backup_dir)/AUTO_BACKUP"
        return
    fi
    local -i n=${#backups[@]}
    local -i cur=0 top=0
    local -i h=$(( SCROW_TUI_ROWS - 9 ))
    (( h < 4 )) && h=4
    local -i i y
    local ts
    while true; do
        scrow_ui_frame
        scrow_ui_put 1 "  ${C_ACCENT}${C_BOLD}RESTORE${C_RESET}"
        scrow_ui_put 2 "  ${C_FAINT}Return SCROW-managed files to an automatic backup.${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=5
        for ((i=top; i<top+h && i<n; i++)); do
            ts="${backups[i]}"
            local marker="  "
            (( i == cur )) && marker="› "
            local row="${marker}$(scrow_ui_ts_fmt "$ts")"
            if (( i == cur )); then
                local -i plen=$(( ${#marker} + 16 ))
                local -i gpad=$(( SCROW_TUI_COLS - plen - 6 ))
                (( gpad < 2 )) && gpad=2
                scrow_ui_spaces "$gpad"
                scrow_ui_put "$y" "${C_SELBG}${C_ACCENT}${C_BOLD}${row}${scrow_ui_spaces_out}${C_RESET}"
            else
                scrow_ui_put "$y" "${C_DIM}${row}${C_RESET}"
            fi
            y+=1
        done
        if (( n > h )); then
            scrow_ui_put $((SCROW_TUI_ROWS - 3)) "  ${C_DIM}$(( top + 1 ))-$(( top + h < n ? top + h : n )) of $n backups${C_RESET}"
        fi
        scrow_ui_center_p "${C_HAIR}↑ ↓ navigate · Enter restore · Esc back${C_RESET}"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            up)   (( cur > 0 )) && (( cur -= 1 )) ;;
            down) (( cur + 1 < n )) && cur+=1 ;;
            enter)
                ts="${backups[cur]}"
                if scrow_ui_confirm "Restore from backup" "Restore" "Cancel" 1 \
                    "Restores SCROW-managed files from the backup made on $(scrow_ui_ts_fmt "$ts")." \
                    "The current state is backed up automatically first, and this backup is not deleted."; then
                    scrow_ui_op "Restore" scrow_engine_restore $(( cur + 1 ))
                    local rc=$?
                    scrow_ui_result "Restore" "$([[ $rc -eq 0 ]] && echo ok || echo err)" --log "$SCROW_CURRENT_LOG" \
                        "$([[ $rc -eq 0 ]] && echo "Files restored from $(scrow_ui_ts_fmt "$ts")." || echo "Restore failed — check the log.")"
                fi
                return ;;
            esc|q|eof|none) return ;;
        esac
        (( cur < top )) && top=$cur
        (( cur >= top + h )) && top=$(( cur - h + 1 ))
    done
}

scrow_screen_reset() {
    scrow_ui_confirm "Reset SCROW" "Reset" "Cancel" 1 \
        "Returns every SCROW-owned file to the official repository state." \
        "SCROW-enabled services and install state are also reset." \
        "An automatic backup is created first. Files SCROW does not own are untouched." \
        "This is permanent unless you restore from a backup afterwards."
    local rc=$?
    (( rc == 2 || rc == 1 )) && return
    scrow_ui_op "Reset" scrow_engine_reset
    local rc=$?
    scrow_ui_result "Reset" "$([[ $rc -eq 0 ]] && echo ok || echo err)" --log "$SCROW_CURRENT_LOG" \
        "$([[ $rc -eq 0 ]] && echo "SCROW-managed files are back to the official state." || echo "Reset failed — check the log.")"
}

scrow_screen_doctor() {
    scrow_ui_frame
    scrow_ui_put 1 "  ${C_ACCENT}${C_BOLD}DOCTOR${C_RESET}"
    scrow_ui_put 2 "  ${C_FAINT}Every SCROW-managed file is verified for integrity.${C_RESET}"
    scrow_ui_hline 3 "$C_HAIR"
    scrow_ui_put 5 "  ${C_DIM}Checking managed files…${C_RESET}"
    scrow_ui_render
    scrow_analyze
    local -i modified=$SCROW_AN_MODIFIED_N missing=$SCROW_AN_MISSING_N broken=$SCROW_AN_BROKEN_N removed=$SCROW_AN_REMOVED_N sync=$SCROW_AN_SYNC_N
    local -i missing_dirs=$SCROW_AN_MISSING_DIRS_N missing_pkgs=$SCROW_AN_MISSING_PKGS_N disabled_svc=$SCROW_AN_DISABLED_SVC_N
    local -i issues=$(( modified + missing + broken + removed + missing_dirs + missing_pkgs + disabled_svc ))
    local color chip
    if (( missing + broken + removed + missing_dirs + missing_pkgs + disabled_svc > 0 )); then
        color="$C_ERR"; chip="✗  $issues $(scrow_ui_plural ISSUE $issues)"
    elif (( modified > 0 )); then
        color="$C_WARN"; chip="!  $modified MODIFIED"
    else
        color="$C_OK"; chip="✓  HEALTHY"
    fi
    local -a labs=("Back")
    (( issues > 0 )) && labs=("Repair" "View Details" "Back")
    local -i sel=0
    local -i y
    while true; do
        scrow_ui_frame
        local title="  ${C_ACCENT}${C_BOLD}DOCTOR${C_RESET}"
        local chipstr="  ${color}${C_BOLD}${chip}${C_RESET}"
        scrow_ui_vislen "$title"
        local -i tv=$scrow_ui_vislen_out
        scrow_ui_vislen "$chipstr"
        local -i gap=$(( SCROW_TUI_COLS - tv - scrow_ui_vislen_out - 2 ))
        (( gap < 1 )) && gap=1
        scrow_ui_spaces "$gap"
        scrow_ui_put 1 "${title}${scrow_ui_spaces_out}${chipstr}"
        scrow_ui_put 2 "  ${C_FAINT}Every SCROW-managed file is verified for integrity.${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=5
        local -i cellw=$(( (SCROW_TUI_COLS - 4) / 2 ))
        (( cellw < 10 )) && cellw=10
        local -i cellw_full=$(( SCROW_TUI_COLS - 4 ))
        (( cellw_full < 10 )) && cellw_full=10
        scrow_ui_put "$y" "  $(scrow_ui_health_cell ✓ "$C_OK" $sync "in sync" $cellw)$(scrow_ui_health_cell ✗ "$C_ERR" $missing "missing on system" $cellw)"
        y+=1
        scrow_ui_put "$y" "  $(scrow_ui_health_cell ! "$C_WARN" $modified "modified by you" $cellw)$(scrow_ui_health_cell ✗ "$C_ERR" $broken "broken symlinks" $cellw)"
        y+=1
        scrow_ui_put "$y" "  $(scrow_ui_health_cell ✗ "$C_ERR" $missing_dirs "missing directories" $cellw)$(scrow_ui_health_cell ✗ "$C_ERR" $missing_pkgs "missing packages" $cellw)"
        y+=1
        scrow_ui_put "$y" "  $(scrow_ui_health_cell ✗ "$C_ERR" $disabled_svc "disabled services" $cellw)$(scrow_ui_health_cell ◇ "$C_ACCENT" $removed "removed from repo" $cellw)"
        y+=1
        scrow_ui_put "$y" "  $(scrow_ui_health_cell ◇ "$C_ACCENT" $SCROW_AN_NEW_N "new files not deployed" $cellw_full)"
        y+=2
        scrow_ui_hline "$y" "$C_HAIR"
        y+=1
        if (( SCROW_AN_REPO_MISSING == 1 )); then
            scrow_ui_put "$y" "  ${C_DIM}The SCROW repository could not be fetched — check the network,${C_RESET}"
            y+=1
            scrow_ui_put "$y" "  ${C_DIM}then run Doctor again.${C_RESET}"
            y+=1
        elif (( issues > 0 )); then
            scrow_ui_put "$y" "  ${C_FAINT}Repair restores the official files — an automatic backup is created first.${C_RESET}"
            y+=1
            (( modified > 0 )) && scrow_ui_put "$y" "  ${C_WARN}Your $modified modified $(scrow_ui_plural file $modified) are kept in that backup.${C_RESET}"
        else
            scrow_ui_put "$y" "  ${C_OK}Everything SCROW manages is healthy — no action needed.${C_RESET}"
        fi
        scrow_ui_buttons $((SCROW_TUI_ROWS - 4)) $sel "${labs[@]}"
        local footer
        if (( ${#labs[@]} > 1 )); then
            footer="${C_HAIR}← → choose · Enter run · Esc back${C_RESET}"
        else
            footer="${C_HAIR}Enter back · Esc back${C_RESET}"
        fi
        scrow_ui_center_p "$footer"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            left|right)
                sel=$(( 1 - sel ))
                (( sel > ${#labs[@]} - 1 )) && sel=$(( ${#labs[@]} - 1 ))
                ;;
            enter)
                case "${labs[sel]}" in
                    Repair)
                        scrow_ui_op "Repair" scrow_engine_repair
                        local rc=$?
                        scrow_ui_result "Repair" "$([[ $rc -eq 0 ]] && echo ok || echo err)" --log "$SCROW_CURRENT_LOG" \
                            "$([[ $rc -eq 0 ]] && echo "SCROW-managed files are back in sync." || echo "Repair failed — check the log.")"
                        return ;;
                    "View Details") scrow_screen_doctor_details ;;
                    Back) return ;;
                esac
                ;;
            esc|q|eof|none) return ;;
        esac
    done
}

scrow_screen_doctor_details() {
    local -a items=()
    local f
    if (( ${#SCROW_AN_MODIFIED[@]} > 0 )); then
        items+=("::Modified by you (${#SCROW_AN_MODIFIED[@]})")
        for f in "${SCROW_AN_MODIFIED[@]}"; do items+=("$f"); done
    fi
    if (( ${#SCROW_AN_MISSING[@]} > 0 )); then
        items+=("::Missing on system (${#SCROW_AN_MISSING[@]})")
        for f in "${SCROW_AN_MISSING[@]}"; do items+=("$f"); done
    fi
    if (( ${#SCROW_AN_MISSING_DIRS[@]} > 0 )); then
        items+=("::Missing directories (${#SCROW_AN_MISSING_DIRS[@]})")
        for f in "${SCROW_AN_MISSING_DIRS[@]}"; do items+=("$f/"); done
    fi
    if (( ${#SCROW_AN_MISSING_PKGS[@]} > 0 )); then
        items+=("::Missing packages (${#SCROW_AN_MISSING_PKGS[@]})")
        for f in "${SCROW_AN_MISSING_PKGS[@]}"; do items+=("$f"); done
    fi
    if (( ${#SCROW_AN_DISABLED_SVC[@]} > 0 )); then
        items+=("::Disabled services (${#SCROW_AN_DISABLED_SVC[@]})")
        for f in "${SCROW_AN_DISABLED_SVC[@]}"; do items+=("$f"); done
    fi
    if (( ${#SCROW_AN_BROKEN[@]} > 0 )); then
        items+=("::Broken symlinks (${#SCROW_AN_BROKEN[@]})")
        for f in "${SCROW_AN_BROKEN[@]}"; do items+=("$f"); done
    fi
    if (( ${#SCROW_AN_REMOVED[@]} > 0 )); then
        items+=("::Removed from repository (${#SCROW_AN_REMOVED[@]})")
        for f in "${SCROW_AN_REMOVED[@]}"; do items+=("$f"); done
    fi
    if (( ${#SCROW_AN_NEW[@]} > 0 )); then
        items+=("::New in repository (${#SCROW_AN_NEW[@]})")
        for f in "${SCROW_AN_NEW[@]}"; do items+=("$f"); done
    fi
    local -i total=$(( ${#SCROW_AN_MODIFIED[@]} + ${#SCROW_AN_MISSING[@]} + ${#SCROW_AN_MISSING_DIRS[@]} \
        + ${#SCROW_AN_MISSING_PKGS[@]} + ${#SCROW_AN_DISABLED_SVC[@]} + ${#SCROW_AN_BROKEN[@]} \
        + ${#SCROW_AN_REMOVED[@]} + ${#SCROW_AN_NEW[@]} ))
    if (( total == 0 )); then
        scrow_ui_result "Doctor" warn \
            "No problems found." \
            "Every file SCROW manages is in a healthy state."
        return
    fi
    local -i n=${#items[@]}
    local -i cur=0 top=0
    local -i h=$(( SCROW_TUI_ROWS - 11 ))
    (( h < 4 )) && h=4
    local -i i y
    local it
    while true; do
        scrow_ui_frame
        scrow_ui_put 1 "  ${C_ACCENT}${C_BOLD}DETAILS${C_RESET}"
        scrow_ui_put 2 "  ${C_FAINT}${total} $(scrow_ui_plural file $total) with issues${C_RESET}"
        scrow_ui_hline 3 "$C_HAIR"
        y=5
        for ((i=top; i<n && i<top+h; i++)); do
            it="${items[i]}"
            if [[ "$it" == "::"* ]]; then
                scrow_ui_put "$y" "  ${C_ACCENT}${C_BOLD}${it#::}${C_RESET}"
            else
                scrow_ui_put "$y" "    ${C_DIM}${it:0:$((SCROW_TUI_COLS - 8))}${C_RESET}"
            fi
            y+=1
        done
        if (( n > h )); then
            local -i f0=0 f1=0 k
            for ((k=0; k<top; k++)); do [[ "${items[k]}" != "::"* ]] && f0+=1; done
            for ((k=top; k<top+h && k<n; k++)); do [[ "${items[k]}" != "::"* ]] && f1+=1; done
            (( f1 > 0 )) && scrow_ui_put $((SCROW_TUI_ROWS - 5)) "  ${C_DIM}$(( f0 + 1 ))-$(( f0 + f1 )) of $total files${C_RESET}"
        fi
        scrow_ui_buttons $((SCROW_TUI_ROWS - 4)) 0 "Back"
        scrow_ui_center_p "${C_HAIR}↑ ↓ scroll · Enter back · Esc back${C_RESET}"
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$scrow_ui_center_p_out"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            up)   (( cur > 0 )) && (( cur -= 1 )) ;;
            down) (( cur + 1 < n )) && cur+=1 ;;
            enter|esc|q|eof|none) return ;;
        esac
        (( cur < top )) && top=$cur
        (( cur >= top + h )) && top=$(( cur - h + 1 ))
    done
}

scrow_screen_uninstall() {
    scrow_ui_confirm "Uninstall SCROW" "Uninstall" "Cancel" 1 \
        "Removes SCROW and every file it manages from this system." \
        "SCROW-enabled services are disabled and install state is cleared." \
        "An automatic backup is created first, and existing backups are preserved." \
        "This cannot be undone — you can reinstall SCROW later and restore from a backup."
    local rc=$?
    (( rc == 2 || rc == 1 )) && return
    local ay="$SCROW_ASSUME_YES"
    SCROW_ASSUME_YES=1
    scrow_ui_op "Uninstall" scrow_engine_reset
    rc=$?
    SCROW_ASSUME_YES=$ay
    scrow_ui_result "Uninstall" "$([[ $rc -eq 0 ]] && echo ok || echo err)" --log "$SCROW_CURRENT_LOG" \
        "$([[ $rc -eq 0 ]] && echo "SCROW has been removed. Backups are preserved in: $(scrow_backup_dir)" || echo "Uninstall failed — check the log.")"
}

# -----------------------------------------------------------------------------
# Entry points
# -----------------------------------------------------------------------------
scrow_menu() {
    scrow_ui_enter
    trap 'scrow_ui_leave' EXIT
    local -i sel=0
    scrow_ui_status_compute
    while true; do
        scrow_frame_main "$sel"
        scrow_ui_render
        scrow_ui_key
        case "$SCROW_TUI_KEY" in
            up)   (( sel > 0 )) && (( sel -= 1 )) ;;
            down) (( sel < 7 )) && sel+=1 ;;
            home) sel=0 ;;
            end)  sel=7 ;;
            enter)
                case "${SCROW_UI_MAIN_ACTIONS[sel]}" in
                    full)       scrow_screen_install_full ;;
                    custom)     scrow_screen_install_custom ;;
                    components) scrow_screen_components ;;
                    update)     scrow_screen_update ;;
                    restore)    scrow_screen_restore ;;
                    reset)      scrow_screen_reset ;;
                    doctor)     scrow_screen_doctor ;;
                    uninstall)  scrow_screen_uninstall ;;
                esac
                scrow_ui_status_compute
                scrow_ui_size
                ;;
            esc|q|eof) break ;;
            none) : ;;
        esac
    done
    scrow_ui_leave
    trap - EXIT
}

scrow_dashboard() { scrow_menu; }

# --- analysis (used by the doctor screen) -------------------------------------
declare -a SCROW_AN_MODIFIED=() SCROW_AN_MISSING=() SCROW_AN_SYNC=() SCROW_AN_BROKEN=() SCROW_AN_REMOVED=()
declare -a SCROW_AN_NEW=() SCROW_AN_MISSING_DIRS=() SCROW_AN_MISSING_PKGS=() SCROW_AN_DISABLED_SVC=()

scrow_analyze() {
    SCROW_AN_MODIFIED=(); SCROW_AN_MISSING=(); SCROW_AN_SYNC=(); SCROW_AN_BROKEN=(); SCROW_AN_REMOVED=()
    SCROW_AN_NEW=(); SCROW_AN_MISSING_DIRS=(); SCROW_AN_MISSING_PKGS=(); SCROW_AN_DISABLED_SVC=()
    SCROW_AN_REPO_MISSING=0

    # Nothing installed → nothing to verify; no repository needed.
    if [[ ! -s "$SCROW_MANIFEST" ]] && [[ -z "$(scrow_state_components)" ]]; then
        SCROW_AN_MODIFIED_N=0; SCROW_AN_MISSING_N=0; SCROW_AN_SYNC_N=0; SCROW_AN_BROKEN_N=0; SCROW_AN_REMOVED_N=0
        SCROW_AN_NEW_N=0; SCROW_AN_MISSING_DIRS_N=0; SCROW_AN_MISSING_PKGS_N=0; SCROW_AN_DISABLED_SVC_N=0
        return 0
    fi

    # Doctor compares against the CURRENT repository state, so a fresh clone is
    # acquired — expected files, missing packages and disabled services all
    # come from it.
    if ! scrow_repo_guard; then
        SCROW_AN_REPO_MISSING=1
        SCROW_AN_MODIFIED_N=0; SCROW_AN_MISSING_N=0; SCROW_AN_SYNC_N=0; SCROW_AN_BROKEN_N=0; SCROW_AN_REMOVED_N=0
        SCROW_AN_NEW_N=0; SCROW_AN_MISSING_DIRS_N=0; SCROW_AN_MISSING_PKGS_N=0; SCROW_AN_DISABLED_SVC_N=0
        return 0
    fi
    scrow_manifest_index_load
    scrow_sha_cache_load
    scrow_target_sha_load
    local line src src_status t_status t
    local -i modified=0 missing=0 in_sync=0 broken=0 removed=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        scrow_tsv "$line"
        case "${SCROW_MF[2]}" in
            l)
                t="$(scrow_target "${SCROW_MF[0]}")"
                if [[ ! -L "$t" || "$(readlink "$t" 2>/dev/null)" != "${SCROW_MF[3]}" ]]; then
                    SCROW_AN_BROKEN+=("${SCROW_MF[0]}"); broken+=1
                fi
                ;;
            f)
                src="${SCROW_MF[3]#@}"
                [[ -z "$src" || "$src" == "${SCROW_MF[3]}" ]] && src="${SCROW_MF[0]}"
                scrow_sha_cache_get "$src"
                src_status="$SCROW_SHA_CACHE_RET"
                if [[ -z "$src_status" ]]; then
                    SCROW_AN_REMOVED+=("${SCROW_MF[0]}"); removed+=1
                    continue
                fi
                t="$(scrow_target "${SCROW_MF[0]}")"
                if [[ -L "$t" ]]; then
                    SCROW_AN_MODIFIED+=("${SCROW_MF[0]}"); modified+=1
                elif [[ ! -e "$t" ]]; then
                    SCROW_AN_MISSING+=("${SCROW_MF[0]}"); missing+=1
                else
                    scrow_target_sha_get "$t"
                    t_status="$SCROW_TARGET_SHA_RET"
                    if [[ "$t_status" == "$src_status" ]]; then
                        SCROW_AN_SYNC+=("${SCROW_MF[0]}"); in_sync+=1
                    else
                        SCROW_AN_MODIFIED+=("${SCROW_MF[0]}"); modified+=1
                    fi
                fi
                ;;
        esac
    done < <(scrow_manifest_lines)

    # --- current-repository state for installed components -------------------
    # Doctor inspects what the CURRENT repository declares for each installed
    # component — not just the files an older manifest happened to record — so
    # newly-added SCROW files, missing directories, missing packages and
    # disabled required services are all detected.
    local comp pkg svc st path full
    local -i newf=0 dirs=0 pkgs=0 svcs=0
    local -a installed=()
    for comp in $(scrow_owner_units); do
        [[ "$comp" == "default" ]] || scrow_component_exists "$comp" || continue
        installed+=("$comp")
        for pkg in $(scrow_component_packages "$comp") $(scrow_component_aur "$comp"); do
            scrow_config_pkg_skipped "$pkg" && continue
            scrow_pm_installed "$pkg" || { SCROW_AN_MISSING_PKGS+=("$comp: $pkg"); pkgs+=1; }
        done
        for path in $(scrow_component_paths "$comp"); do
            [[ ! -e "$SCROW_REPO/$path" && ! -L "$SCROW_REPO/$path" ]] && continue
            if [[ -d "$SCROW_REPO/$path" ]]; then
                t="$(scrow_target "$path")"
                [[ -d "$t" ]] || { SCROW_AN_MISSING_DIRS+=("$path"); dirs+=1; }
                while IFS= read -r full; do
                    [[ -n "$full" ]] || continue
                    [[ -n "${SCROW_MANIFEST_INDEX[$full]:-}" ]] && continue
                    t="$(scrow_target "$full")"
                    if [[ ! -e "$t" && ! -L "$t" ]]; then
                        SCROW_AN_MISSING+=("$full (new)") ; missing+=1
                    fi
                    SCROW_AN_NEW+=("$full"); newf+=1
                done < <(scrow_repo_files "$path")
            fi
        done
    done
    if [[ ${#installed[@]} -gt 0 ]]; then
        for svc in $(scrow_state_services); do
            [[ -n "$svc" ]] || continue
            if ! scrow_service_is_enabled "$svc"; then
                SCROW_AN_DISABLED_SVC+=("$svc"); svcs+=1
            fi
        done
    fi
    SCROW_AN_NEW_N=$newf
    SCROW_AN_MISSING_DIRS_N=$dirs
    SCROW_AN_MISSING_PKGS_N=$pkgs
    SCROW_AN_DISABLED_SVC_N=$svcs

    SCROW_AN_MODIFIED_N=$modified
    SCROW_AN_MISSING_N=$missing
    SCROW_AN_SYNC_N=$in_sync
    SCROW_AN_BROKEN_N=$broken
    SCROW_AN_REMOVED_N=$removed
}

# --- SCROW update (fresh repository + converge deployment) -------------------
scrow_engine_update() {
    echo
    echo "  ${C_ACCENT}SCROW Update${C_RESET}"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] update SCROW repository"
        return 0
    fi

    # The repository is acquired fresh from the network — the newest state by
    # construction — so there is no in-place pull or merge of a persistent copy.
    scrow_repo_guard || return 1
    echo "  ${C_OK}SCROW repository is up to date.${C_RESET}"

    # Refresh the installed engine bundle so future `scrow` runs use the new code.
    scrow_engine_install_bundle \
        || { echo "  ${C_ERR}✗ could not update the installed engine${C_RESET}"; return 1; }

    # Converge the installed components to the updated repository state:
    # deploy newly-added/changed files and re-apply post-install for the
    # components whose files changed.
    local -a comps=( $(scrow_owner_units) )
    if [[ ${#comps[@]} -eq 0 ]]; then
        return 0
    fi
    echo
    echo "  ${C_ACCENT}Converging installed components…${C_RESET}"
    scrow_manifest_index_load
    scrow_sha_cache_load
    scrow_build_synced_map
    local name path full t
    local -i failed=0 changed=0 prc
    declare -A updated_comps=()
    for name in "${comps[@]}"; do
        [[ "$name" == "default" ]] || scrow_component_exists "$name" || continue
        echo "  ${C_ACCENT}› ${name}${C_RESET}"
        local -i comp_changed=0
        for path in $(scrow_component_paths "$name"); do
            [[ ! -e "$SCROW_REPO/$path" && ! -L "$SCROW_REPO/$path" ]] && continue
            if [[ -d "$SCROW_REPO/$path" ]]; then
                while IFS= read -r full; do
                    [[ -n "$full" ]] || continue
                    [[ -n "${SCROW_SYNCED[$full]:-}" ]] && continue
                    scrow_backup_existing "$full" "$name"
                    scrow_deploy_path "$full" || failed=1
                    comp_changed=1
                    changed=1
                done < <(scrow_repo_files "$path")
            else
                [[ -n "${SCROW_SYNCED[$path]:-}" ]] && continue
                scrow_backup_existing "$path" "$name"
                scrow_deploy_path "$path" || failed=1
                comp_changed=1
                changed=1
            fi
        done
        if (( comp_changed == 1 )); then
            SCROW_POST_SERVICES=0
            scrow_component_post "$name"
            prc=$?
            if (( prc == 2 )); then
                echo "  ${C_WARN}  (skipped) optional post-install not enabled${C_RESET}"
            elif (( prc != 0 )); then
                echo "  ${C_ERR}  ✗ ${name} — post-install failed during update${C_RESET}"
                failed=1
            fi
        fi
    done
    scrow_manifest_rebuild "${comps[@]}"
    echo
    if (( failed != 0 )); then
        echo "  ${C_ERR}Update converged with errors — see the log.${C_RESET}"
        return 1
    fi
    if (( changed == 0 )); then
        echo "  ${C_OK}Installed configuration already matches the current SCROW state.${C_RESET}"
    else
        echo "  ${C_OK}Installed configuration updated to the current SCROW state.${C_RESET}"
    fi
    return 0
}
