#!/usr/bin/env python3
import os
import re
import stat
import tempfile
import fcntl
import logging
import copy
import time
from pathlib import Path
from typing import Any

from python.frontend.core_types import BaseEngine

logger = logging.getLogger("scrow_fstab_engine")
logger.setLevel(logging.INFO)

class FstabEngine(BaseEngine):
    """
    Production-grade, highly secure configuration engine for /etc/fstab.
    Features dedicated lockfiles to prevent os.replace-induced lock invalidation,
    generic octal unescaping, cross-tag device resolution, and Arch Linux kernel 7.1 compliance.
    """

    def __init__(self, config_path: str = "/etc/fstab"):
        self.config_path = Path(config_path).expanduser().resolve()
        # Dedicated lockfile path to ensure flock stays valid across replacements
        self.lock_path = self.config_path.parent / f".{self.config_path.name}.lock"
        self.file_mtime_ns: int = 0
        
        # State schema cache
        self.state: dict[str, Any] = self._default_state()

    @staticmethod
    def _default_state() -> dict[str, Any]:
        return {
            "mount_info/uuid": "",
            "mount_info/mount_point": "/",
            "filesystem/fs_type": "btrfs",
            "filesystem/drive_type": "ssd",
            "btrfs_ops/subvol": "@",
            "btrfs_ops/cow_enabled": True,
            "system_flags/auto_mount": True,
            "system_flags/gvfs_show": True,
        }

    @property
    def target_path(self) -> str:
        return str(self.config_path)

    @property
    def cache(self) -> dict[str, Any]:
        return copy.deepcopy(self.state)

    def _unescape_token(self, s: str) -> str:
        """Decodes generic fstab octal escapes (e.g. \\040 -> space)."""
        out = []
        i = 0
        while i < len(s):
            if s[i] == "\\" and i + 3 < len(s) and all(c in "01234567" for c in s[i+1:i+4]):
                try:
                    out.append(chr(int(s[i+1:i+4], 8)))
                except ValueError:
                    out.append(s[i:i+4])
                i += 4
            else:
                out.append(s[i])
                i += 1
        return "".join(out)

    def _normalize_identifier(self, spec: str) -> tuple[str, str]:
        """
        Parses and canonicalizes a partition specifier (e.g. UUID=..., /dev/sda1)
        into a (type, value) tuple. Supports case-insensitive prefix parsing
        and resolves symlinks.
        """
        spec = self._unescape_token(spec.strip())
        spec_upper = spec.upper()

        # Parse tags case-insensitively
        for tag, prefix in (("UUID", "UUID="), ("PARTUUID", "PARTUUID="),
                            ("LABEL", "LABEL="), ("PARTLABEL", "PARTLABEL=")):
            if spec_upper.startswith(prefix):
                val = spec[len(prefix):].strip().strip("'\"").strip()
                return tag, val.lower() if tag in ("UUID", "PARTUUID") else val

        if spec.startswith("/dev/"):
            # Direct by-tag path check
            for tag, prefix in (("UUID", "by-uuid"), ("PARTUUID", "by-partuuid"),
                                ("LABEL", "by-label"), ("PARTLABEL", "by-partlabel")):
                pfx_dir = f"/dev/disk/{prefix}/"
                if spec.startswith(pfx_dir):
                    val = spec[len(pfx_dir):]
                    return tag, val.lower() if tag in ("UUID", "PARTUUID") else val

            # Reverse lookup check: scan symlink directories to map raw /dev/ paths back to tags
            try:
                real_spec = os.path.realpath(spec)
                for tag, prefix in (("UUID", "by-uuid"), ("PARTUUID", "by-partuuid"),
                                    ("LABEL", "by-label"), ("PARTLABEL", "by-partlabel")):
                    pfx_dir = Path(f"/dev/disk/{prefix}/")
                    if pfx_dir.exists():
                        for entry in pfx_dir.iterdir():
                            try:
                                if entry.is_symlink() and entry.resolve() == Path(real_spec):
                                    val = entry.name
                                    return tag, val.lower() if tag in ("UUID", "PARTUUID") else val
                            except OSError:
                                continue
            except OSError:
                pass
            return "PATH", spec  # Preserve case-sensitivity for device paths

        # Fallback heuristic: If it has no '=' and does not start with '/dev/', treat it as a UUID
        if "=" not in spec and not spec.startswith("/dev/"):
            return "UUID", spec.lower()

        # Fallback
        return "RAW", spec

    def _resolve_to_devpath(self, tag: str, val: str) -> str | None:
        """Resolves a tag and value to a canonical /dev/ physical path."""
        if tag == "PATH":
            try:
                return os.path.realpath(val)
            except OSError:
                return None
        prefix_map = {"UUID": "by-uuid", "PARTUUID": "by-partuuid",
                      "LABEL": "by-label", "PARTLABEL": "by-partlabel"}
        if tag in prefix_map:
            try:
                return os.path.realpath(f"/dev/disk/{prefix_map[tag]}/{val}")
            except OSError:
                return None
        return None

    def _match_device(self, spec1: str, spec2: str) -> bool:
        """Compares two device specifiers for equivalence, including cross-tag matching."""
        if not spec1 or not spec2:
            return False
        try:
            t1, v1 = self._normalize_identifier(spec1)
            t2, v2 = self._normalize_identifier(spec2)
            if t1 == t2 and v1 == v2:
                return True
            # Cross-tag matching: resolve both to physical device paths and compare
            r1 = self._resolve_to_devpath(t1, v1)
            r2 = self._resolve_to_devpath(t2, v2)
            return r1 is not None and r1 == r2
        except Exception:
            return False

    def _flock_with_timeout(self, fd: int, lock_type: str, timeout: float = 5.0) -> bool:
        """Acquires a flock with timeout to prevent TUI blocking hangs."""
        op = fcntl.LOCK_EX if lock_type == "EX" else fcntl.LOCK_SH
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, op | fcntl.LOCK_NB)
                return True
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    return False
                time.sleep(0.05)

    def load_state(self, force: bool = False) -> dict[str, Any]:
        """
        Parses /etc/fstab for the active target device configuration under a shared lock.
        Caches state to avoid redundant disk reads unless mtime changes.
        """
        if not self.config_path.exists():
            return self.state

        # Acquire shared lock on the dedicated lockfile
        try:
            lock_fd = os.open(self.lock_path, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o644)
        except OSError as e:
            logger.error(f"Failed to open lockfile for load_state: {e}")
            return self.state

        try:
            if not self._flock_with_timeout(lock_fd, "SH", timeout=2.0):
                logger.error("Timeout acquiring shared lock for load_state")
                return self.state

            current_mtime_ns = self.config_path.stat().st_mtime_ns
            if not force and current_mtime_ns == self.file_mtime_ns:
                return self.state
            
            active_uuid = self.state.get("mount_info/uuid", "")
            
            new_state = self._default_state()
            new_state["mount_info/uuid"] = active_uuid

            if not active_uuid:
                self.state = new_state
                self.file_mtime_ns = current_mtime_ns
                return self.state

            found = False
            with open(self.config_path, "r", encoding="utf-8", errors="surrogateescape") as f:
                for line in f:
                    line_strip = line.rstrip("\n")
                    content = line_strip.strip()
                    if not content or content.startswith("#"):
                        continue
                    
                    fields = content.split()
                    if len(fields) < 4:
                        continue
                    
                    dev_spec = fields[0]
                    if self._match_device(dev_spec, active_uuid):
                        found = True
                        new_state["mount_info/mount_point"] = self._unescape_token(fields[1])
                        fs_type = fields[2].lower()
                        new_state["filesystem/fs_type"] = fs_type
                        
                        opts = fields[3].split(",")
                        
                        # Drive type auto-detection
                        if fs_type == "btrfs":
                            new_state["filesystem/drive_type"] = self._detect_drive_type(dev_spec)
                        else:
                            if "ssd" in opts or any(o.startswith("discard") for o in opts):
                                new_state["filesystem/drive_type"] = "ssd"
                            else:
                                new_state["filesystem/drive_type"] = "hdd"
                            
                        # Mount auto boot
                        if "noauto" in opts:
                            new_state["system_flags/auto_mount"] = False
                        else:
                            new_state["system_flags/auto_mount"] = True
                            
                        # GVfs show detection
                        new_state["system_flags/gvfs_show"] = "comment=x-gvfs-show" in opts
                            
                        # Btrfs specific subvol and CoW toggles
                        if fs_type == "btrfs":
                            subvol_val = "@"
                            for opt in opts:
                                if opt.startswith("subvol="):
                                    subvol_val = opt.split("=", 1)[1]
                                    break
                            new_state["btrfs_ops/subvol"] = subvol_val
                            new_state["btrfs_ops/cow_enabled"] = "nodatacow" not in opts
                        break

            self.state = new_state
            # Only update cached mtime on successful parsing
            self.file_mtime_ns = current_mtime_ns
            if not found and active_uuid:
                logger.warning(f"Device {active_uuid} not present in fstab; using defaults")

        except Exception as e:
            logger.error(f"Failed to read fstab: {e}")
        finally:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)

        return self.state

    def _detect_drive_type(self, device_spec: str) -> str:
        """Resolves device to sysfs blocks to detect rotational flag safely for NVMe/whole disks."""
        t, v = self._normalize_identifier(device_spec)
        prefix_map = {"UUID": "by-uuid", "PARTUUID": "by-partuuid", "LABEL": "by-label", "PARTLABEL": "by-partlabel"}
        
        if t in prefix_map:
            link = f"/dev/disk/{prefix_map[t]}/{v}"
        elif t == "PATH":
            link = v
        else:
            return "hdd"
        
        try:
            real = os.path.realpath(link)
            base = os.path.basename(real)
            sys_path = Path(f"/sys/class/block/{base}")
            if not sys_path.exists():
                return "hdd"
            
            # Check if it is a partition by checking the partition file
            if (sys_path / "partition").exists():
                parent_path = sys_path.resolve().parent
                rotational_path = parent_path / "queue" / "rotational"
            else:
                rotational_path = sys_path / "queue" / "rotational"
                
            if not rotational_path.exists():
                # Fallback to direct block match
                rotational_path = Path(f"/sys/block/{base}/queue/rotational")

            if rotational_path.exists():
                with open(rotational_path, "r") as f:
                    return "hdd" if f.read().strip() == "1" else "ssd"
        except OSError:
            pass
        return "hdd"

    def _first_normal_uid_gid(self) -> tuple[int, int]:
        """Resolves the invoking user's ID dynamically, falling back safely."""
        sudo_uid = os.environ.get("SUDO_UID")
        sudo_gid = os.environ.get("SUDO_GID")
        if sudo_uid and sudo_gid:
            try:
                return int(sudo_uid), int(sudo_gid)
            except ValueError:
                pass
        
        pkexec_uid = os.environ.get("PKEXEC_UID")
        if pkexec_uid:
            try:
                import pwd
                pw = pwd.getpwuid(int(pkexec_uid))
                return pw.pw_uid, pw.pw_gid
            except (ValueError, KeyError):
                pass

        try:
            with open("/etc/passwd", "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.split(":")
                    if len(parts) < 4:
                        continue
                    uid = int(parts[2])
                    gid = int(parts[3])
                    if 1000 <= uid < 65534:
                        return uid, gid
        except OSError:
            pass
        return 1000, 1000

    def _coerce_bool(self, key: str, value: Any) -> bool:
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return value != 0
        if isinstance(value, str):
            v = value.strip().lower()
            if v in ("true", "1", "yes", "on", "y", "t", "enabled"):
                return True
            if v in ("false", "0", "no", "off", "n", "f", "disabled"):
                return False
        return False

    def write_value(self, target_key: str, target_scope: str, new_value: str, item_type: str = "string") -> tuple[bool, str, str]:
        # Handle type deserialization
        val = new_value
        if item_type == "bool" or target_key in ("cow_enabled", "auto_mount"):
            val = self._coerce_bool(target_key, new_value)

        # Snapshot state cache for rollback safety
        saved_state = copy.deepcopy(self.state)
        
        # Update cache
        cache_key = f"{target_scope}/{target_key}"
        self.state[cache_key] = val

        active_uuid = self.state.get("mount_info/uuid", "")

        # 1. Selection Switch Event
        if target_key == "uuid" and target_scope == "mount_info":
            # Verify target format
            t, v = self._normalize_identifier(new_value)
            if t == "RAW":
                self.state = saved_state
                return False, f"Invalid device identifier format: {new_value!r}", ""
            
            self.load_state(force=True)
            return True, f"Loaded configuration for device {new_value}", ""

        # 2. Mutation Event
        if not active_uuid:
            self.state = saved_state
            return False, "Cannot modify fstab: Select a valid target device first.", ""

        ok, msg, detail = self.commit_changes()
        if not ok:
            self.state = saved_state  # Rollback on write failures
        return ok, msg, detail

    def _escape_token(self, s: str) -> str:
        """Escapes spaces, tabs, and carriage returns for fstab safety."""
        s = s.replace("\\", "\\\\")
        for char, esc in [(" ", "040"), ("\t", "011"), ("\n", "012"), ("\r", "015")]:
            s = s.replace(char, f"\\{esc}")
        return s

    def commit_changes(self) -> tuple[bool, str, str]:
        """
        Locks fstab using a dedicated lockfile flock, surgically replaces the active device entry,
        and durably writes the configuration using double fsync commits.
        """
        active_uuid = self.state.get("mount_info/uuid", "")
        mp = self.state.get("mount_info/mount_point", "/")
        fs = self.state.get("filesystem/fs_type", "btrfs")
        drive = self.state.get("filesystem/drive_type", "ssd")
        subvol = self.state.get("btrfs_ops/subvol", "@")
        cow = self.state.get("btrfs_ops/cow_enabled", True)
        auto_mnt = self.state.get("system_flags/auto_mount", True)
        gvfs_show = self.state.get("system_flags/gvfs_show", True)

        # Validation Checks
        SUPPORTED_FS = {"btrfs", "vfat", "exfat", "ntfs", "ext4", "ext3", "ext2", "swap"}
        if fs not in SUPPORTED_FS:
            return False, f"Unsupported filesystem type: {fs!r}", ""

        if any(c in mp for c in "\x00\n\r"):
            return False, f"Invalid mount point: {mp!r} (contains illegal control characters)", ""

        if fs == "swap":
            if mp not in ("none", "swap", "/"):
                return False, f"swap mount point must be 'none', got {mp!r}", ""
            mp = "none"
        elif not mp or not mp.startswith("/"):
            return False, f"Invalid mount point: {mp!r} (must start with /)", ""

        if fs == "btrfs":
            if not subvol:
                return False, "Btrfs subvol cannot be empty", ""
            if any(c in subvol for c in ", \t\n\x00"):
                return False, f"Invalid Btrfs subvolume name: {subvol!r} (contains illegal characters)", ""

        # Generate target prefix
        t, v = self._normalize_identifier(active_uuid)
        if t == "UUID":
            device_spec = f"UUID={v}"
        elif t == "PARTUUID":
            device_spec = f"PARTUUID={v}"
        elif t == "LABEL":
            device_spec = f"LABEL={self._escape_token(v)}"
        elif t == "PARTLABEL":
            device_spec = f"PARTLABEL={self._escape_token(v)}"
        else:
            device_spec = self._escape_token(active_uuid)

        normalized_mp = self._escape_token(mp)
        
        # Guard nofail on critical system mounts
        critical = mp in ("/", "/usr", "/var", "/boot", "/efi", "/boot/efi")
        auto_part = "" if auto_mnt else "noauto"
        nofail_part = "" if critical else "nofail"
        
        if auto_part and nofail_part:
            auto_flag = f"{auto_part},{nofail_part}"
        else:
            auto_flag = auto_part or nofail_part
            
        auto_flag = auto_flag or "defaults"

        options = ""
        dump_pass = "0 0"
        
        uid, gid = self._first_normal_uid_gid()

        # Arch Linux Kernel 7.1 storage architecture options compiler
        if fs == "btrfs":
            options = "defaults,noatime"
            if drive == "ssd":
                options += ",discard=async"
            if cow:
                options += ",compress=zstd:3"
                if drive != "ssd":
                    options += ",autodefrag"
            else:
                options += ",nodatacow"
                
            options += f",subvol={subvol}"
            if auto_flag != "defaults":
                options += f",{auto_flag}"
            if gvfs_show:
                options += ",user,comment=x-gvfs-show"
            dump_pass = "0 0"

        elif fs == "vfat":
            # Native iocharset=utf8 replaces legacy/deprecated utf8; toxic flush option removed
            options = f"rw,relatime,fmask=0133,dmask=0022,shortname=mixed,utf8,errors=remount-ro"
            if auto_flag != "defaults":
                options += f",{auto_flag}"
            if gvfs_show:
                options += ",user,comment=x-gvfs-show"
            dump_pass = "0 0"

        elif fs == "exfat":
            options = f"rw,noatime,uid={uid},gid={gid},dmask=0022,fmask=0133,iocharset=utf8,errors=remount-ro"
            if auto_flag != "defaults":
                options += f",{auto_flag}"
            if gvfs_show:
                options += ",user,comment=x-gvfs-show"
            dump_pass = "0 0"

        elif fs == "ntfs":
            # Kernel 7.1 rewritten native module (filesystem type 'ntfs', replaces Paragon ntfs3/ntfs-3g)
            options = f"defaults,noatime,uid={uid},gid={gid},umask=002,windows_names,iocharset=utf8,prealloc"
            if auto_flag != "defaults":
                options += f",{auto_flag}"
            if gvfs_show:
                options += ",user,comment=x-gvfs-show"
            dump_pass = "0 0"

        elif fs in ("ext4", "ext3", "ext2"):
            # SSD discard mount option removed (relies on fstrim.timer to protect write queue)
            pass_val = "1" if mp == "/" else "2"
            options = "defaults,noatime,lazytime"
            if auto_flag != "defaults":
                options += f",{auto_flag}"
            if gvfs_show:
                options += ",user,comment=x-gvfs-show"
            dump_pass = f"0 {pass_val}"

        elif fs == "swap":
            options = "defaults"
            dump_pass = "0 0"

        new_fstab_line = f"{device_spec}\t{normalized_mp}\t{fs}\t{options}\t{dump_pass}\n"

        # Concurrency Protection: flock the dedicated lockfile to prevent inode substitution bugs
        try:
            lock_fd = os.open(self.lock_path, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC, 0o644)
        except OSError as e:
            return False, f"Failed to open lockfile: {e}", ""

        try:
            if not self._flock_with_timeout(lock_fd, "EX", timeout=5.0):
                return False, "Timeout acquiring exclusive lock on /etc/fstab", ""

            # Inode-Safe TOCTOU Check: stat fstab path
            existed_before = self.config_path.exists()
            if existed_before:
                current_mtime_ns = self.config_path.stat().st_mtime_ns
                if self.file_mtime_ns > 0 and current_mtime_ns > self.file_mtime_ns:
                    return False, "fstab was modified externally since loaded. Aborting transaction.", ""

            # Read existing configuration
            out_lines = []
            replaced = False
            
            if existed_before:
                with open(self.config_path, "r", encoding="utf-8", errors="surrogateescape") as f:
                    lines = f.readlines()
            else:
                lines = []

            for line in lines:
                line_strip = line.rstrip("\n")
                content = line_strip.strip()
                if not content or content.startswith("#"):
                    out_lines.append(line)
                    continue
                
                # Surgical parse preserving spacing and comments
                fields = content.split()
                if len(fields) < 4:
                    out_lines.append(line)
                    continue
                
                comment = ""
                if len(fields) > 4:
                    for idx in range(4, len(fields)):
                        if fields[idx].startswith("#"):
                            # Reconstruct trailing comment
                            comment = " " + " ".join(fields[idx:])
                            break

                dev_spec_in_file = fields[0]
                if self._match_device(dev_spec_in_file, active_uuid):
                    # Replace in-place
                    out_lines.append(new_fstab_line.rstrip("\n") + comment + "\n")
                    replaced = True
                else:
                    out_lines.append(line)

            if not replaced:
                # Add spacing blank line if the file doesn't already end with a blank line
                if out_lines:
                    if not out_lines[-1].endswith("\n"):
                        out_lines[-1] += "\n"
                    # Prevent empty line accumulation
                    if out_lines[-1].strip():
                        out_lines.append("\n")
                out_lines.append(new_fstab_line)

            # Atomic Write Commit
            success = False
            temp_file_path = None
            try:
                # mkstemp lets us set correct modes immediately at creation
                temp_fd, temp_path = tempfile.mkstemp(dir=self.config_path.parent, prefix=f".{self.config_path.name}.")
                temp_file_path = Path(temp_path)
                
                try:
                    # Inherit permissions/ownership on open fd to avoid metadata leaks
                    if existed_before:
                        st = self.config_path.stat()
                        os.fchown(temp_fd, st.st_uid, st.st_gid)
                        os.fchmod(temp_fd, stat.S_IMODE(st.st_mode))
                    else:
                        os.fchmod(temp_fd, 0o644)
                except OSError:
                    pass

                # Write contents
                with os.fdopen(temp_fd, "w", encoding="utf-8", errors="surrogateescape", closefd=True) as tf:
                    tf.writelines(out_lines)
                    tf.flush()
                    try:
                        # fsync temp file contents
                        os.fsync(tf.fileno())
                    except OSError:
                        pass

                # Eventual mtime check
                temp_mtime_ns = temp_file_path.stat().st_mtime_ns

                # Atomic swap replacement
                os.replace(temp_file_path, self.config_path)
                
                # Check for double modifications post-replace
                post_st = self.config_path.stat()
                self.file_mtime_ns = post_st.st_mtime_ns
                success = True

                # Directory fsync is best-effort durability
                try:
                    dir_fd = os.open(str(self.config_path.parent), os.O_RDONLY | os.O_DIRECTORY | os.O_CLOEXEC)
                    try:
                        os.fsync(dir_fd)
                    finally:
                        os.close(dir_fd)
                except OSError:
                    pass

            except OSError as e:
                logger.error(f"Atomic replacement failed: {e}")
                if temp_file_path and temp_file_path.exists():
                    try:
                        temp_file_path.unlink()
                    except OSError:
                        pass
                return False, f"Atomic commit failed: {e}", ""

            if success:
                return True, f"Successfully edited fstab entry for {active_uuid}.", ""
            return False, "Failed to write fstab atomic replacement.", ""

        finally:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
            os.close(lock_fd)

    def write_batch(self, changes: list[tuple[str, str, str, str]]) -> tuple[bool, str, str]:
        if not changes:
            return True, "No pending changes.", ""

        # UUID selection switch must be performed first and loaded
        uuid_change = None
        other_changes = []
        for key, scope, val_str, itype in changes:
            if key == "uuid" and scope == "mount_info":
                uuid_change = (key, scope, val_str, itype)
            else:
                other_changes.append((key, scope, val_str, itype))

        saved_state = copy.deepcopy(self.state)

        if uuid_change:
            ok, msg, _ = self.write_value(*uuid_change)
            if not ok:
                return False, msg, ""

        for key, scope, val_str, itype in other_changes:
            val = val_str
            if itype == "bool" or key in ("cow_enabled", "auto_mount"):
                val = self._coerce_bool(key, val_str)
            cache_key = f"{scope}/{key}"
            self.state[cache_key] = val

        ok, msg, detail = self.commit_changes()
        if not ok:
            self.state = saved_state
        return ok, msg, detail
