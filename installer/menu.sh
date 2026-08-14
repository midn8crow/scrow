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

scrow_ui_spaces() { printf '%*s' "$1" ""; }

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
    local -i len
    len=$(scrow_ui_vislen "$text")
    local -i pad=$(( (w - len) / 2 ))
    (( pad < 0 )) && pad=0
    printf '%s%s' "$(scrow_ui_spaces $(( x0 + pad )))" "$text"
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
    local s="$1" ch
    local -i i=0 n=${#s} vis=0
    while (( i < n )); do
        ch="${s:i:1}"
        if [[ "$ch" == $'\033' ]]; then
            (( i++ ))
            while (( i < n )) && [[ "${s:i:1}" == '[' ]]; do (( i++ )); done
            while (( i < n )) && [[ "${s:i:1}" != 'm' ]]; do (( i++ )); done
            (( i < n )) && (( i++ ))
            continue
        fi
        vis+=1
        (( i++ ))
    done
    printf '%d' "$vis"
}

scrow_ui_center_p() {
    local text="$1"
    local -i plen=${2:-0}
    (( plen == 0 )) && plen=$(scrow_ui_vislen "$text")
    local -i pad=$(( (SCROW_TUI_COLS - plen) / 2 ))
    (( pad < 0 )) && pad=0
    printf '%s%s' "$(scrow_ui_spaces $pad)" "$text"
}

declare -a SCROW_TUI_WRAPPED=()
scrow_ui_wrap() {
    local text="$1" maxlen=$2 word out=""
    SCROW_TUI_WRAPPED=()
    for word in $text; do
        if [[ -z "$out" ]]; then
            out="$word"
        elif (( $(scrow_ui_vislen "$out") + 1 + $(scrow_ui_vislen "$word") <= maxlen )); then
            out="$out $word"
        else
            SCROW_TUI_WRAPPED+=("$out")
            out="$word"
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
    row="$(scrow_ui_spaces $pad)"
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
        (( i < n - 1 )) && row+="$(scrow_ui_spaces $gap)"
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
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}← → choose · Enter confirm · Esc cancel${C_RESET}")"
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
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "$footer")"
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
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}↑ ↓ scroll · q / Esc back${C_RESET}")"
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
    local -i pad=$(( width - $(scrow_ui_vislen "$head") ))
    (( pad < 1 )) && pad=1
    printf '%s%s' "$head" "$(scrow_ui_spaces $pad)"
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
        (( $(scrow_ui_vislen "$cand") <= avail )) && break
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
SCROW_UI_MAIN_BADGES=( "RECOMMENDED" "" "" "" "" "" "" "" )
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

scrow_ui_draw_item_str() {
    local -i item=$1 sel=$2 blockw=$3
    local lb="${SCROW_UI_MAIN_LABELS[item]}" bd="${SCROW_UI_MAIN_BADGES[item]}"
    local indent="  "
    (( item == sel )) && indent="› "
    local content="${indent}${lb}"
    local row
    if [[ -n "$bd" ]] && (( blockw - ${#content} - ${#bd} - 1 >= 0 )); then
        local -i gap=$(( blockw - ${#content} - ${#bd} - 1 ))
        (( gap < 1 )) && gap=1
        if (( item == sel )); then
            row="${C_SELBG}${C_ACCENT}${C_BOLD}${content}${C_RESET}$(scrow_ui_spaces $gap)${C_OK}${bd}${C_RESET}"
        else
            row="${C_DIM}${content}$(scrow_ui_spaces $gap)${C_HAIR}${bd}${C_RESET}"
        fi
    else
        local -i gap=$(( blockw - ${#content} ))
        (( gap < 1 )) && gap=1
        if (( item == sel )); then
            row="${C_SELBG}${C_ACCENT}${C_BOLD}${content}${C_RESET}$(scrow_ui_spaces $gap)"
        else
            row="${C_DIM}${content}$(scrow_ui_spaces $gap)${C_RESET}"
        fi
    fi
    printf '%s' "$row"
}

scrow_ui_draw_item() {
    local -i y=$1 item=$2 sel=$3 xoff=$4 blockw=$5
    scrow_ui_put "$y" "$(scrow_ui_spaces $xoff)$(scrow_ui_draw_item_str "$item" "$sel" "$blockw")"
}

# -----------------------------------------------------------------------------
# Framed panel (main menu component)
# -----------------------------------------------------------------------------
# The menu is drawn as a single cohesive teal-framed panel: border, embedded
# title, section headers with underlines, options, an inner divider and a
# description footer. All helpers are pure arithmetic/printf — no subprocesses.
scrow_ui_box_top() {
    local -i y=$1 x=$2 w=$3
    local title="$4"
    if [[ -n "$title" ]]; then
        local -i d=$(( w - ${#title} - 5 ))
        (( d < 1 )) && d=1
        scrow_ui_put "$y" "$(scrow_ui_spaces $x)${C_FRAME}┌─ ${C_RESET}${C_ACCENT}${C_BOLD}${title}${C_RESET}${C_FRAME} $(scrow_ui_dash $d)┐${C_RESET}"
    else
        scrow_ui_put "$y" "$(scrow_ui_spaces $x)${C_FRAME}┌$(scrow_ui_dash $(( w - 2 )))┐${C_RESET}"
    fi
}

scrow_ui_box_bottom() {
    local -i y=$1 x=$2 w=$3
    scrow_ui_put "$y" "$(scrow_ui_spaces $x)${C_FRAME}└$(scrow_ui_dash $(( w - 2 )))┘${C_RESET}"
}

scrow_ui_box_divider() {
    local -i y=$1 x=$2 w=$3
    scrow_ui_put "$y" "$(scrow_ui_spaces $x)${C_FRAME}│${C_RESET}${C_HAIR}$(scrow_ui_dash $(( w - 2 )))${C_RESET}${C_FRAME}│${C_RESET}"
}

scrow_ui_box_row() {
    local -i y=$1 x=$2 w=$3
    local content="$4"
    local -i clen
    clen=$(scrow_ui_vislen "$content")
    local -i pad=$(( w - 4 - clen ))
    (( pad < 0 )) && pad=0
    scrow_ui_put "$y" "$(scrow_ui_spaces $x)${C_FRAME}│ ${C_RESET}${content}$(scrow_ui_spaces $pad) ${C_FRAME}│${C_RESET}"
}

scrow_frame_main_panel() {
    local -i sel=$1
    local mode="$2"
    local -i cw=$SCROW_TUI_COLS
    local -i i k v line
    local -i colA=0 colB=0 gap=4 contentW=0

    if [[ "$mode" == "two" ]]; then
        for ((i=0; i<3; i++)); do
            v=$(( 2 + ${#SCROW_UI_MAIN_LABELS[i]} ))
            local bdA="${SCROW_UI_MAIN_BADGES[i]}"
            [[ -n "$bdA" ]] && v=$(( v + ${#bdA} + 1 ))
            (( v > colA )) && colA=$v
        done
        for ((i=3; i<8; i++)); do
            v=$(( 2 + ${#SCROW_UI_MAIN_LABELS[i]} ))
            (( v > colB )) && colB=$v
        done
        gap=$(( 8 + (cw - 76) / 6 ))
        (( gap > 12 )) && gap=12
        (( gap < 8 )) && gap=8
        contentW=$(( colA + gap + colB ))
    else
        for ((i=0; i<8; i++)); do
            v=$(( 2 + ${#SCROW_UI_MAIN_LABELS[i]} ))
            local bdS="${SCROW_UI_MAIN_BADGES[i]}"
            [[ -n "$bdS" ]] && v=$(( v + ${#bdS} + 1 ))
            (( v > contentW )) && contentW=$v
        done
        (( contentW > cw - 6 )) && contentW=$(( cw - 6 ))
    fi

    local -i grow=$(( (SCROW_TUI_ROWS - 24) / 6 ))
    if [[ "$mode" == "two" ]]; then
        (( grow > 5 )) && grow=5
    else
        (( grow > 3 )) && grow=3
    fi

    local -i boxW=$(( contentW + 4 ))
    local -i boxX=$(( (cw - boxW) / 2 ))
    (( boxX < 1 )) && boxX=1

    local -i padTop=$(( 1 + grow ))
    local -i padH=$grow
    local -i padB=$grow
    local -i padD=$grow
    local -i padFoot=$grow
    local -i gapAbove=$(( 1 + grow ))
    local -i top=$(( 5 + gapAbove ))

    local -i descw=$(( contentW - 2 ))
    (( descw < 20 )) && descw=20
    local -i maxLines=0 n
    for ((n=0; n<8; n++)); do
        scrow_ui_wrap "${SCROW_UI_MAIN_DESC[n]}" "$descw"
        (( ${#SCROW_TUI_WRAPPED[@]} > maxLines )) && maxLines=${#SCROW_TUI_WRAPPED[@]}
    done

    local -i noDescH panelH showDesc=0
    if [[ "$mode" == "two" ]]; then
        noDescH=$(( 10 + padTop + padH + padB ))
        panelH=$(( 11 + padTop + padH + padB + padD + padFoot + maxLines ))
    else
        noDescH=$(( 14 + padTop + padH + padFoot ))
        panelH=$(( 15 + padTop + padH + 2 * padFoot + padD + maxLines ))
    fi
    if (( panelH <= SCROW_TUI_ROWS - 4 - top )); then
        showDesc=1
    else
        panelH=$noDescH
    fi

    local -i y=$top
    scrow_ui_box_top "$y" "$boxX" "$boxW" "MAIN MENU"
    y+=1
    y+=padTop

    if [[ "$mode" == "two" ]]; then
        local -i hdgap=$(( colA + gap - 12 ))
        local -i hdrtail=$(( contentW - 12 - hdgap - 10 ))
        (( hdrtail < 0 )) && hdrtail=0
        scrow_ui_box_row "$y" "$boxX" "$boxW" \
            "${C_ACCENT}${C_BOLD}INSTALLATION${C_RESET}$(scrow_ui_spaces $hdgap)${C_ACCENT}${C_BOLD}MANAGEMENT${C_RESET}$(scrow_ui_spaces $hdrtail)"
        y+=1
        scrow_ui_box_row "$y" "$boxX" "$boxW" \
            "${C_HAIR}$(scrow_ui_dash 12)$(scrow_ui_spaces $hdgap)$(scrow_ui_dash 10)$(scrow_ui_spaces $hdrtail)${C_RESET}"
        y+=1
        y+=padH
        local itemA itemB
        for ((k=0; k<5; k++)); do
            if (( k < 3 )); then
                itemA="$(scrow_ui_draw_item_str "$k" "$sel" "$colA")"
            else
                itemA="$(scrow_ui_spaces $colA)"
            fi
            itemB="$(scrow_ui_draw_item_str $(( k + 3 )) "$sel" "$colB")"
            scrow_ui_box_row "$y" "$boxX" "$boxW" "${itemA}$(scrow_ui_spaces $gap)${itemB}"
            y+=1
        done
    else
        scrow_ui_box_row "$y" "$boxX" "$boxW" \
            "${C_ACCENT}${C_BOLD}INSTALLATION${C_RESET}$(scrow_ui_spaces $(( contentW - 12 )))"
        y+=1
        scrow_ui_box_row "$y" "$boxX" "$boxW" \
            "${C_HAIR}$(scrow_ui_dash 12)$(scrow_ui_spaces $(( contentW - 12 )))${C_RESET}"
        y+=1
        for ((i=0; i<3; i++)); do
            scrow_ui_box_row "$y" "$boxX" "$boxW" "$(scrow_ui_draw_item_str "$i" "$sel" "$contentW")"
            y+=1
        done
        y+=padH
        scrow_ui_box_row "$y" "$boxX" "$boxW" \
            "${C_ACCENT}${C_BOLD}MANAGEMENT${C_RESET}$(scrow_ui_spaces $(( contentW - 10 )))"
        y+=1
        scrow_ui_box_row "$y" "$boxX" "$boxW" \
            "${C_HAIR}$(scrow_ui_dash 10)$(scrow_ui_spaces $(( contentW - 10 )))${C_RESET}"
        y+=1
        for ((i=3; i<8; i++)); do
            scrow_ui_box_row "$y" "$boxX" "$boxW" "$(scrow_ui_draw_item_str "$i" "$sel" "$contentW")"
            y+=1
        done
    fi

    y+=padB
    if (( showDesc )); then
        scrow_ui_box_divider "$y" "$boxX" "$boxW"
        y+=1
        y+=padD
        scrow_ui_wrap "${SCROW_UI_MAIN_DESC[sel]}" "$descw"
        local -a dwrap=("${SCROW_TUI_WRAPPED[@]}")
        for ((line=0; line<maxLines; line++)); do
            local w="${dwrap[line]:-}"
            if [[ -n "$w" ]]; then
                scrow_ui_box_row "$y" "$boxX" "$boxW" "${C_DIM}${w}${C_RESET}"
            else
                scrow_ui_box_row "$y" "$boxX" "$boxW" ""
            fi
            y+=1
        done
        y+=padFoot
    fi
    scrow_ui_box_bottom "$y" "$boxX" "$boxW"

    local -i hairY=$(( SCROW_TUI_ROWS - 3 ))
    if (( hairY > y + 1 && hairY >= 5 )); then
        scrow_ui_hline "$hairY" "$C_FRAME"
    fi
}

scrow_frame_main_slim() {
    local -i sel=$1 tiny=$2
    local -i cw=$SCROW_TUI_COLS
    local -i blockw=0 i v
    for ((i=0; i<8; i++)); do
        v=$(( 2 + ${#SCROW_UI_MAIN_LABELS[i]} ))
        local bd="${SCROW_UI_MAIN_BADGES[i]}"
        [[ -n "$bd" ]] && v=$(( v + ${#bd} + 1 ))
        (( v > blockw )) && blockw=$v
    done
    local -i maxw=$(( cw - 4 ))
    (( blockw > maxw )) && blockw=$maxw
    local -i xoff=$(( (cw - blockw) / 2 ))
    (( xoff < 2 )) && xoff=2
    local -i sp=$(( xoff + 2 ))
    local -i menuH=10
    local -i y=4
    if (( tiny )); then
        for ((i=0; i<8; i++)); do
            scrow_ui_draw_item "$y" "$i" "$sel" "$xoff" "$blockw"
            y+=1
        done
        return
    fi
    local -i space2=$(( (SCROW_TUI_ROWS - 24) / 8 ))
    (( space2 > 2 )) && space2=2
    local -i top=$(( 5 + 1 + space2 ))
    (( top < 4 )) && top=4
    local -i maxTop=$(( SCROW_TUI_ROWS - 1 - menuH ))
    (( top > maxTop )) && top=$maxTop
    (( top < 4 )) && top=4
    y=$top
    scrow_ui_put "$y" "$(scrow_ui_spaces $sp)${C_ACCENT}${C_BOLD}INSTALLATION${C_RESET}"
    y+=1
    for ((i=0; i<3; i++)); do
        scrow_ui_draw_item "$y" "$i" "$sel" "$xoff" "$blockw"
        y+=1
    done
    y+=1
    scrow_ui_put "$y" "$(scrow_ui_spaces $sp)${C_ACCENT}${C_BOLD}MANAGEMENT${C_RESET}"
    y+=1
    for ((i=3; i<8; i++)); do
        scrow_ui_draw_item "$y" "$i" "$sel" "$xoff" "$blockw"
        y+=1
    done
    local -i lastY=$(( y - 1 ))
    local -i hairY=$(( SCROW_TUI_ROWS - 3 ))
    if (( hairY > lastY + 1 && hairY >= 5 )); then
        scrow_ui_hline "$hairY" "$C_FRAME"
    fi
}

scrow_frame_main() {
    local -i sel=$1
    scrow_ui_frame
    local -i cw=$SCROW_TUI_COLS
    local right="v${SCROW_VERSION}"
    local -i pad=$(( cw - 7 - ${#right} ))
    (( pad < 0 )) && pad=0
    scrow_ui_put 0 "  ${C_ACCENT}${C_BOLD}SCROW${C_RESET}$(scrow_ui_spaces $pad)${C_DIM}${right}${C_RESET}"
    scrow_ui_put 1 "  ${C_DIM}Arch Linux · Hyprland dotfiles manager${C_RESET}"
    scrow_ui_hline 2 "$C_HAIR"
    scrow_ui_put 3 "  ${SCROW_UI_STATUS_DOT}${SCROW_UI_STATUS_TEXT}${C_RESET}"

    local -i tiny=0
    (( SCROW_TUI_ROWS <= 14 )) && tiny=1
    local footer="↑ ↓ navigate · Enter select · Esc / q quit"
    (( cw < 50 )) && footer="↑ ↓ move · Enter · Esc quit"

    if (( ! tiny && SCROW_TUI_ROWS >= 24 && cw >= 76 )); then
        scrow_frame_main_panel "$sel" "two"
    elif (( ! tiny && SCROW_TUI_ROWS >= 24 && cw >= 48 )); then
        scrow_frame_main_panel "$sel" "one"
    else
        scrow_frame_main_slim "$sel" "$tiny"
    fi

    if (( SCROW_TUI_ROWS > 12 )); then
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}${footer}${C_RESET}")"
    fi
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
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}← → choose · Enter confirm · Esc back${C_RESET}")"
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
                scrow_ui_put "$y" "${C_SELBG}${C_ACCENT}${C_BOLD}${plain}$(scrow_ui_spaces $gpad)${C_RESET}"
            elif (( sel[i] == 1 )); then
                scrow_ui_put "$y" "${C_DIM}${marker}${C_ACCENT}${sym}${C_RESET} ${C_DIM}${name}  ${C_FAINT}${title}${C_RESET}"
            else
                scrow_ui_put "$y" "${C_DIM}${marker}${C_HAIR}${sym}${C_RESET} ${C_DIM}${name}  ${C_FAINT}${title}${C_RESET}"
            fi
            y+=1
        done
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}↑ ↓ navigate · Space toggle · Enter continue · Esc back${C_RESET}")"
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
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}← → choose · Enter confirm · Esc back${C_RESET}")"
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
                scrow_ui_put "$y" "${C_SELBG}${C_ACCENT}${C_BOLD}${marker}${sym_color}${sym_ch}${C_ACCENT}${C_BOLD} ${name}  ${title}$(scrow_ui_spaces $gpad)${C_RESET}"
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
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}↑ ↓ navigate · Enter manage · Esc back${C_RESET}")"
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
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}← → choose action · Enter run · Esc back${C_RESET}")"
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
    scrow_engine_update || return 1
    echo
    echo "  ${C_DIM}Applying updated files…${C_RESET}"
    scrow_engine_refresh
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
                scrow_ui_put "$y" "${C_SELBG}${C_ACCENT}${C_BOLD}${marker}${labels[i]}$(scrow_ui_spaces $gpad)${C_RESET}"
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
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}↑ ↓ navigate · Enter run · Esc back${C_RESET}")"
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
                scrow_ui_put "$y" "${C_SELBG}${C_ACCENT}${C_BOLD}${row}$(scrow_ui_spaces $gpad)${C_RESET}"
            else
                scrow_ui_put "$y" "${C_DIM}${row}${C_RESET}"
            fi
            y+=1
        done
        if (( n > h )); then
            scrow_ui_put $((SCROW_TUI_ROWS - 3)) "  ${C_DIM}$(( top + 1 ))-$(( top + h < n ? top + h : n )) of $n backups${C_RESET}"
        fi
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}↑ ↓ navigate · Enter restore · Esc back${C_RESET}")"
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
    scrow_ui_op "Reset" scrow_engine_repair
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
    local -i issues=$(( modified + missing + broken + removed ))
    local color chip
    if (( missing + broken + removed > 0 )); then
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
        local -i gap=$(( SCROW_TUI_COLS - $(scrow_ui_vislen "$title") - $(scrow_ui_vislen "$chipstr") - 2 ))
        (( gap < 1 )) && gap=1
        scrow_ui_put 1 "$title$(scrow_ui_spaces $gap)${chipstr}"
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
        scrow_ui_put "$y" "  $(scrow_ui_health_cell ◇ "$C_ACCENT" $removed "removed from repo" $cellw_full)"
        y+=2
        scrow_ui_hline "$y" "$C_HAIR"
        y+=1
        if (( issues > 0 )); then
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
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "$footer")"
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
    if (( ${#SCROW_AN_BROKEN[@]} > 0 )); then
        items+=("::Broken symlinks (${#SCROW_AN_BROKEN[@]})")
        for f in "${SCROW_AN_BROKEN[@]}"; do items+=("$f"); done
    fi
    if (( ${#SCROW_AN_REMOVED[@]} > 0 )); then
        items+=("::Removed from repository (${#SCROW_AN_REMOVED[@]})")
        for f in "${SCROW_AN_REMOVED[@]}"; do items+=("$f"); done
    fi
    local -i total=$(( ${#SCROW_AN_MODIFIED[@]} + ${#SCROW_AN_MISSING[@]} + ${#SCROW_AN_BROKEN[@]} + ${#SCROW_AN_REMOVED[@]} ))
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
        scrow_ui_put $((SCROW_TUI_ROWS - 1)) "$(scrow_ui_center_p "${C_HAIR}↑ ↓ scroll · Enter back · Esc back${C_RESET}")"
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

scrow_analyze() {
    SCROW_AN_MODIFIED=(); SCROW_AN_MISSING=(); SCROW_AN_SYNC=(); SCROW_AN_BROKEN=(); SCROW_AN_REMOVED=()
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
    SCROW_AN_MODIFIED_N=$modified
    SCROW_AN_MISSING_N=$missing
    SCROW_AN_SYNC_N=$in_sync
    SCROW_AN_BROKEN_N=$broken
    SCROW_AN_REMOVED_N=$removed
}

# --- SCROW update (pull latest repository) ------------------------------------
scrow_engine_update() {
    echo
    echo "  ${C_ACCENT}SCROW Update${C_RESET}"
    if [[ "$SCROW_DRY_RUN" == "1" ]]; then
        echo "  [dry-run] git pull --rebase --autostash"
        return 0
    fi
    if ! git -C "$SCROW_REPO" rev-parse --git-dir >/dev/null 2>&1; then
        echo "  ${C_WARN}SCROW repo is not a git clone — nothing to update.${C_RESET}"
        return 1
    fi
    git -C "$SCROW_REPO" pull --rebase --autostash || { echo "  ${C_WARN}Could not pull. Local changes may conflict — see the log.${C_RESET}"; return 1; }
    echo
    echo "  ${C_OK}SCROW repository is up to date.${C_RESET}"
}
