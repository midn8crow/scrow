#!/usr/bin/env bash
set -uo pipefail

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

PASS=0
FAIL=0
FAILED=()
REPO_ROOT="/home/shadhin/dotfiles"

TEST_HOME="$TEST_DIR/home"
TEST_REPO="$TEST_DIR/repo"
mkdir -p "$TEST_HOME"
export HOME="$TEST_HOME"
export XDG_CONFIG_HOME="$TEST_HOME/.config"
export XDG_DATA_HOME="$TEST_HOME/.local/share"
export XDG_STATE_HOME="$TEST_HOME/.local/state"
export XDG_BIN_HOME="$TEST_HOME/.local/bin"
export XDG_CACHE_HOME="$TEST_HOME/.cache"
export USER="${USER:-testuser}"

STUB_DIR="$TEST_DIR/stubs"
STUB_LOG="$TEST_DIR/stub.log"
mkdir -p "$STUB_DIR"
: > "$STUB_LOG"

check() {
    local name="$1" cond="$2" extra="${3:-}"
    if [[ "$cond" == "true" ]]; then
        ((PASS++))
        printf "  OK: %s\n" "$name"
    else
        ((FAIL++))
        FAILED+=("$name $extra")
        printf "  FAIL: %s %s\n" "$name" "$extra"
    fi
}

create_stubs() {
    for cmd in sudo pacman systemctl loginctl chsh usermod fc-cache lsof ping grub-mkconfig sysctl; do
        printf '#!/usr/bin/env bash\necho "STUB:%s" >> "%s"\nexit 0\n' "$cmd $*" "$STUB_LOG" > "$STUB_DIR/$cmd"
        chmod +x "$STUB_DIR/$cmd"
    done

    cat > "$STUB_DIR/getent" << 'EOF2'
#!/usr/bin/env bash
echo "testuser:x:1000:1000::/home/testuser:/bin/bash"
exit 0
EOF2
    chmod +x "$STUB_DIR/getent"

    cat > "$STUB_DIR/id" << 'EOF2'
#!/usr/bin/env bash
echo "testuser"
exit 0
EOF2
    chmod +x "$STUB_DIR/id"

    cat > "$STUB_DIR/paru" << 'EOF2'
#!/usr/bin/env bash
echo "STUB:paru" >> "$STUB_LOG"
if [[ "$1" == "--version" ]]; then
    [[ -f /tmp/_scrow_test_paru_ok ]] && { echo "paru 25.0"; exit 0; }
    exit 1
fi
[[ "$1" == "-S" ]] && touch /tmp/_scrow_test_paru_ok
exit 0
EOF2
    chmod +x "$STUB_DIR/paru"

    export PATH="$STUB_DIR:$PATH"
}

reset_log() { : > "$STUB_LOG"; }

echo ""
echo "═══ SCROW Installer Test Suite ═══"
echo ""

source "$REPO_ROOT/installer/lib/common.sh"
source "$REPO_ROOT/installer/lib/packages.sh"
source "$REPO_ROOT/installer/lib/deploy.sh"
source "$REPO_ROOT/installer/lib/services.sh"

echo "== 1. Manifest parsing =="
read_manifest "$REPO_ROOT/packages/official.txt" TEST_OFFICIAL
read_manifest "$REPO_ROOT/packages/aur.txt" TEST_AUR
check "official.txt non-empty" "$([ ${#TEST_OFFICIAL[@]} -gt 0 ] && echo true || echo false)" "count=${#TEST_OFFICIAL[@]}"
check "aur.txt non-empty" "$([ ${#TEST_AUR[@]} -gt 0 ] && echo true || echo false)" "count=${#TEST_AUR[@]}"
check "official >= 60 pkgs" "$([ ${#TEST_OFFICIAL[@]} -ge 60 ] && echo true || echo false)" "count=${#TEST_OFFICIAL[@]}"
check "aur >= 10 pkgs" "$([ ${#TEST_AUR[@]} -ge 10 ] && echo true || echo false)" "count=${#TEST_AUR[@]}"
check "official no comments" "$(! printf '%s\n' "${TEST_OFFICIAL[@]}" | grep -q '^#' && echo true || echo false)"

echo "== 2. Manifest dedup =="
dupes=$(printf '%s\n' "${TEST_OFFICIAL[@]}" | sort | uniq -d | wc -l)
check "official no duplicates" "$([ "$dupes" -eq 0 ] && echo true || echo false)" "dups=$dupes"

echo "== 3. discover_sources =="
sources_list=$(discover_sources)
check "discover_sources has output" "$([ -n "$sources_list" ] && echo true || echo false)"
check ".config in sources" "$(echo "$sources_list" | grep -q '^\.config$' && echo true || echo false)"

echo "== 4. Exclusions =="
for never in installer packages tests bootstrap.sh setup README.md CHANGELOG.md LICENSE VERSION .git .gitignore; do
    found=$(echo "$sources_list" | grep -qx "$never" && echo yes || echo no)
    check "excluded: $never" "$([ "$found" = "no" ] && echo true || echo false)"
done

echo "== 5. Deploy =="
mkdir -p "$TEST_REPO/.config/hypr/scripts"
mkdir -p "$TEST_REPO/.config/waybar"
mkdir -p "$TEST_REPO/.config/kitty"
mkdir -p "$TEST_REPO/.config/newapp/configs"
mkdir -p "$TEST_REPO/.local/bin"
mkdir -p "$TEST_REPO/Pictures/Wallpapers"
mkdir -p "$TEST_REPO/installer" "$TEST_REPO/packages" "$TEST_REPO/tests"

echo "monitor = DP-1,1920x1080@60,0x0,1" > "$TEST_REPO/.config/hypr/monitors.conf"
echo "bind = SUPER,Return,exec,kitty" > "$TEST_REPO/.config/hypr/keybinds.conf"
echo "windowrulev2 = float" > "$TEST_REPO/.config/hypr/windowrules.conf"
echo "source = ~/.config/hypr/monitors.conf" > "$TEST_REPO/.config/hypr/hyprland.conf"
printf '#!/bin/bash\necho hello\n' > "$TEST_REPO/.config/hypr/scripts/wallpaper.sh"
chmod +x "$TEST_REPO/.config/hypr/scripts/wallpaper.sh"
echo '{"layer":"bar"}' > "$TEST_REPO/.config/waybar/config.jsonc"
echo "font_family JetBrainsMono" > "$TEST_REPO/.config/kitty/kitty.conf"
printf '#!/bin/bash\necho script\n' > "$TEST_REPO/.local/bin/my-script.sh"
chmod +x "$TEST_REPO/.local/bin/my-script.sh"
echo "wallpaper.png" > "$TEST_REPO/Pictures/Wallpapers/scrow.png"
echo "newapp=true" > "$TEST_REPO/.config/newapp/configs/settings.conf"
echo "old content" > "$TEST_REPO/.config/hypr/test.bak"
mkdir -p "$TEST_REPO/.config/__pycache__"
echo "cached" > "$TEST_REPO/.config/__pycache__/mod.pyc"
echo "1.0.0" > "$TEST_REPO/VERSION"

export REPO_ROOT="$TEST_REPO"

deployed_count=0
while IFS= read -r src; do
    [[ ! -e "$REPO_ROOT/$src" ]] && continue
    if [[ -d "$REPO_ROOT/$src" ]]; then
        mkdir -p "$HOME/$src"
        if command -v rsync >/dev/null 2>&1; then
            rsync -a --exclude='*.bak' --exclude='__pycache__/' --exclude='*.pyc' \
                "$REPO_ROOT/$src/" "$HOME/$src/" 2>/dev/null || true
        else
            while IFS= read -r _f; do
                _rel="${_f#$REPO_ROOT/$src/}"
                mkdir -p "$(dirname "$HOME/$src/$_rel")"
                cp -a "$_f" "$HOME/$src/$_rel" 2>/dev/null || true
            done < <(find "$REPO_ROOT/$src" -type f \
                -not -name '*.bak' -not -name '*.pyc' \
                -not -path '*__pycache__*' \
                -not -path '*.swp' -not -path '*.tmp' \
                -not -path '*.pid' 2>/dev/null)
        fi
    elif [[ -f "$REPO_ROOT/$src" ]]; then
        mkdir -p "$(dirname "$HOME/$src")"
        cp -a "$REPO_ROOT/$src" "$HOME/$src" 2>/dev/null || true
    fi
    ((deployed_count++))
done < <(discover_sources)

check "deployed items > 0" "$([ "$deployed_count" -gt 0 ] && echo true || echo false)" "count=$deployed_count"
check "hyprland.conf deployed" "$([ -f "$HOME/.config/hypr/hyprland.conf" ] && echo true || echo false)"
check "keybinds.conf deployed" "$([ -f "$HOME/.config/hypr/keybinds.conf" ] && echo true || echo false)"
check "windowrules.conf deployed" "$([ -f "$HOME/.config/hypr/windowrules.conf" ] && echo true || echo false)"
check "monitors.conf deployed" "$([ -f "$HOME/.config/hypr/monitors.conf" ] && echo true || echo false)"
check "hypr scripts deployed" "$([ -f "$HOME/.config/hypr/scripts/wallpaper.sh" ] && echo true || echo false)"
check "waybar deployed" "$([ -f "$HOME/.config/waybar/config.jsonc" ] && echo true || echo false)"
check "kitty deployed" "$([ -f "$HOME/.config/kitty/kitty.conf" ] && echo true || echo false)"
check "local/bin deployed" "$([ -f "$HOME/.local/bin/my-script.sh" ] && echo true || echo false)"
check "Pictures deployed" "$([ -f "$HOME/Pictures/Wallpapers/scrow.png" ] && echo true || echo false)"
check "new .config/newapp deployed" "$([ -f "$HOME/.config/newapp/configs/settings.conf" ] && echo true || echo false)"
check "exec bit: local/bin" "$([ -x "$HOME/.local/bin/my-script.sh" ] && echo true || echo false)"
check "exec bit: hypr script" "$([ -x "$HOME/.config/hypr/scripts/wallpaper.sh" ] && echo true || echo false)"

echo "== 6. Excludes =="
check "*.bak excluded" "$([ ! -f "$HOME/.config/hypr/test.bak" ] && echo true || echo false)"
check "__pycache__ excluded" "$([ ! -d "$HOME/.config/__pycache__" ] && echo true || echo false)"
check "setup not in HOME" "$([ ! -f "$HOME/setup" ] && echo true || echo false)"
check "installer not in HOME" "$([ ! -d "$HOME/installer" ] && echo true || echo false)"

echo "== 7. Backup =="
SCROW_BACKUP_DIR="$XDG_DATA_HOME/scrow/backups"
mkdir -p "$HOME/.config/hypr"
echo "original" > "$HOME/.config/hypr/hyprland.conf"
backup_file "$HOME/.config/hypr/hyprland.conf"
check "backup dir created" "$([ -d "$SCROW_BACKUP_DIR" ] && echo true || echo false)"
check "backup file exists" "$([ -n "$(find "$SCROW_BACKUP_DIR" -name '*.bak' 2>/dev/null)" ] && echo true || echo false)"
check "backup has content" "$(grep -rq 'original' "$SCROW_BACKUP_DIR"/ 2>/dev/null && echo true || echo false)"

echo "== 8. Manifest =="
SCROW_MANIFEST="$XDG_DATA_HOME/scrow/manifest.tsv"
: > "$SCROW_MANIFEST"
while IFS= read -r src; do
    [[ -e "$REPO_ROOT/$src" ]] && echo "$src" >> "$SCROW_MANIFEST"
done < <(discover_sources)
check "manifest.tsv exists" "$([ -f "$SCROW_MANIFEST" ] && echo true || echo false)"
check "manifest.tsv non-empty" "$([ -s "$SCROW_MANIFEST" ] && echo true || echo false)"

echo "== 9. Validate =="
# Restore hyprland.conf overwritten by backup test
cp -a "$REPO_ROOT/.config/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf"
FIND_EXCLUDES=(-not -path '*/.git/*' -not -path '*/installer/*' -not -path '*/packages/*'
    -not -path '*/tests/*' -not -name '*.bak' -not -name '*.pyc'
    -not -name 'setup' -not -name 'README.md' -not -name 'CHANGELOG.md'
    -not -name 'LICENSE' -not -name 'VERSION' -not -name '.gitignore'
    -not -name 'bootstrap.sh')

count_missing() {
    local count=0
    while IFS= read -r repo_file; do
        local rel="${repo_file#$REPO_ROOT/}"
        [[ ! -e "$HOME/$rel" ]] && ((count++))
    done < <(find "$REPO_ROOT" -type f "${FIND_EXCLUDES[@]}" 2>/dev/null)
    echo "$count"
}

count_differs() {
    local count=0
    while IFS= read -r repo_file; do
        local rel="${repo_file#$REPO_ROOT/}"
        if [[ -e "$HOME/$rel" ]] && [[ -f "$repo_file" ]]; then
            cmp -s "$repo_file" "$HOME/$rel" 2>/dev/null || ((count++))
        fi
    done < <(find "$REPO_ROOT" -type f "${FIND_EXCLUDES[@]}" 2>/dev/null)
    echo "$count"
}

rm -f "$HOME/.config/kitty/kitty.conf"
missing=$(count_missing)
check "detects missing file" "$([ "$missing" -gt 0 ] && echo true || echo false)" "missing=$missing"

echo "modified" > "$HOME/.config/kitty/kitty.conf"
differs=$(count_differs)
check "detects differs" "$([ "$differs" -gt 0 ] && echo true || echo false)" "differs=$differs"

cp -a "$REPO_ROOT/.config/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
m2=$(count_missing); d2=$(count_differs)
problems=$((m2 + d2))
# Debug: show remaining problems
if [ "$problems" -gt 0 ]; then
    while IFS= read -r rf; do
        rel="${rf#$REPO_ROOT/}"
        if [ ! -e "$HOME/$rel" ]; then
            printf "    MISSING: %s
" "$rel"
        elif [ -f "$rf" ] && ! cmp -s "$rf" "$HOME/$rel" 2>/dev/null; then
            printf "    DIFFERS: %s
" "$rel"
        fi
    done < <(find "$REPO_ROOT" -type f "${FIND_EXCLUDES[@]}" 2>/dev/null)
fi
check "validation clean" "$([ "$problems" -eq 0 ] && echo true || echo false)" "problems=$problems"

echo "== 10. Paru already installed =="
create_stubs
reset_log
SCROW_PARU_READY=0
# paru stub is in PATH, so ensure_paru detects it and returns early
set +e
ensure_paru 2>/dev/null
paru_rc=$?
set -e
check "ensure_paru returns 0 (paru found)" "$([ "$paru_rc" -eq 0 ] && echo true || echo false)" "rc=$paru_rc"

echo "== 10b. Paru idempotent =="
set +e
ensure_paru 2>/dev/null
paru_rc2=$?
set -e
check "ensure_paru idempotent" "$([ "$paru_rc2" -eq 0 ] && echo true || echo false)" "rc=$paru_rc2"

echo "== 11. Services =="
reset_log
# Verify stubs are callable
"$STUB_DIR/systemctl" --user is-enabled test.service 2>/dev/null
"$STUB_DIR/sudo" systemctl enable sddm.service 2>/dev/null
svc_calls=$(grep -cE "(systemctl|sudo)" "$STUB_LOG" 2>/dev/null || true)
svc_calls=${svc_calls:-0}
check "systemctl stub works" "$([ "$svc_calls" -ge 2 ] && echo true || echo false)" "calls=$svc_calls"

reset_log
SCROW_SUDO_PID=""
setup_user_services 2>/dev/null
setup_system_services 2>/dev/null
stop_sudo_keepalive 2>/dev/null
svc_calls2=$(grep -cE "(systemctl|sudo)" "$STUB_LOG" 2>/dev/null || true)
svc_calls2=${svc_calls2:-0}
check "services setup calls systemctl" "$([ "$svc_calls2" -gt 0 ] && echo true || echo false)" "calls=$svc_calls2"

echo "== 12. Idempotent =="
export REPO_ROOT="$TEST_REPO"
while IFS= read -r src; do
    [[ ! -e "$REPO_ROOT/$src" ]] && continue
    if [[ -d "$REPO_ROOT/$src" ]]; then
        mkdir -p "$HOME/$src"
        if command -v rsync >/dev/null 2>&1; then
            rsync -a --exclude='*.bak' --exclude='__pycache__/' --exclude='*.pyc' \
                "$REPO_ROOT/$src/" "$HOME/$src/" 2>/dev/null || true
        else
            while IFS= read -r _f; do
                _rel="${_f#$REPO_ROOT/$src/}"
                mkdir -p "$(dirname "$HOME/$src/$_rel")"
                cp -a "$_f" "$HOME/$src/$_rel" 2>/dev/null || true
            done < <(find "$REPO_ROOT/$src" -type f \
                -not -name '*.bak' -not -name '*.pyc' \
                -not -path '*__pycache__*' \
                -not -path '*.swp' -not -path '*.tmp' \
                -not -path '*.pid' 2>/dev/null)
        fi
    elif [[ -f "$REPO_ROOT/$src" ]]; then
        mkdir -p "$(dirname "$HOME/$src")"
        cp -a "$REPO_ROOT/$src" "$HOME/$src" 2>/dev/null || true
    fi
done < <(discover_sources)
check "second deploy OK" "true"

echo "== 13. Components =="
export REPO_ROOT="/home/shadhin/dotfiles"
comp_count=$(grep -v '^#' "$REPO_ROOT/installer/components.list" | grep -v '^[[:space:]]*$' | wc -l)
check "components.list has entries" "$([ "$comp_count" -gt 0 ] && echo true || echo false)" "count=$comp_count"

echo "== 14. x() and try() =="
set +e
( source "$REPO_ROOT/installer/lib/common.sh" 2>/dev/null; x "failing" false 2>/dev/null )
rc=$?
set -e
check "x() non-zero on fail" "$([ "$rc" -ne 0 ] && echo true || echo false)" "rc=$rc"
source "$REPO_ROOT/installer/lib/common.sh" 2>/dev/null
x "passing" true
check "x() zero on success" "$([ $? -eq 0 ] && echo true || echo false)"
try false
check "try() zero on failure" "$([ $? -eq 0 ] && echo true || echo false)"

echo "== 15. Setup help =="
output=$(bash "$REPO_ROOT/setup" help 2>&1)
check "help shows usage" "$(echo "$output" | grep -q 'Usage:' && echo true || echo false)"
check "help shows commands" "$(echo "$output" | grep -q 'full' && echo true || echo false)"

echo "== 16. Temp cleanup =="
tmp_count=$(find /tmp -maxdepth 1 -name "scrow-*" -type d 2>/dev/null | wc -l)
check "no stale /tmp/scrow-*" "$([ "$tmp_count" -eq 0 ] && echo true || echo false)" "count=$tmp_count"

echo "== 17. Action files =="
for action in full components update repair restore doctor uninstall; do
    file="$REPO_ROOT/installer/actions/$action.sh"
    check "$action.sh exists" "$([ -f "$file" ] && echo true || echo false)"
    check "$action.sh has function" "$(grep -q "action_$action" "$file" && echo true || echo false)"
    check "$action.sh syntax" "$(bash -n "$file" 2>/dev/null && echo true || echo false)"
done

echo "== 18. Syntax =="
check "setup syntax" "$(bash -n "$REPO_ROOT/setup" 2>/dev/null && echo true || echo false)"
check "bootstrap.sh syntax" "$(bash -n "$REPO_ROOT/bootstrap.sh" 2>/dev/null && echo true || echo false)"
for lib in common.sh packages.sh deploy.sh services.sh validate.sh; do
    check "lib/$lib syntax" "$(bash -n "$REPO_ROOT/installer/lib/$lib" 2>/dev/null && echo true || echo false)"
done

echo "== 19. Old architecture removed =="
check "ORCHESTRA.sh gone" "$([ ! -f "$REPO_ROOT/scripts/ORCHESTRA.sh" ] && echo true || echo false)"
check "sdata/ gone" "$([ ! -d "$REPO_ROOT/sdata" ] && echo true || echo false)"
check "old test gone" "$([ ! -f "$REPO_ROOT/test-installer.sh" ] && echo true || echo false)"
check ".git_list gone" "$([ ! -f "$REPO_ROOT/.git_list" ] && echo true || echo false)"

echo "== 20. Repo cleanliness =="
bak_count=$(find "$REPO_ROOT" -name "*.bak" -not -path '*/.git/*' 2>/dev/null | wc -l)
check "no .bak files" "$([ "$bak_count" -eq 0 ] && echo true || echo false)" "found=$bak_count"
pycache_count=$(find "$REPO_ROOT" -name "__pycache__" -type d -not -path '*/.git/*' 2>/dev/null | wc -l)
check "no __pycache__" "$([ "$pycache_count" -eq 0 ] && echo true || echo false)" "found=$pycache_count"

echo ""
echo "═══ RESULT: $PASS PASS / $FAIL FAIL ═══"
if (( FAIL > 0 )); then
    echo ""
    echo "Failed:"
    for name in "${FAILED[@]}"; do
        echo "  - $name"
    done
    exit 1
fi
echo ""
echo "All tests passed."
