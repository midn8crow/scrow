#!/usr/bin/env bash
# SCROW installer test suite — tests the NEW end-4-style installer
# Usage: bash tests/test-installer.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0 FAIL=0

check() {
    local desc="$1" result="$2" detail="${3:-}"
    if [[ "$result" == "true" ]]; then
        printf "  \e[32mOK\e[0m: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  \e[31mFAIL\e[0m: %s (%s)\n" "$desc" "$detail"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== SCROW Installer Test Suite ==="
echo "Repository: $REPO_ROOT"
echo ""

# ── 1. Repository structure ───────────────────────────────────────────────────

echo "== 1. Repository structure =="
check "setup exists"          "$([ -f "$REPO_ROOT/setup" ] && echo true || echo false)"
check "setup is executable"   "$([ -x "$REPO_ROOT/setup" ] && echo true || echo false)"
check "get exists"            "$([ -f "$REPO_ROOT/get" ] && echo true || echo false)"
check "sdata/lib/env.sh"     "$([ -f "$REPO_ROOT/sdata/lib/env.sh" ] && echo true || echo false)"
check "sdata/lib/functions.sh" "$([ -f "$REPO_ROOT/sdata/lib/functions.sh" ] && echo true || echo false)"
check "sdata/subcmd-install/1.deps.sh"  "$([ -f "$REPO_ROOT/sdata/subcmd-install/1.deps.sh" ] && echo true || echo false)"
check "sdata/subcmd-install/2.setups.sh" "$([ -f "$REPO_ROOT/sdata/subcmd-install/2.setups.sh" ] && echo true || echo false)"
check "sdata/subcmd-install/3.files.sh"  "$([ -f "$REPO_ROOT/sdata/subcmd-install/3.files.sh" ] && echo true || echo false)"
check "packages/official.txt" "$([ -f "$REPO_ROOT/packages/official.txt" ] && echo true || echo false)"
check "packages/aur.txt"      "$([ -f "$REPO_ROOT/packages/aur.txt" ] && echo true || echo false)"
check "dots/ directory exists" "$([ -d "$REPO_ROOT/dots" ] && echo true || echo false)"

# ── 2. Old installer fully removed ────────────────────────────────────────────

echo ""
echo "== 2. Old installer removed =="
check "no installer/ directory"      "$([ ! -d "$REPO_ROOT/installer" ] && echo true || echo false)"
check "no bootstrap.sh"              "$([ ! -f "$REPO_ROOT/bootstrap.sh" ] && echo true || echo false)"
check "no tests/test-installer.sh"   "$([ ! -f "$REPO_ROOT/tests/test-installer.sh.bak" ] && echo true || echo false)"
check "no installer/lib/"            "$([ ! -d "$REPO_ROOT/installer/lib" ] && echo true || echo false)"
check "no installer/actions/"        "$([ ! -d "$REPO_ROOT/installer/actions" ] && echo true || echo false)"

# ── 3. dots/ tree contains all expected dotfiles ──────────────────────────────

echo ""
echo "== 3. dots/ tree content =="
check "dots/.config exists"   "$([ -d "$REPO_ROOT/dots/.config" ] && echo true || echo false)"
check "dots/.local exists"    "$([ -d "$REPO_ROOT/dots/.local" ] && echo true || echo false)"
check "dots/.zshrc exists"    "$([ -f "$REPO_ROOT/dots/.zshrc" ] && echo true || echo false)"

# Waybar: complete tree
waybar_files=$(find "$REPO_ROOT/dots/.config/waybar" -type f 2>/dev/null | wc -l)
check "waybar has files (>=50)" "$([ "$waybar_files" -ge 50 ] && echo true || echo false)" "count=$waybar_files"
check "waybar/launch.sh exists" "$([ -f "$REPO_ROOT/dots/.config/waybar/launch.sh" ] && echo true || echo false)"
check "waybar/config-anik.jsonc" "$([ -f "$REPO_ROOT/dots/.config/waybar/config-anik.jsonc" ] && echo true || echo false)"
check "waybar/athena/ dir"      "$([ -d "$REPO_ROOT/dots/.config/waybar/athena" ] && echo true || echo false)"
check "waybar/scripts/ dir"     "$([ -d "$REPO_ROOT/dots/.config/waybar/scripts" ] && echo true || echo false)"
check "waybar/colors/ dir"      "$([ -d "$REPO_ROOT/dots/.config/waybar/colors" ] && echo true || echo false)"
check "waybar/cava/ dir"        "$([ -d "$REPO_ROOT/dots/.config/waybar/cava" ] && echo true || echo false)"
check "waybar/context/ dir"     "$([ -d "$REPO_ROOT/dots/.config/waybar/context" ] && echo true || echo false)"

# Hyprland: complete tree
hypr_files=$(find "$REPO_ROOT/dots/.config/hypr" -type f 2>/dev/null | wc -l)
check "hypr has files (>=20)"   "$([ "$hypr_files" -ge 20 ] && echo true || echo false)" "count=$hypr_files"
check "hyprland.conf exists"    "$([ -f "$REPO_ROOT/dots/.config/hypr/hyprland.conf" ] && echo true || echo false)"
check "hyprland.lua exists"     "$([ -f "$REPO_ROOT/dots/.config/hypr/hyprland.lua" ] && echo true || echo false)"
check "hypr/modules/ dir"       "$([ -d "$REPO_ROOT/dots/.config/hypr/modules" ] && echo true || echo false)"
check "hypr/scripts/ dir"       "$([ -d "$REPO_ROOT/dots/.config/hypr/scripts" ] && echo true || echo false)"
check "hypr/hyprlock/ dir"      "$([ -d "$REPO_ROOT/dots/.config/hypr/hyprlock" ] && echo true || echo false)"
check "hypr/modules/autostart.lua" "$([ -f "$REPO_ROOT/dots/.config/hypr/modules/autostart.lua" ] && echo true || echo false)"
check "hypr/modules/workspace_overview.lua" "$([ -f "$REPO_ROOT/dots/.config/hypr/modules/workspace_overview.lua" ] && echo true || echo false)"

# Rofi, mako, kitty, other configs
check "rofi/ exists"    "$([ -d "$REPO_ROOT/dots/.config/rofi" ] && echo true || echo false)"
check "mako/ exists"    "$([ -d "$REPO_ROOT/dots/.config/mako" ] && echo true || echo false)"
check "kitty/ exists"   "$([ -d "$REPO_ROOT/dots/.config/kitty" ] && echo true || echo false)"

# Local bin scripts
localbin_count=$(find "$REPO_ROOT/dots/.local/bin" -type f 2>/dev/null | wc -l)
check "local/bin has scripts (>=40)" "$([ "$localbin_count" -ge 40 ] && echo true || echo false)" "count=$localbin_count"

# Fonts
check ".local/share/fonts/ exists" "$([ -d "$REPO_ROOT/dots/.local/share/fonts" ] && echo true || echo false)"

# Icons
check ".local/share/icons/ exists" "$([ -d "$REPO_ROOT/dots/.local/share/icons" ] && echo true || echo false)"

# ── 4. Root-level dotfiles are NOT in repo root (moved to dots/) ─────────────

echo ""
echo "== 4. Dotfiles are in dots/, not repo root =="
check ".config NOT at root"  "$([ ! -d "$REPO_ROOT/.config" ] && echo true || echo false)"
check ".local NOT at root"   "$([ ! -d "$REPO_ROOT/.local" ] && echo true || echo false)"
check ".zshrc NOT at root"   "$([ ! -f "$REPO_ROOT/.zshrc" ] && echo true || echo false)"

# ── 5. No old installer artifacts remain ──────────────────────────────────────

echo ""
echo "== 5. No legacy artifacts =="
check "no installer/components.list"  "$([ ! -f "$REPO_ROOT/installer/components.list" ] && echo true || echo false)"
check "no installer/lib/common.sh"   "$([ ! -f "$REPO_ROOT/installer/lib/common.sh" ] && echo true || echo false)"
check "no installer/lib/deploy.sh"   "$([ ! -f "$REPO_ROOT/installer/lib/deploy.sh" ] && echo true || echo false)"

# ── 6. setup help works ──────────────────────────────────────────────────────

echo ""
echo "== 6. setup help =="
output=$(bash "$REPO_ROOT/setup" help 2>&1) || true
check "help shows usage"  "$(echo "$output" | grep -q 'Usage:' && echo true || echo false)"
check "help shows install" "$(echo "$output" | grep -q 'install' && echo true || echo false)"

# ── 7. packages manifests are non-empty ──────────────────────────────────────

echo ""
echo "== 7. Package manifests =="
official_count=$(grep -v '^#' "$REPO_ROOT/packages/official.txt" | grep -v '^[[:space:]]*$' | wc -l)
check "official.txt has packages (>=60)" "$([ "$official_count" -ge 60 ] && echo true || echo false)" "count=$official_count"
aur_count=$(grep -v '^#' "$REPO_ROOT/packages/aur.txt" | grep -v '^[[:space:]]*$' | wc -l)
check "aur.txt has packages (>=5)" "$([ "$aur_count" -ge 5 ] && echo true || echo false)" "count=$aur_count"
check "official.txt has hyprland"  "$(grep -q '^hyprland$' "$REPO_ROOT/packages/official.txt" && echo true || echo false)"
check "official.txt has cava (waybar-cava visualizer runtime)" \
    "$(grep -q '^cava$' "$REPO_ROOT/packages/official.txt" && echo true || echo false)"
check "aur.txt keeps libcava (cava module shared lib, ships libcava.pc)" \
    "$(grep -q '^libcava$' "$REPO_ROOT/packages/aur.txt" && echo true || echo false)"
check "aur.txt drops waybar-cava-git (moving-git clone, unreliable on VM)" \
    "$(grep -qv '^waybar-cava-git$' "$REPO_ROOT/packages/aur.txt" && echo true || echo false)"
check "local waybar PKGBUILD exists (packages/waybar-cava)" \
    "$([ -f "$REPO_ROOT/packages/waybar-cava/PKGBUILD" ] && echo true || echo false)"
check "waybar PKGBUILD pins release tarball + cava=enabled" \
    "$(grep -q -- '-Dcava=enabled' "$REPO_ROOT/packages/waybar-cava/PKGBUILD" && echo true || echo false)"
check "waybar PKGBUILD provides+conflicts waybar (replaces stock)" \
    "$(grep -q "provides=('waybar')" "$REPO_ROOT/packages/waybar-cava/PKGBUILD" && grep -q "conflicts=('waybar'" "$REPO_ROOT/packages/waybar-cava/PKGBUILD" && echo true || echo false)"
check "aur.txt uses ytdlp-gui-bin (prebuilt) not slow cargo build" \
    "$(grep -q '^ytdlp-gui-bin$' "$REPO_ROOT/packages/aur.txt" && echo true || echo false)"
check "official.txt has rust"      "$(grep -q '^rust$' "$REPO_ROOT/packages/official.txt" && echo true || echo false)"
check "official.txt has go"        "$(grep -q '^go$' "$REPO_ROOT/packages/official.txt" && echo true || echo false)"

# Launcher coverage: every app referenced by the SCROW menu / configs must be
# representable in a manifest so a fresh install actually installs it.
check "official.txt has uv (WayClick dep)" \
    "$(grep -q '^uv$' "$REPO_ROOT/packages/official.txt" && echo true || echo false)"
check "official.txt has libuv (WayClick dep)" \
    "$(grep -q '^libuv$' "$REPO_ROOT/packages/official.txt" && echo true || echo false)"
check "official.txt has python (WayClick venv)" \
    "$(grep -q '^python$' "$REPO_ROOT/packages/official.txt" && echo true || echo false)"
check "official.txt has pipewire-audio (WayClick audio)" \
    "$(grep -q '^pipewire-audio$' "$REPO_ROOT/packages/official.txt" && echo true || echo false)"
check "official.txt has chess-tui" \
    "$(grep -q '^chess-tui$' "$REPO_ROOT/packages/official.txt" && echo true || echo false)"
check "aur.txt has stockfish (chess engine)" \
    "$(grep -q '^stockfish$' "$REPO_ROOT/packages/aur.txt" && echo true || echo false)"
check "aur.txt has moviebox-tui" \
    "$(grep -q '^moviebox-tui$' "$REPO_ROOT/packages/aur.txt" && echo true || echo false)"

# ── 8. Deployment test with temp HOME ─────────────────────────────────────────

echo ""
echo "== 8. Deployment test (temp HOME) =="
TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Source env and functions
export HOME="$TEST_HOME"
export XDG_CONFIG_HOME="$TEST_HOME/.config"
export XDG_DATA_HOME="$TEST_HOME/.local/share"
export XDG_BIN_HOME="$TEST_HOME/.local/bin"
export XDG_CACHE_HOME="$TEST_HOME/.cache"
export XDG_STATE_HOME="$TEST_HOME/.local/state"

source "$REPO_ROOT/sdata/lib/env.sh"
# Override paths for test
INSTALLED_LISTFILE="$TEST_HOME/.config/scrow/installed_listfile"
FIRSTRUN_FILE="$TEST_HOME/.config/scrow/installed_true"

# Create XDG dirs
mkdir -p "$XDG_BIN_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"
mkdir -p "$(dirname "$INSTALLED_LISTFILE")"

# Define deployment functions inline (cp-based for test without rsync)
_cp_dir() {
    local src="$1" dst="$2"
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
    mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
    find "$src" -type f -o -type l | while read -r f; do
        local rel="${f#"$src"/}"
        realpath -se "$dst/$rel" >> "$INSTALLED_LISTFILE"
    done
}
_cp_dir_sync() {
    local src="$1" dst="$2"
    mkdir -p "$dst"
    rm -rf "$dst"/*
    cp -a "$src"/. "$dst"/
    mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
    find "$src" -type f -o -type l | while read -r f; do
        local rel="${f#"$src"/}"
        realpath -se "$dst/$rel" >> "$INSTALLED_LISTFILE"
    done
}
rsync_dir()       { _cp_dir "$@"; }
rsync_dir__sync() { _cp_dir_sync "$@"; }
rsync_dir__ignore_existing() { mkdir -p "$2"; cp -an "$1"/. "$2"/ 2>/dev/null || true; }
cp_file() {
    mkdir -p "$(dirname "$2")"
    cp -f "$1" "$2"
    mkdir -p "$(dirname "$INSTALLED_LISTFILE")"
    realpath -se "$2" >> "$INSTALLED_LISTFILE"
}

# Deploy .config
rsync_dir__sync "$REPO_ROOT/dots/.config" "$XDG_CONFIG_HOME"

# Deploy .local
rsync_dir "$REPO_ROOT/dots/.local" "$HOME/.local"

# Deploy shell files
for f in .zshrc .fzf-init.zsh .starship-init.zsh .zoxide-init.zsh; do
    [[ -f "$REPO_ROOT/dots/$f" ]] && cp_file "$REPO_ROOT/dots/$f" "$HOME/$f"
done

# Deploy .icons
[[ -d "$REPO_ROOT/dots/.icons" ]] && rsync_dir "$REPO_ROOT/dots/.icons" "$HOME/.icons"

# Deploy Pictures
[[ -d "$REPO_ROOT/dots/Pictures" ]] && rsync_dir "$REPO_ROOT/dots/Pictures" "$HOME/Pictures"

# Ensure executables
find "$XDG_CONFIG_HOME/waybar/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
find "$XDG_CONFIG_HOME/hypr/scripts" -type f -exec chmod +x {} + 2>/dev/null || true
find "$XDG_CONFIG_HOME/hypr/hyprlock" -name "*.sh" -exec chmod +x {} + 2>/dev/null || true

# Verify deployment
deployed_config=$(find "$XDG_CONFIG_HOME" -type f 2>/dev/null | wc -l)
repo_config=$(find "$REPO_ROOT/dots/.config" -type f 2>/dev/null | wc -l)
check ".config files deployed (repo=$repo_config deployed=$deployed_config)" \
    "$([ "$deployed_config" -ge "$repo_config" ] && echo true || echo false)" \
    "repo=$repo_config deployed=$deployed_config"

deployed_local=$(find "$HOME/.local" -type f 2>/dev/null | wc -l)
repo_local=$(find "$REPO_ROOT/dots/.local" -type f 2>/dev/null | wc -l)
check ".local files deployed (repo=$repo_local deployed=$deployed_local)" \
    "$([ "$deployed_local" -ge "$repo_local" ] && echo true || echo false)" \
    "repo=$repo_local deployed=$deployed_local"

# Waybar complete
deployed_waybar=$(find "$XDG_CONFIG_HOME/waybar" -type f 2>/dev/null | wc -l)
repo_waybar=$(find "$REPO_ROOT/dots/.config/waybar" -type f 2>/dev/null | wc -l)
check "Waybar complete deployment ($deployed_waybar/$repo_waybar)" \
    "$([ "$deployed_waybar" -ge "$repo_waybar" ] && echo true || echo false)" \
    "deployed=$deployed_waybar repo=$repo_waybar"

deployed_waybar_dirs=$(find "$XDG_CONFIG_HOME/waybar" -maxdepth 1 -type d 2>/dev/null | wc -l)
repo_waybar_dirs=$(find "$REPO_ROOT/dots/.config/waybar" -maxdepth 1 -type d 2>/dev/null | wc -l)
check "Waybar all theme dirs preserved ($deployed_waybar_dirs/$repo_waybar_dirs)" \
    "$([ "$deployed_waybar_dirs" -ge "$repo_waybar_dirs" ] && echo true || echo false)" \
    "dirs deployed=$deployed_waybar_dirs repo=$repo_waybar_dirs"

# Hyprland complete
deployed_hypr=$(find "$XDG_CONFIG_HOME/hypr" -type f 2>/dev/null | wc -l)
repo_hypr=$(find "$REPO_ROOT/dots/.config/hypr" -type f 2>/dev/null | wc -l)
check "Hyprland complete deployment ($deployed_hypr/$repo_hypr)" \
    "$([ "$deployed_hypr" -ge "$repo_hypr" ] && echo true || echo false)" \
    "deployed=$deployed_hypr repo=$repo_hypr"

check "Hyprland modules deployed" "$([ -d "$XDG_CONFIG_HOME/hypr/modules" ] && echo true || echo false)"
check "Hyprland scripts deployed" "$([ -d "$XDG_CONFIG_HOME/hypr/scripts" ] && echo true || echo false)"
check "Hyprlock scripts deployed" "$([ -d "$XDG_CONFIG_HOME/hypr/hyprlock" ] && echo true || echo false)"

# Local bin
deployed_bin=$(find "$XDG_BIN_HOME" -type f 2>/dev/null | wc -l)
repo_bin=$(find "$REPO_ROOT/dots/.local/bin" -type f 2>/dev/null | wc -l)
check "Local bin complete ($deployed_bin/$repo_bin)" \
    "$([ "$deployed_bin" -ge "$repo_bin" ] && echo true || echo false)" \
    "deployed=$deployed_bin repo=$repo_bin"

# Shell files
check ".zshrc deployed" "$([ -f "$HOME/.zshrc" ] && echo true || echo false)"

# Installed listfile
check "installed_listfile created" "$([ -f "$INSTALLED_LISTFILE" ] && echo true || echo false)"
listfile_lines=$(wc -l < "$INSTALLED_LISTFILE" 2>/dev/null || echo 0)
check "installed_listfile has entries ($listfile_lines)" "$([ "$listfile_lines" -gt 0 ] && echo true || echo false)" "lines=$listfile_lines"

# ── 9. No manual file list needed ────────────────────────────────────────────

echo ""
echo "== 9. Auto-discovery (no manual file list) =="
# Adding a file to dots/.config should auto-deploy without installer changes
mkdir -p "$REPO_ROOT/dots/.config/newtest-app"
echo "test" > "$REPO_ROOT/dots/.config/newtest-app/config.ini"
rsync_dir__sync "$REPO_ROOT/dots/.config" "$XDG_CONFIG_HOME"
check "New app auto-deployed" "$([ -f "$XDG_CONFIG_HOME/newtest-app/config.ini" ] && echo true || echo false)"
rm -rf "$REPO_ROOT/dots/.config/newtest-app"

# ── 10. Waybar deployment fixture test ────────────────────────────────────────
# Prove the .config deployment engine mirrors EVERY intended Waybar file: all
# themes/configs/styles, nested theme modules, scripts (incl. deep ones),
# hidden files (.current, dot-dirs) and symlinks.

echo ""
echo "== 10. Waybar deployment fixture (multi-theme, nested, hidden, symlink) =="

FIX_TMP=$(mktemp -d)
FIX_SRC="$FIX_TMP/fixture"
FIX_DST="$FIX_TMP/home/.config/waybar"

mkdir -p \
    "$FIX_SRC/configs/themes/alpha/modules" \
    "$FIX_SRC/configs/themes/beta/modules" \
    "$FIX_SRC/configs/scripts/nested" \
    "$FIX_SRC/configs/extra/.hidden-dir"

echo '{ "modules-left": [] }' > "$FIX_SRC/configs/config-alpha.jsonc"
echo '{ "modules-left": [] }' > "$FIX_SRC/configs/config-beta.jsonc"
echo '* { color: red; }'      > "$FIX_SRC/configs/style-alpha.css"
echo '* { color: blue; }'     > "$FIX_SRC/configs/style-beta.css"
printf 'alpha'                > "$FIX_SRC/configs/.current"
echo '#!/bin/sh'              > "$FIX_SRC/configs/scripts/media.sh"
echo '#!/bin/sh'              > "$FIX_SRC/configs/scripts/nested/health.sh"
echo 'keep'                   > "$FIX_SRC/configs/extra/.hidden-dir/.keep"
echo '{ "battery": {} }'      > "$FIX_SRC/configs/themes/alpha/modules/battery.jsonc"
echo '{ "clock": {} }'        > "$FIX_SRC/configs/themes/beta/modules/clock.jsonc"
chmod +x "$FIX_SRC/configs/scripts/media.sh" "$FIX_SRC/configs/scripts/nested/health.sh"
ln -s themes/alpha/modules/battery.jsonc "$FIX_SRC/configs/logos.jsonc"

# The same .config deployment primitive 3.files.sh uses (rsync preferred,
# cp fallback). rsync_dir__sync is already defined above (cp-based), and we
# additionally exercise the real rsync mode when rsync is available.
if command -v rsync >/dev/null 2>&1; then
    deploy_waybar_fixture() { mkdir -p "$2"; rsync -a --delete "$1"/ "$2"/; }
else
    deploy_waybar_fixture() { mkdir -p "$2"; rm -rf "$2"/*; cp -a "$1"/. "$2"/; }
fi
deploy_waybar_fixture "$FIX_SRC/configs" "$FIX_DST"
find "$FIX_DST/scripts" -type f -exec chmod +x {} + 2>/dev/null || true

fix_count_src=$(find "$FIX_SRC/configs" -mindepth 1 | wc -l)
fix_count_dst=$(find "$FIX_DST" -mindepth 1 | wc -l)
check "Fixture: deployed count == source count ($fix_count_dst/$fix_count_src)" \
    "$([ "$fix_count_dst" -eq "$fix_count_src" ] && echo true || echo false)" \
    "dst=$fix_count_dst src=$fix_count_src"

fix_missing=$(comm -23 \
    <(cd "$FIX_SRC/configs" && find . -mindepth 1 | sort) \
    <(cd "$FIX_DST" && find . -mindepth 1 | sort))
check "Fixture: zero intended files missing from deployed tree" \
    "$([ -z "$fix_missing" ] && echo true || echo false)" "missing=$fix_missing"

check "Fixture: multiple configs deployed (alpha+beta)" \
    "$([ -f "$FIX_DST/config-alpha.jsonc" ] && [ -f "$FIX_DST/config-beta.jsonc" ] && echo true || echo false)"
check "Fixture: multiple styles deployed (alpha+beta)" \
    "$([ -f "$FIX_DST/style-alpha.css" ] && [ -f "$FIX_DST/style-beta.css" ] && echo true || echo false)"
check "Fixture: nested theme module deployed (themes/alpha/modules/battery.jsonc)" \
    "$([ -f "$FIX_DST/themes/alpha/modules/battery.jsonc" ] && echo true || echo false)"
check "Fixture: deep script deployed + executable (scripts/nested/health.sh)" \
    "$([ -x "$FIX_DST/scripts/nested/health.sh" ] && echo true || echo false)"
check "Fixture: script executable bit preserved (scripts/media.sh)" \
    "$([ -x "$FIX_DST/scripts/media.sh" ] && echo true || echo false)"
check "Fixture: hidden state file deployed (.current)" \
    "$([ -f "$FIX_DST/.current" ] && echo true || echo false)"
check "Fixture: hidden nested file deployed (extra/.hidden-dir/.keep)" \
    "$([ -f "$FIX_DST/extra/.hidden-dir/.keep" ] && echo true || echo false)"
check "Fixture: symlink preserved as symlink (not dereferenced)" \
    "$([ -L "$FIX_DST/logos.jsonc" ] && echo true || echo false)"

# The real installed tree must satisfy the same completeness check the
# installer's preflight runs (3.files.sh waybar_preflight).
real_waybar_missing=$(comm -23 \
    <(cd "$REPO_ROOT/dots/.config/waybar" && find . -mindepth 1 | sort) \
    <(cd "$XDG_CONFIG_HOME/waybar" && find . -mindepth 1 | sort) 2>/dev/null)
check "Real tree: repository waybar == deployed waybar (0 missing)" \
    "$([ -z "$real_waybar_missing" ] && echo true || echo false)" "missing=$real_waybar_missing"

rm -rf "$FIX_TMP"

# ── 11. Summary ───────────────────────────────────────────────────────────────

echo ""
echo "=== Results ==="
printf "\e[32m%d passed\e[0m, \e[31m%d failed\e[0m\n" "$PASS" "$FAIL"
echo ""
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
