# shellcheck shell=bash
# SCROW — shared functions (sourced, not executed directly)

# ── Execution wrappers ────────────────────────────────────────────────────────

try() { "$@" || true; }

x() {
    local cmdstatus=0
    "$@" || cmdstatus=$?
    while [[ $cmdstatus -ne 0 ]]; do
        printf "${RED}[$0]: Command \"${GREEN}%s${RED}\" has failed.${RST}\n" "$*"
        printf "  r = Repeat (DEFAULT)  e = Exit  i = Ignore\n"
        local p; read -p " [R/e/i]: " p
        case "$p" in
            [iI]) printf "${BLUE}Ignoring error...${RST}\n"; cmdstatus=0; break ;;
            [eE]) printf "${BLUE}Exiting.${RST}\n"; exit 1 ;;
            *)    if "$@"; then cmdstatus=0; else cmdstatus=1; fi ;;
        esac
    done
    [[ $cmdstatus -eq 0 ]] && printf "${BLUE}[$0]: \"${GREEN}%s${BLUE}\" finished.${RST}\n" "$*"
    [[ $cmdstatus -ne 0 ]] && { printf "${RED}[$0]: \"${GREEN}%s${RED}\" failed. Exiting.${RST}\n" "$*"; exit 1; }
}

v() {
    printf "${CYAN}[$0]: Next command:${RST}\n${GREEN}%s${RST}\n" "$*"
    if $ask; then
        printf "  y = Yes  e = Exit  s = Skip  yesforall = Yes to all\n"
        local p; read -p "====> " p
        case "$p" in
            [eE]) exit ;;
            [sS]) printf "${YELLOW}Skipped: %s${RST}\n" "$*"; return ;;
            "yesforall") ask=false; x "$@" ;;
            *) x "$@" ;;
        esac
    else
        x "$@"
    fi
}

showfun() {
    printf "${BLUE}[$0]: Function \"$1\":${RST}\n"
    printf "${GREEN}"
    type -a "$1" 2>/dev/null || true
    printf "${RST}\n"
}

pause() {
    if $ask; then
        printf "${FAINT}${ITALIC}(Ctrl-C to abort, Enter to proceed)${RST}\n"
        read -r
    fi
}

# ── Sudo keepalive ────────────────────────────────────────────────────────────

SUDO_KEEPALIVE_PID=""

sudo_init_keepalive() {
    command -v sudo >/dev/null 2>&1 || return 0
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null && return 0
    printf "${CYAN}[$0]: Requesting sudo privileges...${RST}\n"
    sudo true || { printf "${RED}[$0]: Sudo failed. Aborting.${RST}\n"; exit 1; }
    (while true; do sleep 60; sudo true 2>/dev/null || exit 0; done) &
    SUDO_KEEPALIVE_PID=$!
}

sudo_stop_keepalive() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

# ── Prevent root execution ────────────────────────────────────────────────────

prevent_sudo_or_root() {
    if [[ $(whoami) == "root" ]]; then
        printf "${RED}[$0]: Do NOT run as root or with sudo. Aborting.${RST}\n"
        exit 1
    fi
}

# ── Backup helpers ────────────────────────────────────────────────────────────

backup_clashing_targets() {
    local source_dir="$1" target_dir="$2" backup_dir="$3"
    shift 3
    local -a ignored_list=("$@")
    local -A delk
    for del in "${ignored_list[@]}"; do delk["$del"]=1; done

    local -a clash_list=()
    local -A target_map
    for i in $(ls -A "$target_dir" 2>/dev/null); do target_map["$i"]=1; done
    for i in $(ls -A "$source_dir" 2>/dev/null); do
        [[ -n "${target_map[$i]}" && -z "${delk[$i]-}" ]] && clash_list+=("$i")
    done

    [[ ${#clash_list[@]} -eq 0 ]] && return 0

    mkdir -p "$backup_dir"
    if command -v rsync >/dev/null 2>&1; then
        local args_includes=()
        for i in "${clash_list[@]}"; do
            if [[ -d "$target_dir/$i" ]]; then
                args_includes+=(--include="/$i/" --include="/$i/**")
            else
                args_includes+=(--include="/$i")
            fi
        done
        args_includes+=(--exclude='*')
        rsync -av --progress "${args_includes[@]}" "$target_dir/" "$backup_dir/"
    else
        for i in "${clash_list[@]}"; do
            if [[ -d "$target_dir/$i" ]]; then
                mkdir -p "$backup_dir/$i"
                cp -a "$target_dir/$i"/* "$backup_dir/$i"/ 2>/dev/null || true
            elif [[ -f "$target_dir/$i" ]]; then
                cp -p "$target_dir/$i" "$backup_dir/$i"
            fi
        done
    fi
}

# ── Utility helpers ───────────────────────────────────────────────────────────

command_exists() { command -v "$1" >/dev/null 2>&1; }

sanitize_path() {
    local path="$1"
    path=$(echo "$path" | tr -d '\000-\037')
    case "$path" in
        ..|../*|*/../*|*/..) die "Invalid path: $path" ;;
    esac
    echo "$path"
}

files_differ() {
    [[ ! -f "$1" || ! -f "$2" ]] && return 0
    if command -v stat &>/dev/null; then
        local s1 s2
        s1=$(stat -c%s "$1" 2>/dev/null || stat -f%z "$1" 2>/dev/null)
        s2=$(stat -c%s "$2" 2>/dev/null || stat -f%z "$2" 2>/dev/null)
        [[ "$s1" != "$s2" ]] && return 0
    fi
    cmp -s "$1" "$2" && return 1 || return 0
}

check_disk_space() {
    local path="${1:-.}" required_mb="${2:-100}"
    command -v df &>/dev/null || return 0
    local avail_kb
    avail_kb=$(df -k "$path" | awk 'NR==2{print $4}')
    local avail_mb=$((avail_kb / 1024))
    [[ $avail_mb -lt $required_mb ]] && { printf "${YELLOW}Low disk space: ${avail_mb}MB available, ${required_mb}MB recommended${RST}\n"; return 1; }
    return 0
}

register_temp_file() { TEMP_FILES_TO_CLEANUP+=("$1"); }
cleanup_temp_files() {
    for f in "${TEMP_FILES_TO_CLEANUP[@]}"; do rm -f "$f" 2>/dev/null || true; done
    TEMP_FILES_TO_CLEANUP=()
}
trap cleanup_temp_files EXIT

dedup_and_sort_listfile() {
    [[ ! -f "$1" ]] && { echo "File not found: $1" >&2; return 2; }
    local tmp; tmp=$(mktemp)
    sort -u -- "$1" > "$tmp"
    mv -f -- "$tmp" "$2"
}
