"""Unit tests for zxtouch.checker — the static script analyzer.

Run:  python -m pytest tools/tests/test_checker.py -q
"""
import json
import sys
from pathlib import Path

PY_MOD = Path(__file__).resolve().parents[2] / "layout" / "usr" / "share" / "zxtouch" / "python"
sys.path.insert(0, str(PY_MOD))

from zxtouch import checker  # noqa: E402


def codes(result):
    return [(d["code"], d["severity"]) for d in result["diagnostics"]]


def first(result, code):
    for diagnostic in result["diagnostics"]:
        if diagnostic["code"] == code:
            return diagnostic
    return None


def test_clean_script_has_no_diagnostics():
    source = (
        "tap(200, 300)\n"
        "sleep(0.5)\n"
        "colour = getColor(195, 400)\n"
        "if colour != 0xFFFFFF:\n"
        "    log('pressed')\n"
        "for i in range(3):\n"
        "    swipe(200, 600, 200, 200, 0.3)\n"
    )
    result = checker.analyze(source)
    assert result["diagnostics"] == []
    assert result["ok"] is True


def test_unknown_function_reports_e200_with_suggestion():
    result = checker.analyze("taap(200, 300)\n")
    diagnostic = first(result, "E200")
    assert diagnostic is not None
    assert "'taap'" in diagnostic["message"]
    assert "'tap'" in diagnostic["message"]


def test_missing_required_argument():
    result = checker.analyze("tap(200)\n")
    assert first(result, "E202") is not None


def test_too_many_positional_arguments():
    result = checker.analyze("tap(1, 2, 3, 4)\n")
    assert first(result, "E201") is not None


def test_unknown_keyword():
    result = checker.analyze("tap(200, 300, foo=1)\n")
    assert first(result, "E203") is not None


def test_duplicate_argument_between_positional_and_keyword():
    result = checker.analyze("tap(200, 300, x=1)\n")
    assert first(result, "E204") is not None


def test_literal_type_mismatch_is_warning():
    result = checker.analyze("tap('200', 300)\n")
    diagnostic = first(result, "W300")
    assert diagnostic is not None
    assert diagnostic["severity"] == "warning"
    assert result["ok"] is True


def test_table_literal_accepted_for_region():
    result = checker.analyze("findColor(0xFFFFFF, region={'x': 1, 'y': 2, 'w': 3, 'h': 4})\n")
    assert first(result, "W300") is None


def test_enum_violation():
    result = checker.analyze("swipeUntilImage('a.png', 'top')\n")
    assert first(result, "E301") is not None


def test_range_violation():
    assert first(checker.analyze("findImage('a.png', threshold=2)\n"), "E302") is not None
    assert first(checker.analyze("setProxySystem('host', 700000)\n"), "E302") is not None
    assert first(checker.analyze("tap('a', 1, finger=99)\n"), "E302") is not None


def test_valid_enum_and_range_values_pass():
    assert checker.analyze("swipeUntilImage('a.png', 'down')\n")["diagnostics"] == []
    assert checker.analyze("findImage('a.png', threshold=0.9)\n")["diagnostics"] == []


def test_syntax_error_reports_e100():
    result = checker.analyze("def f(:\n    pass\n")
    diagnostic = first(result, "E100")
    assert diagnostic is not None
    assert diagnostic["line"] == 1
    assert result["ok"] is False


def test_crane_unknown_method_is_reported():
    result = checker.analyze("crane.foo('a')\n")
    assert first(result, "E200") is not None


def test_crane_known_method_is_clean():
    assert checker.analyze("crane.list('com.apple.mobilesafari')\n")["diagnostics"] == []


def test_user_defined_function_and_import_are_resolved():
    source = (
        "import math\n"
        "from time import sleep as nap\n"
        "\n"
        "def helper(value):\n"
        "    return math.sqrt(value)\n"
        "\n"
        "result = helper(4)\n"
        "nap(0.1)\n"
    )
    assert checker.analyze(source)["diagnostics"] == []


def test_method_calls_on_locals_are_not_flagged():
    assert checker.analyze("items = [1, 2]\nitems.append(3)\n")["diagnostics"] == []


def test_callable_parameter_is_not_unknown():
    source = (
        "def run(callback, *args, **kwargs):\n"
        "    return callback(*args, **kwargs)\n"
    )
    assert checker.analyze(source)["diagnostics"] == []


def test_comprehension_and_exception_names_are_scoped():
    source = (
        "def load(items):\n"
        "    return [item for item in items]\n"
        "try:\n"
        "    values = load([1, 2])\n"
        "except Exception as err:\n"
        "    log(err)\n"
    )
    assert checker.analyze(source)["diagnostics"] == []


def test_positions_account_for_non_ascii():
    result = checker.analyze("log('xin chào')\ntaap(1, 2)\n")
    diagnostic = first(result, "E200")
    assert diagnostic["line"] == 2
    assert diagnostic["column"] == 1


def test_end_positions_are_within_line():
    result = checker.analyze("taap(1, 2)\n")
    diagnostic = first(result, "E200")
    assert diagnostic["endLine"] == 1
    assert diagnostic["endColumn"] > diagnostic["column"]


def test_empty_source_is_valid():
    assert checker.analyze("")["diagnostics"] == []


def test_analyze_never_raises_on_garbage():
    for source in (")))", "\x00\x01", "def ", "class", "1 +", "\\"):
        checker.analyze(source)  # must not raise


def test_variadic_argument_accepts_extras():
    assert checker.analyze("dialogChoice('Pick', 'a', 'b', 'c')\n")["diagnostics"] == []


def test_cli_writes_report_file(tmp_path):
    script = tmp_path / "entry.py"
    script.write_text("taap(1, 2)\n", encoding="utf-8")
    exit_code = checker.main(["zxtouch.checker", str(script)])
    assert exit_code == 0
    report = json.loads((tmp_path / "entry.py.diag.json").read_text(encoding="utf-8"))
    assert report["diagnostics"][0]["code"] == "E200"


def test_cli_missing_file_returns_error():
    assert checker.main(["zxtouch.checker", "does-not-exist.py"]) == 2
