"""Machine-readable spec for the functions injected into user scripts.

Single source of truth for the script checker (``zxtouch.checker``) and any
tooling that needs per-function parameter types / required flags / enum and
range constraints.

* Structure (parameter names, order, defaults, ``*args``) is introspected
  from :mod:`zxtouch.prelude`, so it can never drift from the implementation.
* Types and value constraints come from the tables in this module. Parameters
  without an explicit override fall back to a default/name heuristic
  (the Python port of ``ZXEditorParameterType`` in RemoteDashboardServer.m).
"""

from dataclasses import dataclass, replace
from typing import Any, Dict, List, Optional, Tuple

import functools
import inspect

NUMBER = "number"
TEXT = "text"
TABLE = "table"
BOOLEAN = "boolean"
ANY = "any"
FUNCTION = "function"

VALID_TYPES = frozenset({NUMBER, TEXT, TABLE, BOOLEAN, ANY, FUNCTION})


@dataclass(frozen=True)
class ParamSpec:
    name: str
    type: str = ANY
    required: bool = True
    default: Any = None
    enum: Optional[Tuple[Any, ...]] = None
    min: Optional[float] = None
    max: Optional[float] = None
    variadic: bool = False
    keyword: bool = False
    keyword_only: bool = False


@dataclass(frozen=True)
class FunctionSpec:
    name: str
    params: Tuple[ParamSpec, ...] = ()
    returns: str = "unknown"
    checkable: bool = True


# --------------------------------------------------------------- return types

RETURN_TYPES: Dict[str, str] = {
    "tap": "void",
    "touchDown": "void",
    "touchMove": "void",
    "touchUp": "void",
    "swipe": "void",
    "longPress": "void",
    "pinch": "void",
    "rotate": "void",
    "getColor": "number",
    "getColors": "number[]",
    "findColor": "[number, number][]",
    "findColors": "[number, number][]",
    "waitForColor": "boolean",
    "findImage": "object[]",
    "waitForImage": "object | null",
    "screenshot": "string",
    "deleteScreenshot": "boolean",
    "convertBase64": "string",
    "ocrText": "string",
    "findText": "object[]",
    "ocrFind": "[number, number, string]",
    "waitForText": "object | null",
    "tapImage": "object | null",
    "tapText": "object | null",
    "swipeUntilImage": "object | null",
    "swipeUntilText": "object | null",
    "dialogInput": "string",
    "dialogChoice": "number",
    "timestamp": "number",
    "md5": "string",
    "showOverlay": "boolean",
    "updateOverlay": "boolean",
    "hideOverlay": "boolean",
    "appRun": "boolean",
    "appKill": "boolean",
    "appClear": "boolean",
    "appState": "number",
    "openURL": "boolean",
    "inputText": "boolean",
    "typeText": "boolean",
    "showKeyboard": "boolean",
    "hideKeyboard": "boolean",
    "keyboardVisible": "boolean",
    "keyDown": "boolean",
    "keyUp": "boolean",
    "getClipboard": "string",
    "setClipboard": "boolean",
    "toast": "boolean",
    "alert": "boolean",
    "vibrate": "boolean",
    "log": "boolean",
    "sleep": "void",
    "usleep": "void",
    "randomSleep": "void",
    "screenSize": "object",
    "deviceInfo": "object",
    "httpGet": "HttpResponse",
    "httpPost": "HttpResponse",
    "readFile": "string",
    "writeFile": "boolean",
    "appendFile": "boolean",
    "jsonDecode": "object",
    "jsonEncode": "string",
    "randomInt": "number",
    "randomFloat": "number",
    "wifiInfo": "object",
    "getIP": "string",
    "setAirplaneMode": "boolean",
    "setCellularData": "boolean",
    "setProxySystem": "boolean",
    "clearProxySystem": "boolean",
    "recordStart": "boolean",
    "recordStop": "object[]",
    "recordPlay": "boolean",
    "recordSave": "boolean",
    "recordLoad": "object[]",
    "get_device": "object",
    "set_device": "void",
    "disconnect": "void",
    "setDebugVisual": "boolean",
    "clearDebugVisual": "boolean",
    "setDebugTouchLog": "boolean",
    "zxRange": "number[]",
    "zxConcat": "string",
    "zxUnpackMatch": "[boolean, number, number]",
    "fail": "void",
    "load": "object",
    "main": "void",
    "crane.list": "object[]",
    "crane.switch": "object",
    "crane.create": "object",
    "crane.delete": "object",
    "crane.wipe": "object",
    "crane.rename": "object",
    "crane.clearData": "object",
    "crane.backup": "object",
    "crane.restore": "object",
    "crane.size": "object",
}

# ------------------------------------------------------------- type overrides

# (function, parameter) -> type. Takes precedence over the name heuristic.
PARAM_TYPE_OVERRIDES: Dict[Tuple[str, str], str] = {
    ("tap", "x"): NUMBER,
    ("tap", "y"): NUMBER,
    ("tap", "finger"): NUMBER,
    ("getColor", "x"): NUMBER,
    ("getColor", "y"): NUMBER,
    ("getColors", "locations"): TABLE,
    ("findColor", "color"): NUMBER,
    ("findColor", "count"): NUMBER,
    ("findColor", "region"): TABLE,
    ("findColor", "tolerance"): NUMBER,
    ("findColors", "pattern"): TABLE,
    ("findColors", "count"): NUMBER,
    ("findColors", "region"): TABLE,
    ("findColors", "tolerance"): NUMBER,
    ("waitForColor", "x"): NUMBER,
    ("waitForColor", "y"): NUMBER,
    ("waitForColor", "color"): NUMBER,
    ("waitForColor", "timeout"): NUMBER,
    ("waitForColor", "interval"): NUMBER,
    ("waitForColor", "tolerance"): NUMBER,
    ("findImage", "path"): TEXT,
    ("findImage", "count"): NUMBER,
    ("findImage", "threshold"): NUMBER,
    ("findImage", "region"): TABLE,
    ("waitForImage", "path"): TEXT,
    ("waitForImage", "timeout"): NUMBER,
    ("waitForImage", "threshold"): NUMBER,
    ("waitForImage", "interval"): NUMBER,
    ("screenshot", "name"): TEXT,
    ("screenshot", "region"): TABLE,
    ("ocrText", "lang"): TEXT,
    ("findText", "case_sensitive"): BOOLEAN,
    ("findText", "lang"): TEXT,
    ("findText", "region"): TABLE,
    ("dialogChoice", "options"): ANY,
    ("showOverlay", "data"): TABLE,
    ("recordPlay", "events"): TABLE,
    ("recordPlay", "speed"): NUMBER,
    ("recordSave", "name"): TEXT,
    ("recordSave", "events"): TABLE,
    ("httpGet", "headers"): TABLE,
    ("httpGet", "timeout"): NUMBER,
    ("httpPost", "headers"): TABLE,
    ("httpPost", "timeout"): NUMBER,
    ("setProxySystem", "host"): TEXT,
    ("setProxySystem", "port"): NUMBER,
    ("setAirplaneMode", "enabled"): BOOLEAN,
    ("setAirplaneMode", "delay"): NUMBER,
    ("setCellularData", "enabled"): BOOLEAN,
    ("setCellularData", "delay"): NUMBER,
    ("setDebugVisual", "enabled"): BOOLEAN,
    ("setDebugVisual", "duration"): NUMBER,
    ("keyDown", "keyType"): TEXT,
    ("keyUp", "keyType"): TEXT,
    ("randomInt", "mins"): NUMBER,
    ("randomInt", "maxs"): NUMBER,
    ("randomFloat", "mins"): NUMBER,
    ("randomFloat", "maxs"): NUMBER,
    ("swipeUntilImage", "path"): TEXT,
    ("swipeUntilImage", "direction"): TEXT,
    ("swipeUntilImage", "maxSwipes"): NUMBER,
    ("swipeUntilImage", "threshold"): NUMBER,
    ("swipeUntilImage", "speed"): NUMBER,
    ("swipeUntilText", "direction"): TEXT,
    ("swipeUntilText", "maxSwipes"): NUMBER,
    ("swipeUntilText", "speed"): NUMBER,
    ("swipeUntilText", "lang"): TEXT,
    ("tapImage", "path"): TEXT,
    ("tapImage", "timeout"): NUMBER,
    ("tapImage", "threshold"): NUMBER,
    ("tapImage", "region"): TABLE,
    ("tapText", "index"): NUMBER,
    ("tapText", "region"): TABLE,
    ("tapText", "lang"): TEXT,
    ("crane.list", "bundleId"): TEXT,
    ("crane.switch", "bundleId"): TEXT,
    ("crane.switch", "name"): TEXT,
    ("crane.create", "bundleId"): TEXT,
    ("crane.create", "name"): TEXT,
    ("crane.delete", "bundleId"): TEXT,
    ("crane.delete", "name"): TEXT,
    ("crane.wipe", "bundleId"): TEXT,
    ("crane.wipe", "name"): TEXT,
    ("crane.rename", "bundleId"): TEXT,
    ("crane.rename", "old"): TEXT,
    ("crane.rename", "new"): TEXT,
    ("crane.clearData", "bundleId"): TEXT,
    ("crane.clearData", "container"): TEXT,
    ("crane.backup", "bundleId"): TEXT,
    ("crane.backup", "container"): TEXT,
    ("crane.backup", "name"): TEXT,
    ("crane.restore", "bundleId"): TEXT,
    ("crane.restore", "path"): TEXT,
    ("crane.size", "bundleId"): TEXT,
    ("crane.size", "container"): TEXT,
}

# Name-based fallbacks for parameters that recur across many functions.
PARAM_TYPE_BY_NAME: Dict[str, str] = {
    "region": TABLE,
    "pattern": TABLE,
    "headers": TABLE,
    "options": TABLE,
    "events": TABLE,
    "locations": TABLE,
}

# ------------------------------------------------------------- value constraints

DIRECTION = ("up", "down", "left", "right")
KEY_TYPE = ("home", "volumeUp", "volumeDown", "power")

# (function, parameter) -> constraint dict {"enum"|"min"|"max"}.
CONSTRAINTS: Dict[Tuple[str, str], Dict[str, Any]] = {
    ("swipeUntilImage", "direction"): {"enum": DIRECTION},
    ("swipeUntilText", "direction"): {"enum": DIRECTION},
    ("keyDown", "keyType"): {"enum": KEY_TYPE},
    ("keyUp", "keyType"): {"enum": KEY_TYPE},
    ("findImage", "threshold"): {"min": 0, "max": 1},
    ("waitForImage", "threshold"): {"min": 0, "max": 1},
    ("tapImage", "threshold"): {"min": 0, "max": 1},
    ("swipeUntilImage", "threshold"): {"min": 0, "max": 1},
    ("findColor", "tolerance"): {"min": 0},
    ("findColors", "tolerance"): {"min": 0},
    ("setProxySystem", "port"): {"min": 1, "max": 65535},
}

# Constraints intentionally NOT applied, because the implementation accepts the
# value instead of failing. Flagging them would be a false positive:
#   tapText.index        -> `if idx <= 0: idx = 1` (0 = first match, documented)
#   findColor.count      -> `want = max(1, int(count))`
#   findColors.count     -> accepted, unused by the implementation
#   findImage.count      -> `want = max(1, int(count))`
#   setDebugVisual.duration -> clamped to 0.3..5 (documented range)
#   randomInt/randomFloat mins/maxs -> `random.randint/uniform` accept negatives
#   count / mins / maxs / index are therefore absent from _NON_NEGATIVE_PARAMS.

# Parameter names that are finger ids on touch primitives (0-9).
_FINGER_PARAMS = ("finger", "fid")

# Parameter names that must be non-negative. Kept to values where a negative
# number is meaningless and is NOT clamped by the implementation.
_NON_NEGATIVE_PARAMS = (
    "x", "y", "w", "h", "x1", "y1", "x2", "y2", "timeout", "interval",
    "duration", "delay", "speed", "scale", "seconds", "microseconds",
    "radius", "maxSwipes", "threshold", "tolerance",
)

# ------------------------------------------------------------- name heuristic

_TABLE_NAME_HINTS = ("region", "pattern", "location", "header", "body", "option", "events", "data")
_BOOLEAN_NAME_HINTS = ("enabled", "case_sensitive", "debug", "visible", "force")
_NUMBER_NAME_HINTS = (
    "x", "y", "w", "h", "fid", "count", "timeout", "interval", "duration",
    "delay", "speed", "threshold", "tolerance", "scale", "angle", "seconds",
    "microseconds", "mins", "maxs", "index", "port", "radius",
)
_TEXT_NAME_HINTS = ("path", "url", "text", "message", "title", "name", "key", "direction", "lang", "bundleid", "host")


def _type_from_default(default: Any) -> Optional[str]:
    if isinstance(default, bool):
        return BOOLEAN
    if isinstance(default, str):
        return TEXT
    if isinstance(default, (int, float)):
        return NUMBER
    if isinstance(default, (list, tuple, dict, set)):
        return TABLE
    if default is None:
        return None
    return None


def _type_from_name(name: str) -> str:
    lower = (name or "").lower()
    if any(h in lower for h in _TABLE_NAME_HINTS):
        return TABLE
    if any(h in lower for h in _BOOLEAN_NAME_HINTS):
        return BOOLEAN
    if any(lower == h or lower.endswith(h.capitalize()) or lower.endswith("_" + h) for h in _NUMBER_NAME_HINTS):
        return NUMBER
    if any(lower == h or lower.endswith(h.capitalize()) or lower.endswith("_" + h) for h in _TEXT_NAME_HINTS):
        return TEXT
    return ANY


def _resolve_type(func_name: str, param: ParamSpec) -> str:
    override = PARAM_TYPE_OVERRIDES.get((func_name, param.name))
    if override:
        return override
    if param.variadic or param.keyword:
        return ANY
    if param.name in PARAM_TYPE_BY_NAME:
        return PARAM_TYPE_BY_NAME[param.name]
    if param.name in _FINGER_PARAMS:
        return NUMBER
    from_default = _type_from_default(param.default) if not param.required else None
    if from_default:
        return from_default
    guess = _type_from_name(param.name)
    if guess != ANY:
        return guess
    return ANY


def _apply_constraints(func_name: str, param: ParamSpec) -> ParamSpec:
    constraint = CONSTRAINTS.get((func_name, param.name))
    if constraint is None and param.name in _FINGER_PARAMS:
        constraint = {"min": 0, "max": 9}
    if constraint is None and param.name in _NON_NEGATIVE_PARAMS and param.type in (NUMBER, ANY):
        constraint = {"min": 0}
    if not constraint:
        return param
    return replace(
        param,
        enum=tuple(constraint["enum"]) if "enum" in constraint else param.enum,
        min=constraint.get("min", param.min),
        max=constraint.get("max", param.max),
    )


def _signature_params(func: Any) -> Optional[List[ParamSpec]]:
    try:
        sig = inspect.signature(func)
    except (TypeError, ValueError):
        return None
    params: List[ParamSpec] = []
    for p in sig.parameters.values():
        if p.kind == p.VAR_POSITIONAL:
            params.append(ParamSpec(p.name, ANY, required=False, variadic=True))
        elif p.kind == p.VAR_KEYWORD:
            params.append(ParamSpec(p.name, ANY, required=False, keyword=True))
        elif p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD, p.KEYWORD_ONLY):
            required = p.default is inspect.Parameter.empty
            params.append(ParamSpec(
                p.name,
                ANY,
                required=required,
                default=None if required else p.default,
                keyword_only=(p.kind == p.KEYWORD_ONLY),
            ))
    return params


def _build_spec(name: str, func: Any) -> FunctionSpec:
    params = _signature_params(func)
    if params is None:
        return FunctionSpec(name, (), RETURN_TYPES.get(name, "unknown"), checkable=False)
    resolved = tuple(_apply_constraints(name, replace(p, type=_resolve_type(name, p))) for p in params)
    return FunctionSpec(name, resolved, RETURN_TYPES.get(name, "unknown"), checkable=True)


@functools.lru_cache(maxsize=1)
def _build_all() -> Dict[str, FunctionSpec]:
    specs: Dict[str, FunctionSpec] = {}
    try:
        from zxtouch import prelude
    except Exception:
        return specs

    for name in getattr(prelude, "__all__", []):
        obj = getattr(prelude, name, None)
        if obj is None:
            continue
        specs[name] = _build_spec(name, obj)

    crane = getattr(prelude, "crane", None)
    if crane is not None:
        for attr in dir(type(crane)):
            if attr.startswith("_"):
                continue
            member = getattr(crane, attr)
            if not callable(member):
                continue
            specs["crane." + attr] = _build_spec("crane." + attr, member)
    return specs


def specs() -> Dict[str, FunctionSpec]:
    """Return every known function/namespace entry, keyed by name."""
    return _build_all()


def lookup(name: str) -> Optional[FunctionSpec]:
    return _build_all().get(name)


@functools.lru_cache(maxsize=1)
def valid_globals() -> frozenset:
    """Names user scripts may reference: prelude exports plus Python builtins."""
    import builtins

    names = set()
    try:
        from zxtouch import prelude
        names.update(getattr(prelude, "__all__", []))
    except Exception:
        pass
    names.update(dir(builtins))
    names.update({"True", "False", "None", "self", "__name__", "__file__", "__doc__"})
    return frozenset(names)


@functools.lru_cache(maxsize=1)
def namespace_roots() -> frozenset:
    """Base names that own dotted API entries (e.g. ``crane.list``)."""
    return frozenset({name.split(".", 1)[0] for name in _build_all() if "." in name})


def is_known_name(name: str) -> bool:
    return name in valid_globals() or name in _build_all() or name in namespace_roots()


def spec_summary() -> Dict[str, Any]:
    """Small debug/sync payload used by tests."""
    return {name: spec for name, spec in _build_all().items()}
