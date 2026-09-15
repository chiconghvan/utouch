"""Unit tests for zxtouch.apispec — the spec table that drives the checker.

Run:  python -m pytest tools/tests/test_apispec.py -q
"""
import inspect
import sys
from pathlib import Path

PY_MOD = Path(__file__).resolve().parents[2] / "layout" / "usr" / "share" / "zxtouch" / "python"
sys.path.insert(0, str(PY_MOD))

from zxtouch import apispec, prelude  # noqa: E402


def test_every_export_has_a_spec():
    specs = apispec.specs()
    missing = [name for name in prelude.__all__ if name not in specs]
    assert missing == []


def test_checkable_specs_match_prelude_signatures():
    specs = apispec.specs()
    for name in prelude.__all__:
        spec = specs[name]
        if not spec.checkable:
            continue
        signature = inspect.signature(getattr(prelude, name))
        expected = [
            p for p in signature.parameters.values()
            if p.kind in (p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD, p.KEYWORD_ONLY)
        ]
        assert [p.name for p in spec.params if not p.variadic and not p.keyword] == [p.name for p in expected]
        for resolved, original in zip(spec.params, expected):
            assert resolved.required == (original.default is inspect.Parameter.empty)


def test_crane_namespace_is_exposed():
    specs = apispec.specs()
    for attr in ("list", "switch", "create", "delete", "wipe", "rename", "clearData", "backup", "restore", "size"):
        assert "crane." + attr in specs
    assert "crane" in apispec.namespace_roots()


def test_unknown_not_in_valid_globals():
    assert apispec.is_known_name("tap")
    assert apispec.is_known_name("print")
    assert apispec.is_known_name("crane")
    assert not apispec.is_known_name("taap")
    assert not apispec.is_known_name("nonexistent")


def test_key_type_resolution():
    specs = apispec.specs()
    tap = {p.name: p for p in specs["tap"].params}
    assert tap["x"].type == apispec.NUMBER
    assert tap["finger"].type == apispec.NUMBER

    find_image = {p.name: p for p in specs["findImage"].params}
    assert find_image["path"].type == apispec.TEXT
    assert find_image["region"].type == apispec.TABLE


def test_key_constraints():
    specs = apispec.specs()
    direction = {p.name: p for p in specs["swipeUntilImage"].params}["direction"]
    assert direction.enum == ("up", "down", "left", "right")

    threshold = {p.name: p for p in specs["findImage"].params}["threshold"]
    assert threshold.min == 0 and threshold.max == 1

    finger = {p.name: p for p in specs["tap"].params}["finger"]
    assert finger.min == 0 and finger.max == 9

    port = {p.name: p for p in specs["setProxySystem"].params}["port"]
    assert port.min == 1 and port.max == 65535


def test_required_and_optional_flags():
    specs = apispec.specs()
    tap = {p.name: p for p in specs["tap"].params}
    assert tap["x"].required and tap["y"].required
    assert not tap["finger"].required

    swipe = {p.name: p for p in specs["swipe"].params}
    assert swipe["x1"].required
    assert not swipe["duration"].required


def test_variadic_params_detected():
    specs = apispec.specs()
    options = specs["dialogChoice"].params[-1]
    assert options.variadic

    log_args = specs["log"].params[-1]
    assert log_args.variadic
