import xml.etree.ElementTree as ET
from xml.dom import minidom
from pathlib import Path
from typing import Any
import subprocess
import shutil
import os
import re
import sys

# Make standalone execution (python3 python/engines/fontconfig.py) resolve
# the scrow_tui package layout regardless of CWD or username.
_SCROW_TUI_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_SCROW_TUI_ROOT) not in sys.path:
    sys.path.insert(0, str(_SCROW_TUI_ROOT))

from python.frontend.core_types import BaseEngine

class FontconfigEngine(BaseEngine):
    """
    O(1) XML serialization engine for Arch Linux fontconfig rules.
    Operates strictly within ~/.config/fontconfig/conf.d/ to adhere to XDG standards.

    Serialization contract (empirically verified against fontconfig 2.18.2):
      - Generic family aliases are emitted with binding="strong" on the alias
        element. Binding-less aliases lose to the system prefer chains in the
        font matching pass and are silently ineffective.
      - Rendered settings are emitted inside a single <match target="font">
        block with mode="assign" for predictable override behavior.
      - Arbitrary target="pattern" family rewrites (Arial -> X, etc.) and any
        match blocks with explicit <test> predicates are preserved verbatim
        across load/write cycles to keep the configuration lossless.
    """
    ALIAS_CLASSES = ("sans-serif", "serif", "monospace", "emoji", "sans")
    RENDER_PROP_WHITELIST = {
        "antialias", "hinting", "autohint", "embeddedbitmap",
        "hintstyle", "rgba", "lcdfilter", "rasterizer",
    }
    DIR_KEYS = {"font_dir", "font_dirs"}
    IGNORED_PATTERN_EDIT_NAMES = {"family", "familylang"}

    _KNOWN_CONSTS = {
        "none", "rgb", "bgr", "vrgb", "vbgr",
        "hintnone", "hintslight", "hintmedium", "hintfull",
        "lcdnone", "lcddefault", "lcdlight", "lcdlegacy",
    }

    def __init__(self, config_path: str = "~/.config/fontconfig/conf.d/99-scrow-fonts.conf"):
        self.config_path = Path(config_path).expanduser().resolve()
        self.cache: dict[str, Any] = {}
        self._pattern_rewrites: list[str] = []
        self._sync_pending = 0
        self._sync_worker_running = False

    @property
    def target_path(self) -> str:
        return str(self.config_path)

    # ------------------------------------------------------------------
    # State loading
    # ------------------------------------------------------------------
    def load_state(self) -> dict[str, Any]:
        self._pattern_rewrites = []
        if not self.config_path.exists() or self.config_path.stat().st_size == 0:
            return {}

        state: dict[str, Any] = {}
        try:
            tree = ET.parse(self.config_path)
            root = tree.getroot()

            dir_values: list[str] = []
            for dir_el in root.findall("dir"):
                if dir_el.text and dir_el.text.strip():
                    dir_values.append(dir_el.text.strip())
            if dir_values:
                state["font_dir"] = dir_values[0] if len(dir_values) == 1 else dir_values

            for alias in root.findall("alias"):
                family_el = alias.find("family")
                if family_el is None or not family_el.text:
                    continue
                family = family_el.text.strip()
                prefer = alias.findall("prefer/family")
                if prefer:
                    fonts = [pf.text.strip() for pf in prefer if pf.text]
                    if fonts:
                        state[family] = fonts[0] if len(fonts) == 1 else fonts

            for match in root.findall("match"):
                target = match.get("target", "font")
                has_family_test = any(
                    t.get("name") in ("family", "familylang") for t in match.findall("test")
                )
                is_pattern_rewrite = target == "pattern" or has_family_test
                if is_pattern_rewrite:
                    self._pattern_rewrites.append(ET.tostring(match, encoding="unicode"))
                    continue

                for edit in match.findall("edit"):
                    name = edit.get("name")
                    if not name or name in self.IGNORED_PATTERN_EDIT_NAMES:
                        continue
                    val = self._extract_edit_value(edit)
                    if val is not None:
                        state[name] = val

            self.cache = state
            return state
        except Exception as e:
            print(f"[FontconfigEngine] Load Exception: {e}")
            return {}

    def load_legacy_state(self) -> dict[str, Any]:
        legacy = Path("~/.config/fontconfig/fonts.conf").expanduser()
        if not legacy.exists() or legacy.stat().st_size == 0 or legacy == self.config_path:
            return {}
        saved = self.config_path
        self.config_path = legacy
        try:
            return self.load_state()
        finally:
            self.config_path = saved

    def _extract_edit_value(self, edit: ET.Element) -> Any:
        bool_node = edit.find("bool")
        if bool_node is not None and bool_node.text:
            return self._text_bool(bool_node.text.strip())

        const_node = edit.find("const")
        if const_node is not None and const_node.text:
            return const_node.text.strip()

        double_node = edit.find("double")
        if double_node is not None and double_node.text:
            return self._to_num(double_node.text.strip(), float)

        int_node = edit.find("int")
        if int_node is not None and int_node.text:
            return self._to_num(int_node.text.strip(), int)

        string_node = edit.find("string")
        if string_node is not None and string_node.text:
            return string_node.text.strip()
        return None

    @staticmethod
    def _to_num(text: str, cast):
        try:
            return cast(text)
        except ValueError:
            return text

    @staticmethod
    def _text_bool(text: str) -> bool:
        return text.lower() in ("true", "1", "yes", "on", "t", "y")

    # ------------------------------------------------------------------
    # Value coercion helpers (shared by load + write paths)
    # ------------------------------------------------------------------
    _TRUTHY = ("true", "1", "yes", "on", "t", "y")

    @classmethod
    def as_bool(cls, val: Any) -> bool:
        if isinstance(val, bool):
            return val
        return str(val).lower() in cls._TRUTHY

    @classmethod
    def _is_numeric_string(cls, s: str) -> bool:
        if s.count(".") > 1 or s.startswith("-"):
            return s.count(".") <= 1 and s.lstrip("-").replace(".", "", 1).isdigit()
        return s.replace(".", "", 1).isdigit()

    def coerce_write_value(self, key: str, val: Any, item_type: str) -> Any:
        if val is None or val == "":
            return None
        if item_type == "bool" or isinstance(val, bool):
            return self.as_bool(val)
        if item_type == "int":
            try:
                return int(val)
            except (ValueError, TypeError):
                return val
        if item_type == "float":
            try:
                return float(val)
            except (ValueError, TypeError):
                return val
        return val

    def render_edit_data_type(self, name: str, val: Any, item_type: str) -> str:
        if isinstance(val, bool) or item_type == "bool":
            return "bool"
        if isinstance(val, int):
            return "int"
        if isinstance(val, float):
            return "float"
        if isinstance(val, str) and self._is_numeric_string(val):
            return "float" if "." in val else "int"
        return "const" if str(val).lower() in self._KNOWN_CONSTS else "string"

    # ------------------------------------------------------------------
    # Mutation paths
    # ------------------------------------------------------------------
    def write_batch(self, changes: list[tuple[str, str, str, str]]) -> tuple[bool, str, str]:
        if not changes:
            return True, "No pending changes.", ""

        legacy_absorbed = False
        if not self.config_path.exists():
            legacy_state = self.load_legacy_state()
            if legacy_state:
                self.cache = legacy_state
                legacy_absorbed = True

        state: dict[str, Any] = dict(self.cache)
        for key, scope, val, itype in changes:
            if val is None or val == "":
                state.pop(key, None)
            else:
                state[key] = self.coerce_write_value(key, val, itype)

        try:
            self.config_path.parent.mkdir(parents=True, exist_ok=True)

            root = ET.Element("fontconfig")

            extra_classes = tuple(
                k for k in state
                if k not in self.ALIAS_CLASSES
                and k not in self.RENDER_PROP_WHITELIST
                and k not in self.DIR_KEYS
                and isinstance(state[k], (list, str))
            )
            for fc in self.ALIAS_CLASSES + extra_classes:
                value = state.get(fc)
                if not value:
                    continue
                alias = ET.SubElement(root, "alias", {"binding": "strong"})
                fam = ET.SubElement(alias, "family")
                fam.text = fc
                pref = ET.SubElement(alias, "prefer")
                if isinstance(value, list):
                    for item in value:
                        node = ET.SubElement(pref, "family")
                        node.text = str(item)
                else:
                    node = ET.SubElement(pref, "family")
                    node.text = str(value)

            dirs: list[str] = []
            for dk in self.DIR_KEYS:
                dv = state.get(dk)
                if dv is None:
                    continue
                raw_dirs = dv if isinstance(dv, list) else [dv]
                for d in raw_dirs:
                    d = str(d).strip()
                    if not d:
                        continue
                    expanded = Path(d).expanduser()
                    if not expanded.is_absolute():
                        expanded = expanded.resolve()
                    dirs.append(str(expanded))

            for d in sorted(set(dirs)):
                node = ET.SubElement(root, "dir")
                node.text = d

            render_keys = [k for k in state
                           if k not in self.ALIAS_CLASSES
                           and k not in self.DIR_KEYS
                           and k in self.RENDER_PROP_WHITELIST
                           and state[k] is not None
                           and not isinstance(state[k], (list, dict))]
            if render_keys:
                match = ET.SubElement(root, "match", {"target": "font"})
                for k in render_keys:
                    self._append_render_edit(match, k, state[k])

            for raw in self._pattern_rewrites:
                try:
                    parsed = ET.fromstring(raw)
                except ET.ParseError:
                    continue
                if not self._rewrite_safe(parsed, state):
                    continue
                root.append(parsed)

            xmlstr = minidom.parseString(ET.tostring(root)).toprettyxml(indent="  ")
            xmlstr = re.sub(
                r'^\s*<\?xml[^>]*\?>',
                '<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">',
                xmlstr,
                count=1,
            )
            clean_xml = "\n".join(ln for ln in xmlstr.splitlines() if ln.strip()) + "\n"

            temp_path = self.config_path.with_name(f".{self.config_path.name}.tmp-{os.getpid()}")
            with open(temp_path, "w", encoding="utf-8") as f:
                f.write(clean_xml)
                f.flush()
                os.fsync(f.fileno())
            temp_path.replace(self.config_path)

            self.cache = state

            if legacy_absorbed:
                self._drop_legacy()

            self._refresh_cache_async()
            self._sync_gtk_async()

            return True, f"Successfully applied {len(changes)} font settings.", ""
        except Exception as e:
            return False, f"XML Generation Failed: {e}", ""

    def _rewrite_safe(self, match: ET.Element, state: dict[str, Any]) -> bool:
        """Normalize preserved legacy pattern rewrites so they cannot hijack
        generic family requests.

        Empirically verified against fontconfig 2.18.2: fontconfig expands a
        generic request (e.g. `fc-match sans-serif`) into a family list that
        contains the generic synonym AND every prefer-ed family from system
        alias chains (e.g. Arial/Helvetica for sans-serif, Times New Roman for
        serif, Liberation Serif from our own strong alias). A legacy rewrite
        like <test qual="any" name="family"><string>Arial</string></test> with
        <edit family mode="assign" binding="strong"> then rewrites EVERY
        generic request that merely mentions Arial in its expansion, silently
        overriding user choice.
        Fix: (1) restrict the test to qual="first" so the rewrite only fires
        when the requested family itself (first in the list) is the target;
        (2) drop rewrites whose target is a current alias prefer family or the
        known generic synonyms (those can never fire legitimately).
        """
        if match.get("target", "font") != "pattern":
            return True
        test_families: list[str] = []
        for t in match.findall("test"):
            if t.get("name") in ("family", "familylang"):
                el = t.find("string")
                if el is not None and el.text:
                    test_families.append(el.text.strip())
                t.set("qual", "first")

        if not test_families:
            return True
        prefer_families = {
            str(f).strip()
            for f in state.values()
            if isinstance(f, (str, list))
        }
        generic_synonyms = {"times new roman", "liberation serif", "vera serif"}
        for fam in test_families:
            if fam in self.ALIAS_CLASSES:
                return False
            if fam in prefer_families or fam.strip().lower() in generic_synonyms:
                return False
        return True

    def _append_render_edit(self, match: ET.Element, name: str, val: Any) -> None:
        edit = ET.SubElement(match, "edit", {"mode": "assign", "name": name})
        if isinstance(val, bool):
            kid = ET.SubElement(edit, "bool")
            kid.text = "true" if val else "false"
        elif isinstance(val, int):
            kid = ET.SubElement(edit, "int")
            kid.text = str(val)
        elif isinstance(val, float):
            kid = ET.SubElement(edit, "double")
            kid.text = f"{val:g}"
        elif str(val).lower() in self._KNOWN_CONSTS:
            kid = ET.SubElement(edit, "const")
            kid.text = str(val)
        else:
            kid = ET.SubElement(edit, "string")
            kid.text = str(val)

    def _drop_legacy(self) -> None:
        """Remove the legacy ~/.config/fontconfig/fonts.conf so its raw
        qual="any" + binding="strong" rewrites cannot fight the canonical
        config. No backup is kept (the canonical conf has all the state)."""
        legacy = Path("~/.config/fontconfig/fonts.conf").expanduser()
        if not legacy.exists() or legacy == self.config_path:
            return
        try:
            legacy.unlink()
        except OSError:
            pass

    def _refresh_cache_async(self) -> None:
        binary = shutil.which("fc-cache")
        if not binary:
            return
        try:
            subprocess.Popen(
                [binary, "-f"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except Exception:
            pass

    def sync_system_fonts(self, quiet: bool = False) -> bool:
        """Mirror the configured generic families to the toolkit layers that
        pin their own fonts (GTK settings.ini + dconf, Qt qt5ct/qt6ct) so a
        change is truly system-wide.

        fontconfig only governs generic requests; GTK apps read
        gtk-font-name and Qt apps read [Fonts] general/fixed, both of which
        are per-toolkit and separate from fontconfig.

        Reads families straight from self.cache (fresh after write_batch),
        reusing existing sizes when present.
        """
        family = ""
        mono = ""
        for key in ("sans-serif", "monospace"):
            val = self.cache.get(key)
            if not (isinstance(val, str) and val.strip()):
                state = self.load_state()
                val = state.get(key)
            if isinstance(val, str):
                value = val.strip()
                if key == "sans-serif":
                    family = value
                else:
                    mono = value

        if not family:
            if not quiet:
                print("[FontconfigEngine] No sans-serif family configured; toolkit sync skipped.")
            return False

        # --- GTK ---------------------------------------------------------
        gtk_ok = self._sync_gtk_toolkits(family, mono, quiet)

        # --- Qt (qt5ct / qt6ct) ------------------------------------------
        qt_ok = True
        for conf_path, version in (("~/.config/qt5ct/qt5ct.conf", "qt5"),
                                   ("~/.config/qt6ct/qt6ct.conf", "qt6")):
            try:
                qt_ok = self._patch_qt_conf(Path(conf_path).expanduser(),
                                            version, family, mono, quiet) and qt_ok
            except OSError as e:
                qt_ok = False
                if not quiet:
                    print(f"[-] {conf_path}: {e}")

        if not quiet and qt_ok:
            print("[i] Qt (qt5ct/qt6ct) fonts synced.")

        return gtk_ok or qt_ok

    # ------------------------------------------------------------------
    # GTK
    # ------------------------------------------------------------------
    def _sync_gtk_toolkits(self, family: str, mono: str, quiet: bool) -> bool:
        size = FontconfigEngine._existing_gtk_size("gtk-font-name=")
        entries = {f"gtk-font-name": f"{family} {size}"}
        if mono:
            mono_size = FontconfigEngine._existing_gtk_size("gtk-monospace-font-name=")
            if mono_size == str(FontconfigEngine._DEFAULT_GTK_SIZE):
                gs = shutil.which("gsettings")
                mono_size = self._gsettings_font_size(gs or "", "monospace-font-name")
            entries["gtk-monospace-font-name"] = f"{mono} {mono_size}"
        ok = True
        for path in FontconfigEngine._gtk_ini_paths():
            try:
                self._patch_gtk_ini(path, entries)
                if not quiet:
                    for k, v in entries.items():
                        print(f"[+] {path}: {k}={v}")
            except OSError as e:
                ok = False
                if not quiet:
                    print(f"[-] {path}: {e}")

        gs = shutil.which("gsettings")
        if gs:
            for key, fsize in (
                    ("font-name", size),
                    ("document-font-name", self._gsettings_font_size(gs, "document-font-name")),
                    ("monospace-font-name", self._gsettings_font_size(gs, "monospace-font-name"))):
                try:
                    fam = family if key != "monospace-font-name" else mono
                    if not fam:
                        continue
                    subprocess.run(
                        [gs, "set", "org.gnome.desktop.interface", key, f"{fam} {fsize}"],
                        check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    )
                    if not quiet:
                        print(f"[+] gsettings {key}: {fam} {fsize}")
                except Exception:
                    pass
        elif not quiet:
            print("[i] gsettings not available; GTK settings.ini only.")
        return ok

    # ------------------------------------------------------------------
    # Qt (qt5ct / qt6ct)
    # ------------------------------------------------------------------
    _QT_FONT_TEMPLATES = {
        "qt5": "family,size,-1,5,50,0,0,0,0,0",
        "qt6": "family,size,-1,5,400,0,0,0,0,0,0,0,0,0,0,1",
    }
    _QT_DEFAULT_SIZE = 12

    @staticmethod
    def _qt_swap_family(serialized: str, family: str) -> str:
        """Replace only the family field of a QFont serialization, keeping
        size / weight / flags intact."""
        parts = serialized.split(",", 1)
        parts[0] = family
        return ",".join(parts)

    @staticmethod
    def _qt_make_serial(version: str, family: str, size: str) -> str:
        template = FontconfigEngine._QT_FONT_TEMPLATES[version]
        return template.replace("family", family).replace("size", size)

    @staticmethod
    def _qt_size_from(serialized: str) -> str:
        if serialized:
            parts = serialized.split(",")
            if len(parts) > 1 and parts[1].strip().isdigit():
                return parts[1]
        return str(FontconfigEngine._QT_DEFAULT_SIZE)

    @staticmethod
    def _qt_slots(path: Path) -> dict[str, str]:
        """Extract existing [Fonts] general/fixed serializations."""
        if not path.is_file():
            return {}
        slots: dict[str, str] = {}
        in_fonts = False
        for line in path.read_text().splitlines():
            stripped = line.strip()
            if stripped.startswith("["):
                in_fonts = stripped == "[Fonts]"
                continue
            if in_fonts and "=" in line:
                key, _, val = line.partition("=")
                key = key.strip()
                if key in ("general", "fixed"):
                    slots[key] = val.strip().strip('"')
        return slots

    @staticmethod
    def _qt_write(path: Path, slots: dict[str, str]) -> None:
        """Rewrite a qt5ct/qt6ct.conf with updated [Fonts] general/fixed,
        preserving all other sections byte-for-byte (atomic tmp+rename so
        concurrent readers never see a half-written file)."""
        content = path.read_text() if path.is_file() else ""
        lines = content.splitlines()
        out: list[str] = []
        in_fonts = False
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("["):
                if in_fonts:
                    out.append("")  # blank line after Fonts block
                    in_fonts = False
                if stripped == "[Fonts]":
                    in_fonts = True
                    out.append("[Fonts]")
                    out.append(f'general="{slots["general"]}"')
                    out.append(f'fixed="{slots["fixed"]}"')
                    continue
                out.append(line)
                continue
            if in_fonts:
                continue  # drop original Fonts lines
            out.append(line)
        if not any(ln.strip() == "[Fonts]" for ln in out):
            if out:
                out.append("")
            out.append("[Fonts]")
            out.append(f'general="{slots["general"]}"')
            out.append(f'fixed="{slots["fixed"]}"')
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(out).rstrip("\n") + "\n")
            f.flush()
            os.fsync(f.fileno())
        tmp.replace(path)

    def _patch_qt_conf(self, conf: Path, version: str, sans: str, mono: str, quiet: bool) -> bool:
        """Update [Fonts] general/fixed in a qt5ct/qt6ct.conf file.

        general -> sans-serif family, fixed -> monospace family. Existing
        QFont serializations keep their size/weight/flags (only the family
        is swapped); new entries use a sensible default size."""
        try:
            slots = self._qt_slots(conf)
            general = slots.get("general", "")
            size = self._qt_size_from(general)
            slots["general"] = self._qt_swap_family(general, sans) if general else self._qt_make_serial(version, sans, size)
            fixed = slots.get("fixed", "")
            slots["fixed"] = self._qt_swap_family(fixed, mono) if fixed else self._qt_make_serial(version, mono, size)
            self._qt_write(conf, slots)
            if not quiet:
                print(f"[+] {conf}: general={slots['general']}")
            return True
        except OSError as e:
            if not quiet:
                print(f"[-] {conf}: {e}")
            return False

    _DEFAULT_GTK_SIZE = 11

    @classmethod
    def _gtk_ini_paths(cls) -> tuple[Path, Path]:
        """Resolve GTK settings.ini paths at call time so a later HOME switch
        (sudo/runuser/tests with a fake HOME) is honored."""
        return (
            Path("~/.config/gtk-3.0/settings.ini").expanduser(),
            Path("~/.config/gtk-4.0/settings.ini").expanduser(),
        )

    @classmethod
    def _existing_gtk_size(cls, keyline: str = "gtk-font-name=") -> str:
        """Reuse the size from any existing gtk-font-name / gtk-monospace-font-name."""
        for ini in FontconfigEngine._gtk_ini_paths():
            if not ini.is_file():
                continue
            try:
                for line in ini.read_text().splitlines():
                    if line.startswith(keyline):
                        parts = line.split("=", 1)[1].rsplit(" ", 1)
                        if len(parts) == 2 and parts[1].isdigit():
                            return parts[1]
            except OSError:
                continue
        return str(cls._DEFAULT_GTK_SIZE)

    @classmethod
    def _patch_gtk_ini(cls, path: Path, entries: dict[str, str]) -> None:
        content = path.read_text() if path.is_file() else ""
        out: list[str] = []
        replaced: set[str] = set()
        in_settings = False
        for line in content.splitlines():
            stripped = line.strip()
            if stripped == "[Settings]":
                in_settings = True
                out.append(line)
                continue
            if stripped.startswith("[") and in_settings:
                in_settings = False
            if in_settings:
                matched = next((k for k in entries if line.startswith(k + "=")), None)
                if matched:
                    out.append(f"{matched}={entries[matched]}")
                    replaced.add(matched)
                    continue
            out.append(line)
        missing = [k for k in entries if k not in replaced]
        if missing:
            if "[Settings]" in out:
                idx = out.index("[Settings]") + 1
                for k in missing:
                    out.insert(idx, f"{k}={entries[k]}")
            else:
                if out and not out[-1].strip():
                    out.pop()
                out.append("[Settings]")
                out.extend(f"{k}={entries[k]}" for k in entries)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
            f.flush()
            os.fsync(f.fileno())
        tmp.replace(path)

    @staticmethod
    def _gsettings_font_size(gs: str, key: str) -> str:
        try:
            out = subprocess.run(
                [gs, "get", "org.gnome.desktop.interface", key],
                capture_output=True, text=True, timeout=5,
            )
            val = out.stdout.strip().strip("'")
            parts = val.rsplit(" ", 1)
            if len(parts) == 2 and parts[1].isdigit():
                return parts[1]
        except Exception:
            pass
        return str(FontconfigEngine._DEFAULT_GTK_SIZE)

    def _sync_gtk_async(self) -> None:
        """Schedule the GTK/Qt/dconf sync on a single draining worker.

        The worker re-reads self.cache (the live, latest state) on every
        drained request, so a burst of rapid write_batch calls can never
        leave a stale family as the final written value (a naive
        thread-per-call would race on ordering)."""
        try:
            import threading

            self._sync_pending += 1
            if self._sync_worker_running:
                return
            self._sync_worker_running = True

            def worker() -> None:
                try:
                    while self._sync_pending > 0:
                        self._sync_pending -= 1
                        self.sync_system_fonts(quiet=True)
                finally:
                    self._sync_worker_running = False

            threading.Thread(target=worker, daemon=True).start()
        except Exception:
            pass

    def write_value(self, target_key: str, target_scope: str, new_value: str, item_type: str = "string") -> tuple[bool, str, str]:
        return self.write_batch([(target_key, target_scope, new_value, item_type)])


if __name__ == "__main__":
    # CLI entry: re-run the GTK/Qt/dconf sync from the config file
    # (used by the TUI's "Sync GTK & Qt Fonts" action).
    engine = FontconfigEngine()
    success = engine.sync_system_fonts(quiet=False)
    raise SystemExit(0 if success else 1)