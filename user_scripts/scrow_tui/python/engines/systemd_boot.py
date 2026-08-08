import os
import re
import stat
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Self

from python.frontend.core_types import BaseEngine
from python.engines.cmdline import BridgedStateDict

class SystemdBootEngine(BaseEngine):
    def __init__(self, config_path: str = "") -> None:
        self.config_path: Path = Path(config_path).expanduser().resolve() if config_path else Path("/boot/loader/entries/arch-linux.conf")
        self.cache: BridgedStateDict = BridgedStateDict()
        self.file_mtime_ns: int = 0

    @classmethod
    def from_path(cls, config_path: str) -> Self:
        return cls(config_path)

    @property
    def target_path(self) -> str:
        return str(self.config_path)

    def load_state(self) -> dict[str, Any]:
        if not self.config_path.exists():
            return BridgedStateDict()

        self.cache = BridgedStateDict()
        
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                self.file_mtime_ns = os.fstat(f.fileno()).st_mtime_ns
                content = f.read()
                
            for line in content.splitlines():
                if match := re.match(r'^([ \t]*)options([ \t]+)(.*)$', line):
                    tokens = re.split(r'((?:[^\s"\']|"[^"]*"|\'[^\']*\')+)', match.group(3))
                    args = [t for t in tokens if t.strip()]
                    counts: dict[str, int] = {}
                    
                    for arg in args:
                        k, v = arg.split("=", 1) if "=" in arg else (arg, "true")
                        counts[k] = counts.get(k, 0) + 1
                        self.cache[f"DEFAULT/{k}:{counts[k]}"] = v
                        self.cache[f"DEFAULT/{k}"] = v
        except OSError:
            pass
            
        return self.cache

    def write_value(self, target_key: str, target_scope: str, new_value: str, item_type: str = "string") -> tuple[bool, str, str]:
        return self.write_batch([(target_key, target_scope, new_value, item_type)])

    def write_batch(self, changes: list[tuple[str, str, str, str]]) -> tuple[bool, str, str]:
        if not changes:
            return True, "No pending changes.", ""

        lines: list[str] = []
        if self.config_path.exists():
            try:
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    if os.fstat(f.fileno()).st_mtime_ns > self.file_mtime_ns:
                        return False, f"File {self.config_path.name} modified externally. Reload required.", ""
                    lines = f.read().splitlines()
            except OSError as e:
                return False, f"Failed to open config for verification: {e}", ""

        changes_dict = {(scope, key): (val, itype) for key, scope, val, itype in changes}
        applied_commits: set[tuple[str, str]] = set()
        out_lines: list[str] = []
        options_found: bool = False
        
        for line in lines:
            if match := re.match(r'^([ \t]*)options([ \t]+)(.*)$', line):
                options_found = True
                leading_space, spacing, options_val = match.groups()
                tokens = re.split(r'((?:[^\s"\']|"[^"]*"|\'[^\']*\')+)', options_val)
                
                max_counts: dict[str, int] = {}
                for t in tokens:
                    if t.strip():
                        k = t.split("=", 1)[0]
                        max_counts[k] = max_counts.get(k, 0) + 1
                        
                out_tokens: list[str] = []
                counts: dict[str, int] = {}
                
                for t in tokens:
                    if not t.strip():
                        out_tokens.append(t)
                        continue
                        
                    k = t.split("=", 1)[0]
                    counts[k] = counts.get(k, 0) + 1
                    
                    lookup_exact = ("DEFAULT", f"{k}:{counts[k]}")
                    lookup_base = ("DEFAULT", k)
                    
                    target_val = None
                    target_itype = None
                    matched_lookup = None
                    
                    if lookup_exact in changes_dict:
                        target_val, target_itype = changes_dict[lookup_exact]
                        matched_lookup = lookup_exact
                    elif counts.get(k, 0) == max_counts.get(k, 0) and lookup_base in changes_dict:
                        target_val, target_itype = changes_dict[lookup_base]
                        matched_lookup = lookup_base
                        
                    if target_val is not None:
                        applied_commits.add(matched_lookup)
                        val_str = str(target_val)
                        val_lower = val_str.lower()
                        
                        match (val_lower, target_itype):
                            case ("__delete__" | "unset" | "", _) | ("false", "bool"):
                                if out_tokens and out_tokens[-1].isspace():
                                    out_tokens.pop()
                            case _:
                                if target_itype == "bool" and val_lower == "true":
                                    out_tokens.append(k)
                                else:
                                    out_tokens.append(f"{k}={val_str}")
                    else:
                        out_tokens.append(t)
                        
                for key_raw, scope, val, target_itype in changes:
                    lookup = (scope, key_raw)
                    if lookup in applied_commits:
                        continue
                        
                    val_str = str(val)
                    val_lower = val_str.lower()
                    
                    match (val_lower, target_itype):
                        case ("__delete__" | "unset" | "", _) | ("false", "bool"):
                            continue
                        case _:
                            clean_key = key_raw.split(":")[0] if ":" in key_raw else key_raw
                            needs_space = False
                            for tk in reversed(out_tokens):
                                if tk:
                                    needs_space = bool(tk.strip())
                                    break
                            if needs_space:
                                out_tokens.append(" ")
                                
                            if target_itype == "bool" and val_lower == "true":
                                out_tokens.append(clean_key)
                            else:
                                out_tokens.append(f"{clean_key}={val_str}")
                            applied_commits.add(lookup)
                            
                out_lines.append(f"{leading_space}options{spacing}{''.join(out_tokens).strip()}")
            else:
                out_lines.append(line)
                
        if not options_found:
            new_tokens: list[str] = []
            for key_raw, scope, val, target_itype in changes:
                lookup = (scope, key_raw)
                if lookup in applied_commits:
                    continue
                    
                val_str = str(val)
                val_lower = val_str.lower()
                
                match (val_lower, target_itype):
                    case ("__delete__" | "unset" | "", _) | ("false", "bool"):
                        continue
                    case _:
                        clean_key = key_raw.split(":")[0] if ":" in key_raw else key_raw
                        if new_tokens:
                            new_tokens.append(" ")
                            
                        if target_itype == "bool" and val_lower == "true":
                            new_tokens.append(clean_key)
                        else:
                            new_tokens.append(f"{clean_key}={val_str}")
                        applied_commits.add(lookup)
                        
            if new_tokens:
                out_lines.append(f"options\t{''.join(new_tokens)}")

        final_content = "\n".join(out_lines) + "\n"
        success = False
        status_msg = "Failed"
        temp_file_path = None
        
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with tempfile.NamedTemporaryFile(mode='w', delete=False, encoding='utf-8', dir=self.config_path.parent) as tf:
                temp_file_path = Path(tf.name)
                tf.write(final_content)
                tf.flush()
                os.fsync(tf.fileno())
                
            if self.config_path.exists():
                try:
                    stat_info = self.config_path.stat()
                    os.chmod(temp_file_path, stat.S_IMODE(stat_info.st_mode))
                    os.chown(temp_file_path, stat_info.st_uid, stat_info.st_gid)
                except OSError: 
                    pass
            
            temp_mtime_ns = temp_file_path.stat().st_mtime_ns
            os.replace(temp_file_path, self.config_path)
            
            self.file_mtime_ns = temp_mtime_ns
            success = True
            
        except PermissionError:
            if temp_file_path and temp_file_path.exists():
                try: temp_file_path.unlink()
                except OSError: pass
            try:
                res = subprocess.run(
                    ["sudo", "-n", "tee", str(self.config_path)],
                    input=final_content.encode(), capture_output=True, timeout=5
                )
                if res.returncode == 0:
                    self.file_mtime_ns = self.config_path.stat().st_mtime_ns
                    return True, f"Successfully batched {len(applied_commits)} commits (sudo).", ""
                return False, "AUTH_REQUIRED", ""
            except Exception:
                return False, "AUTH_REQUIRED", ""
        except OSError as e:
            status_msg = f"Atomic commit failed: {e}"
        finally:
            if temp_file_path and temp_file_path.exists() and not success:
                try: temp_file_path.unlink()
                except OSError: pass

        if success:
            return True, f"Successfully batched {len(applied_commits)} commits.", ""
            
        return False, status_msg, ""
