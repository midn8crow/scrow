#!/bin/bash
# AUR Package Security Checker (paru version)
# Checks PKGBUILD, .install files, and (optionally) downloaded sources for
# suspicious patterns before installing.

# Clear screen AND scrollback buffer
printf '\033[2J\033[H\033[3J'

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Cleanup on exit
TEMP_DIR=""
cleanup() {
    [ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR" 2>/dev/null
}
trap cleanup EXIT

# --- Input validation ---
if [ -z "$1" ]; then
    echo "Usage: $0 <package-name>"
    echo "Example: $0 neofetch"
    exit 1
fi

PACKAGE="$1"
if [[ ! "$PACKAGE" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    printf "${RED}[ERROR]${NC} Invalid package name: '%s'\n" "$PACKAGE"
    echo "Package names can only contain: a-z A-Z 0-9 . _ -"
    exit 1
fi

echo "=========================================="
echo "  AUR Security Check: $PACKAGE"
echo "=========================================="
echo ""

# --- Step 1: package info from AUR ---
echo -e "${YELLOW}[1/6] Fetching package info...${NC}"
echo ""

AUR_INFO=$(curl -s --max-time 20 "https://aur.archlinux.org/rpc/v5/info/$PACKAGE" 2>/dev/null)

if [ -z "$AUR_INFO" ]; then
    echo -e "${RED}[ERROR]${NC} Failed to fetch package info from AUR"
    exit 1
fi

if printf '%s' "$AUR_INFO" | grep -q '"resultcount":0'; then
    echo -e "${RED}[ERROR]${NC} Package '$PACKAGE' not found in AUR"
    exit 1
fi

NAME=$(printf '%s' "$AUR_INFO" | grep -o '"Name":"[^"]*"' | head -1 | cut -d'"' -f4)
VERSION=$(printf '%s' "$AUR_INFO" | grep -o '"Version":"[^"]*"' | head -1 | cut -d'"' -f4)
DESCRIPTION=$(printf '%s' "$AUR_INFO" | grep -o '"Description":"[^"]*"' | head -1 | cut -d'"' -f4)
URL=$(printf '%s' "$AUR_INFO" | grep -o '"URL":"[^"]*"' | head -1 | cut -d'"' -f4)
MAINTAINER=$(printf '%s' "$AUR_INFO" | grep -o '"Maintainer":"[^"]*"' | head -1 | cut -d'"' -f4)
VOTES=$(printf '%s' "$AUR_INFO" | grep -o '"NumVotes":[0-9]*' | head -1 | cut -d':' -f2)
POPULARITY=$(printf '%s' "$AUR_INFO" | grep -o '"Popularity":[0-9.]*' | head -1 | cut -d':' -f2)

printf "  ${CYAN}Name:$NC %s\n" "$NAME"
printf "  ${CYAN}Version:$NC %s\n" "$VERSION"
printf "  ${CYAN}Description:$NC %s\n" "$DESCRIPTION"
printf "  ${CYAN}URL:$NC %s\n" "$URL"
printf "  ${CYAN}Maintainer:$NC %s\n" "$MAINTAINER"
printf "  ${CYAN}Votes:$NC %s\n" "$VOTES"
printf "  ${CYAN}Popularity:$NC %s\n" "$POPULARITY"

if [[ "$VOTES" =~ ^[0-9]+$ ]] && [ "$VOTES" -lt 10 ]; then
    echo -e "  ${RED}[WARNING]${NC} Low votes ($VOTES) - package may be risky"
fi
echo ""

# --- Step 2: clone repo and pin commit ---
echo -e "${YELLOW}[2/6] Downloading AUR repository...${NC}"
echo ""

TEMP_DIR=$(mktemp -d)
REPO_DIR="$TEMP_DIR/$PACKAGE"

if ! timeout 60 git clone --quiet --depth 1 --single-branch "https://aur.archlinux.org/$PACKAGE.git" "$REPO_DIR" 2>/dev/null; then
    echo -e "${RED}[ERROR]${NC} Could not download AUR repository"
    exit 1
fi

COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null)
COMMIT_DATE=$(git -C "$REPO_DIR" show -s --format=%ci HEAD 2>/dev/null | cut -d' ' -f1)

echo -e "  ${GREEN}[OK]${NC} Repository downloaded"
echo -e "  ${CYAN}Commit:$NC $COMMIT"
echo -e "  ${CYAN}Committed:$NC $COMMIT_DATE"
if [ -n "$COMMIT_DATE" ] && [[ "$(date -d "$COMMIT_DATE" +%s 2>/dev/null)" -lt $(($(date +%s) - 1209600)) ]]; then
    echo -e "  ${YELLOW}[INFO]${NC} Last updated over 2 weeks ago - may be stale"
fi
echo ""

# --- Suspicious patterns ---
declare -A PATTERNS=(
    # System destruction
    ["rm -rf /"]="System wipe (deletes entire system)"
    ["rm -rf /\*"]="System wipe (deletes everything)"
    ["rm -rf ~"]="Home directory wipe"
    ["rm -rf \$HOME"]="Home directory wipe"
    ["rmdir /"]="Root directory removal"

    # Remote code execution (must have actual pipe to shell)
    ["curl.*\| *bash"]="Remote code execution via bash"
    ["wget.*\| *bash"]="Remote code execution via bash"
    ["curl.*\| *sh"]="Remote code execution via sh"
    ["wget.*\| *sh"]="Remote code execution via sh"
    ["curl.*\| *zsh"]="Remote code execution via zsh"
    ["wget.*\| *zsh"]="Remote code execution via zsh"
    ["curl.*\| *python"]="Remote code execution via python"
    ["wget.*\| *python"]="Remote code execution via python"
    ["curl.*\| *perl"]="Remote code execution via perl"
    ["wget.*\| *perl"]="Remote code execution via perl"
    ["curl.*\| *ruby"]="Remote code execution via ruby"
    ["wget.*\| *ruby"]="Remote code execution via ruby"
    ["telnet.*\| *sh"]="Telnet pipe to shell"

    # Code execution
    ["eval\("]="Dynamic code execution"
    ["exec\("]="Process execution"
    ["nohup .* &"]="Background process execution"
    ["\`.*\`"]="Command substitution (backticks)"

    # Encoded/hidden payloads
    ["base64 -d.*\|.*bash"]="Encoded payload execution"
    ["base64 -d.*\|.*sh"]="Encoded payload execution"
    ["echo.*\|.*base64.*\|.*bash"]="Encoded payload execution"
    ["printf.*\\\\x[0-9A-Fa-f]"]="Hex-encoded payload"
    ["\$\(echo.*\|.*\bsh\b"]="Obfuscated shell execution"

    # Permission escalation
    ["chmod 777 /"]="Dangerous permissions on root"
    ["chmod \+s"]="SUID escalation"
    ["chmod 4755"]="SUID escalation"
    ["chmod 2755"]="SGID escalation"
    ["chown root"]="Permission escalation"
    ["chown \$USER.*s"]="SUID on user binary"
    ["setuid"]="SUID flag setting"
    ["setgid"]="SGID flag setting"

    # Data theft
    ["/etc/shadow"]="Password hash access"
    ["/etc/passwd"]="User data access"
    ["\.ssh/id"]="SSH key theft"
    ["\.ssh/authorized"]="SSH key theft"
    ["\.ssh/config"]="SSH config access"
    ["\.gnupg"]="PGP key theft"
    ["\.bash_history"]="History file access"
    ["\.zsh_history"]="History file access"
    ["\.config/.*password"]="Config password theft"

    # Surveillance
    ["keylog"]="Keylogging"
    ["keylogger"]="Keylogging"
    ["screen.*-d.*-r"]="Screen capture"
    ["xinput.*xev"]="Input capture"
    ["/dev/input"]="Direct input capture"
    ["xdotool (key|click|type|search|mousemove|getdisplaygeometry|behave_screen)"]="Keyboard/mouse simulation"

    # Network backdoors
    ["nc -l -p"]="Netcat listener"
    ["nc -e"]="Netcat with execute"
    ["ncat -l"]="Backdoor listener"
    ["ncat.*-e"]="Backdoor with execute"
    ["/dev/tcp"]="Network connection"
    ["socket\.connect"]="Socket connection"
    ["\.bind\(|bind\(\s*\("]="Network bind"
    ["\.listen\(|listen\(\s*\("]="Network listener"
    ["reverse.*shell"]="Reverse shell"
    ["bash -i.*>.*&"]="Reverse shell redirect"
    ["mkfifo.*nc"]="Named pipe backdoor"

    # TLS / trust bypass
    ["StrictHostKeyChecking=no"]="SSH host key verification disabled"
    ["--insecure"]="TLS certificate verification disabled (curl)"
    ["curl -k "]="TLS certificate verification disabled (curl)"
    ["wget --no-check-certificate"]="TLS certificate verification disabled (wget)"

    # Writes outside the build directory
    ["-o /(etc|var|root|home|usr)/"]="Downloads directly to a system path"
    ["> \\s*/(etc|var|root|home|usr)/"]="Redirection to a system path"

    # Disk destruction
    ["mkfs\."]="Filesystem formatting"
    ["dd if=.*of=/dev/"]="Disk overwrite"
    ["dd if=.*of=/dev/sd"]="Disk overwrite"
    ["wipefs"]="Filesystem signature wipe"
    ["fdisk.*delete"]="Partition deletion"

    # Scheduled tasks
    ["crontab -e"]="Scheduled task creation"
    ["crontab -r"]="Cron job deletion"
    ["/etc/cron"]="Cron directory access"
    ["systemd-run.*--on-calendar"]="Systemd timer creation"

    # Python/Perl execution
    ["python -c.*import os"]="Python system call"
    ["python -c.*subprocess"]="Python subprocess execution"
    ["python -c.*exec\("]="Python dynamic execution"
    ["python -c.*eval\("]="Python dynamic evaluation"
    ["perl -e.*system"]="Perl system call"
    ["perl -e.*exec"]="Perl exec call"
    ["perl.*-MIPC::Open"]="Perl process execution"

    # Process manipulation
    ["killall"]="Mass process termination"
    ["pkill -9"]="Force kill all"
    ["kill -9.*\$PPID"]="Kill parent process"
    ["kill -TERM.*init"]="Kill init process"

    # Kernel/system manipulation
    ["insmod"]="Kernel module loading"
    ["modprobe"]="Kernel module loading"
    ["rmmod"]="Kernel module removal"
    ["sysctl.*-write"]="Runtime kernel parameter change"

    # Information gathering (recon)
    ["ifconfig.*\|.*curl"]="Network info exfiltration"
    ["ip addr.*\|.*curl"]="Network info exfiltration"
    ["hostname.*\|.*curl"]="Hostname exfiltration"
    ["whoami.*\|.*curl"]="User info exfiltration"
    ["id.*\|.*curl"]="User ID exfiltration"

    # Obfuscation tricks
    ["\$\{.*//.*\}"]="String manipulation (obfuscation)"
    ["\$\{.*:-.*\}"]="Default value substitution"
    ["printf.*%s.*\\\\x"]="Hex string encoding"
)

SUSPICIOUS=0
declare -a SUSPICIOUS_FILES

# Scan one text file: strip comment lines, flatten newlines to spaces so
# patterns can't hide by splitting across lines, then check every pattern.
scan_file() {
    local f="$1"
    [ -f "$f" ] || return 0
    case "$f" in
        */.git/*) return 0 ;;
    esac
    local base ext
    base=${f##*/}
    ext=${base##*.}
    case "$base" in
        README*|LICENSE*|COPYING*|CHANGELOG*|NEWS|AUTHORS|INSTALL|CONTRIBUTING*|HACKING*) return 0 ;;
        Cargo.lock|package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|pnpm-lock.yml|poetry.lock|Gemfile.lock|composer.lock|go.sum|mix.lock) return 0 ;;
    esac
    case "$ext" in
        md|txt|rst|adoc|sample|bak|orig|yml|yaml) return 0 ;;
    esac
    grep -Iq . "$f" 2>/dev/null || return 0   # skip binaries
    local code
    code=$(grep -vE '^[[:space:]]*#' "$f" 2>/dev/null | tr '\n' ' ')
    [ -n "$code" ] || return 0
    local pattern hits=0
    for pattern in "${!PATTERNS[@]}"; do
        if printf '%s' "$code" | grep -qiE -- "$pattern"; then
            echo -e "  ${RED}[SUSPICIOUS]${NC} ${f##*/}: $pattern - ${PATTERNS[$pattern]}"
            hits=$((hits + 1))
        fi
    done
    if [ "$hits" -gt 0 ]; then
        SUSPICIOUS=$((SUSPICIOUS + hits))
        SUSPICIOUS_FILES+=("$f")
    fi
}

# Add read-only binds for common toolchains installed outside /usr (nvm, pyenv,
# asdf, ghcup, opam, go, ...). Each existing dir is bound at its real path so
# the tools' own location logic still works; PATH is extended to reach them.
add_toolchain_binds() {
    local -n binds_ref="$1"
    local -n path_ref="$2"
    local d
    local dirs=(
        "$HOME/.nvm" "$HOME/.volta" "$HOME/.pyenv" "$HOME/.asdf"
        "$HOME/.ghcup" "$HOME/.cabal" "$HOME/.opam" "$HOME/go"
        "$HOME/.local/share/pnpm"
    )
    for d in "${dirs[@]}"; do
        [ -d "$d" ] || continue
        binds_ref+=(--ro-bind "$d" "$d")
        case "$d" in
            "$HOME/.nvm")
                local nvm_bin
                for nvm_bin in "$HOME/.nvm/versions/node"/*/bin; do
                    [ -d "$nvm_bin" ] && path_ref="$nvm_bin:$path_ref"
                done
                ;;
            "$HOME/.pyenv") path_ref="$HOME/.pyenv/shims:$HOME/.pyenv/bin:$path_ref" ;;
            "$HOME/.asdf") path_ref="$HOME/.asdf/shims:$HOME/.asdf/bin:$path_ref" ;;
            "$HOME/.ghcup") path_ref="$HOME/.ghcup/bin:$path_ref" ;;
            "$HOME/.opam") path_ref="$HOME/.opam/default/bin:$path_ref" ;;
            "$HOME/go") path_ref="$HOME/go/bin:$path_ref" ;;
            "$HOME/.cabal") path_ref="$HOME/.cabal/bin:$path_ref" ;;
            "$HOME/.local/share/pnpm") path_ref="$HOME/.local/share/pnpm:$path_ref" ;;
        esac
    done
}

# Run any command inside the bubblewrap sandbox with the toolchain binds, so
# nothing it runs can read or modify your real home.
sandbox_exec() {
    local repo="$1" extra_path=""
    local -a binds=() envs=()
    local cargo_bin cargo_dir rustup_home
    shift
    add_toolchain_binds binds extra_path
    cargo_bin=$(command -v cargo 2>/dev/null)
    envs+=(--setenv CARGO_HOME "$TEMP_DIR/home/.cargo")
    if [ -n "$cargo_bin" ] && [[ "$cargo_bin" != /usr/* ]]; then
        cargo_dir=$(dirname "$cargo_bin")
        binds+=(--ro-bind "$cargo_dir" /opt/rust-bin)
        extra_path="/opt/rust-bin:$extra_path"
        rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
        if [ -d "$rustup_home" ]; then
            binds+=(--ro-bind "$rustup_home" /opt/rustup)
            envs+=(--setenv RUSTUP_HOME /opt/rustup)
        fi
    fi
    [ -n "$extra_path" ] && envs+=(--setenv PATH "$extra_path$PATH")
    timeout 300 bwrap \
        --die-with-parent --unshare-pid --unshare-uts --unshare-ipc \
        --ro-bind /usr /usr --ro-bind /etc /etc \
        --ro-bind /run /run --ro-bind /var /var \
        --proc /proc --dev /dev --tmpfs /dev/shm \
        --tmpfs /tmp --tmpfs /home --tmpfs /root \
        --bind "$TEMP_DIR" "$TEMP_DIR" \
        --symlink usr/bin /bin --symlink usr/lib /lib --symlink usr/lib64 /lib64 \
        --setenv HOME "$TEMP_DIR/home" --setenv GNUPGHOME "$GNUPGHOME" \
        "${binds[@]}" "${envs[@]}" \
        --chdir "$repo" \
        -- "$@"
}

# Run makepkg --nobuild inside the sandbox so prepare() cannot touch your home.
run_isolated_makepkg() {
    local repo="$1"
    if command -v bwrap >/dev/null 2>&1; then
        sandbox_exec "$repo" makepkg --nobuild --noconfirm --nodeps
        return $?
    fi
    # No bwrap: still isolate HOME/CARGO_HOME so the build never touches ~
    (cd "$repo" && timeout 300 env HOME="$TEMP_DIR/home" RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}" GNUPGHOME="$GNUPGHOME" CARGO_HOME="$TEMP_DIR/home/.cargo" makepkg --nobuild --noconfirm --nodeps)
}

# Find build deps that are neither pacman-installed nor present as a binary
# (rustup-style tools on PATH are skipped, so they are never offered for
# install). The PKGBUILD is only ever executed inside the sandbox. Returns
# pacman package names (with version constraints) still missing.
check_missing_builddeps() {
    local repo="$1" extra_path="" srcinfo line dep bin
    local -a binds=() deps=() notinstalled=() missing=()
    add_toolchain_binds binds extra_path
    local cargo_bin
    cargo_bin=$(command -v cargo 2>/dev/null)
    if [ -n "$cargo_bin" ] && [[ "$cargo_bin" != /usr/* ]]; then
        extra_path="$(dirname "$cargo_bin"):$extra_path"
    fi
    if command -v bwrap >/dev/null 2>&1; then
        srcinfo=$(sandbox_exec "$repo" makepkg -p "$repo/PKGBUILD" --printsrcinfo 2>/dev/null)
    else
        srcinfo=$(cd "$repo" && timeout 60 makepkg -p PKGBUILD --printsrcinfo 2>/dev/null)
    fi
    [ -z "$srcinfo" ] && return 0
    while IFS= read -r line; do
        line=${line#makedepends = }
        [ -n "$line" ] && deps+=("$line")
    done < <(printf '%s\n' "$srcinfo" | sed 's/^[[:space:]]*//' | grep '^makedepends = ')
    [ ${#deps[@]} -eq 0 ] && return 0
    while IFS= read -r line; do
        [ -n "$line" ] && notinstalled+=("$line")
    done < <(pacman -T "${deps[@]}" 2>/dev/null)
    for dep in "${notinstalled[@]}"; do
        bin=${dep%%[<>=@]*}
        if ! PATH="$extra_path$PATH" command -v "$bin" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    printf '%s\n' "${missing[@]}"
}

# --- Step 3: scan every file in the repo (PKGBUILD, .install, patches...) ---
echo -e "${YELLOW}[3/6] Scanning repository files...${NC}"
echo ""
while IFS= read -r -d '' f; do
    scan_file "$f"
done < <(find "$REPO_DIR" -type f -not -path '*/.git/*' -print0)

if [ "$SUSPICIOUS" -eq 0 ]; then
    echo -e "  ${GREEN}[OK]${NC} No suspicious patterns in repository files"
fi
echo ""

# --- Step 4: integrity checks on the PKGBUILD ---
echo -e "${YELLOW}[4/6] Checking integrity...${NC}"
echo ""

PKGBUILD_PATH="$REPO_DIR/PKGBUILD"
if [ -f "$PKGBUILD_PATH" ]; then
    if grep -qiE "=\([^)]*SKIP[^)]*\)|('SKIP'|\"SKIP\")" "$PKGBUILD_PATH"; then
        echo -e "  ${RED}[WARNING]${NC} Checksums contain SKIP - downloads are NOT verified"
    elif grep -qiE "^(sha256sums|sha512sums|b2sums|sha1sums|md5sums|cksums)=" "$PKGBUILD_PATH"; then
        echo -e "  ${GREEN}[OK]${NC} Checksums present"
    else
        echo -e "  ${RED}[WARNING]${NC} No checksum array found in PKGBUILD"
    fi
    if grep -qiE "git\+[^ ]+\.git" "$PKGBUILD_PATH"; then
        echo -e "  ${YELLOW}[INFO]${NC} Uses VCS source (git) - verify the commit/tag is pinned"
    fi
    if grep -qiE "no-check-certificate|--insecure|StrictHostKeyChecking=no" "$PKGBUILD_PATH"; then
        echo -e "  ${RED}[WARNING]${NC} TLS/SSH verification disabled somewhere"
    fi
    if grep -qiE "install.*-D.*(/etc|/var|/root|/home|/opt)" "$PKGBUILD_PATH"; then
        echo -e "  ${YELLOW}[INFO]${NC} Installs files outside /usr"
    fi
    if grep -qiE "useradd|adduser|groupadd" "$PKGBUILD_PATH"; then
        echo -e "  ${YELLOW}[INFO]${NC} Creates system users/groups"
    fi
    if grep -qiE "systemctl|\.service|\.timer" "$PKGBUILD_PATH"; then
        echo -e "  ${YELLOW}[INFO]${NC} Installs systemd services/timers"
    fi
    if grep -qiE "udevadm|\.rules" "$PKGBUILD_PATH"; then
        echo -e "  ${YELLOW}[INFO]${NC} Installs udev rules"
    fi
    if grep -qiE "\.desktop|autostart|\.xinitrc|\.xprofile" "$PKGBUILD_PATH"; then
        echo -e "  ${YELLOW}[INFO]${NC} Installs desktop entries or autostart"
    fi
fi

SIG_FILES=$(find "$REPO_DIR" -type f \( -name '*.sig' -o -name '*.asc' \) -not -path '*/.git/*' 2>/dev/null)
if [ -n "$SIG_FILES" ]; then
    echo -e "  ${YELLOW}[INFO]${NC} PGP keys/signatures shipped with the package:"
    while IFS= read -r sig; do
        printf "    - %s\n" "${sig#$REPO_DIR/}"
    done <<< "$SIG_FILES"
    echo -e "         (source signature verification runs in the isolated keyring in step 5)"
else
    echo -e "  ${YELLOW}[INFO]${NC} No signatures shipped - AUR PKGBUILDs are unsigned, verify the maintainer yourself"
fi
echo ""

# --- Step 5: download and scan the actual source code ---
echo -e "${YELLOW}[5/6] Source code scan...${NC}"
echo ""
if command -v makepkg >/dev/null 2>&1; then
    if command -v bwrap >/dev/null 2>&1; then
        echo -e "  ${YELLOW}[WARN]${NC} This downloads and extracts the real sources and runs"
        echo -e "         makepkg's prepare() inside a bubblewrap sandbox: it"
        echo -e "         cannot read or modify anything in your home, but it"
        echo -e "         still has network access (needed to download sources)."
    else
        echo -e "  ${YELLOW}[WARN]${NC} This downloads and extracts the real sources and runs"
        echo -e "         makepkg's prepare() as your user in an isolated temp dir."
        echo -e "         (bubblewrap not installed - install it for full sandboxing)"
    fi
    read -rp "  Download and scan package sources? (y/N): " DO_SOURCES
    if [[ "$DO_SOURCES" =~ ^[Yy]$ ]]; then
        echo ""
        # Import any keys shipped with the package into an isolated keyring so
        # PGP-verified sources can be fetched without touching the real one.
        GNUPGHOME="$TEMP_DIR/gnupg"
        mkdir -m 700 "$GNUPGHOME"
        mkdir -p "$TEMP_DIR/home"
        while IFS= read -r -d '' keyfile; do
            gpg --homedir "$GNUPGHOME" --import "$keyfile" >/dev/null 2>&1
        done < <(find "$REPO_DIR" -type f \( -name '*.asc' -o -name '*.sig' \) -not -path '*/.git/*' -print0)

        # Check for build deps that are genuinely missing (rustup-style tools
        # already on PATH are skipped). Install them with pacman if the user
        # agrees, so the source fetch can actually run.
        MISSING_DEPS=$(check_missing_builddeps "$REPO_DIR")
        if [ -n "$MISSING_DEPS" ]; then
            echo ""
            echo -e "  ${YELLOW}[INFO]${NC} This package needs build dependencies that are"
            echo -e "         not installed on your system:"
            echo "$MISSING_DEPS" | sed 's/^/    - /'
            echo ""
            read -rp "  Install them now with pacman (asks for your password)? (y/N): " DO_INSTALL
            if [[ "$DO_INSTALL" =~ ^[Yy]$ ]]; then
                echo ""
                echo "  Running: sudo pacman -S --needed $MISSING_DEPS"
                if sudo pacman -S --needed $MISSING_DEPS; then
                    echo -e "  ${GREEN}[OK]${NC} Dependencies installed"
                else
                    echo -e "  ${RED}[ERROR]${NC} Dependency install failed - skipping source scan"
                    MISSING_DEPS=""
                    SKIP_SCAN=1
                fi
            else
                echo "  Skipping source scan (build dependencies not installed)."
                SKIP_SCAN=1
            fi
        fi

        if [ -z "$SKIP_SCAN" ]; then
            echo ""
            echo "  Downloading and extracting sources..."
            run_isolated_makepkg "$REPO_DIR" 2>&1 | sed 's/^/    /'
            BUILD_RC=${PIPESTATUS[0]}
            if [ "$BUILD_RC" -eq 0 ] && [ -d "$REPO_DIR/src" ]; then
                echo -e "  ${GREEN}[OK]${NC} Sources downloaded, scanning..."
                while IFS= read -r -d '' f; do
                    scan_file "$f"
                done < <(find "$REPO_DIR/src" -type f -print0)
                if [ "$SUSPICIOUS" -eq 0 ]; then
                    echo -e "  ${GREEN}[OK]${NC} No suspicious patterns in source files"
                fi
            else
                echo -e "  ${YELLOW}[WARN]${NC} Could not download/extract sources (rc=$BUILD_RC) - skipped"
            fi
        fi
    fi
else
    echo "  makepkg not found - skipping source scan"
fi
echo ""

# --- Step 6: show the package files ---
echo -e "${YELLOW}[6/6] Package files...${NC}"
echo ""
for showf in "$PKGBUILD_PATH" "$REPO_DIR"/*.install; do
    [ -f "$showf" ] || continue
    echo -e "${CYAN}--- $(basename "$showf") ---${NC}"
    cat "$showf"
    echo ""
done

# --- Summary ---
echo ""
echo "=========================================="
echo "  RESULT"
echo "=========================================="
if [ "$SUSPICIOUS" -gt 0 ]; then
    echo -e "${RED}  ⚠  $SUSPICIOUS suspicious pattern(s) found in:${NC}"
    for f in "${SUSPICIOUS_FILES[@]}"; do
        printf "    - %s\n" "${f#$REPO_DIR/}"
    done
    echo "  Do NOT install without reviewing the files above."
else
    echo -e "${GREEN}  No obvious threats detected.${NC}"
fi
echo ""
echo -e "  ${CYAN}Pinned commit:$NC $COMMIT"
echo "  TOCTOU warning: paru installs the CURRENT AUR HEAD, not this commit."
echo "  Re-run this check right before installing, and eyeball the sources."
echo ""
echo "  Note: AUR PKGBUILDs are not signed. Verify the maintainer yourself."
echo ""
echo "Press any key to continue..."
read -n 1
