"""Static checker for ZXTouch user scripts.

Evaluates a script against the function catalog in :mod:`zxtouch.apispec`:

* **structure** — Python syntax errors (indent, brackets, blocks);
* **API usage** — unknown function, wrong arity, missing required argument,
  unknown/duplicate keyword;
* **data** — literal argument that does not match the parameter type;
* **values** — literal outside a parameter's enum or numeric range.

Run as a CLI to produce a JSON report:

    python3 -m zxtouch.checker <script.py>

writes ``<script.py>.diag.json`` (see :func:`analyze` for the schema). The
report is consumed by the native editor (via the SpringBoard :6000 socket)
and the web dashboard (``POST /api/editor/validate``).
"""

from __future__ import annotations

import ast
import difflib
import json
import os
import sys
from typing import Any, Dict, List, Optional

from zxtouch import apispec

MAX_DIAGNOSTICS = 200

SEVERITY_ERROR = "error"
SEVERITY_WARNING = "warning"
SEVERITY_INFO = "info"


# --------------------------------------------------------------------- helpers

def _make_diagnostic(code: str, severity: str, node: ast.AST, lines: List[str], message: str) -> Dict[str, Any]:
    line, column, end_line, end_column = _node_position(node, lines)
    return {
        "code": code,
        "severity": severity,
        "line": line,
        "column": column,
        "endLine": end_line,
        "endColumn": end_column,
        "message": message,
    }


def _byte_to_char(text: str, byte_column: int) -> int:
    if byte_column <= 0:
        return 0
    data = text.encode("utf-8")
    if byte_column >= len(data):
        return len(text)
    return len(data[:byte_column].decode("utf-8", "ignore"))


def _node_position(node: ast.AST, lines: List[str]) -> tuple:
    line = getattr(node, "lineno", 1) or 1
    end_line = getattr(node, "end_lineno", line) or line
    start_text = lines[line - 1] if 0 <= line - 1 < len(lines) else ""
    end_text = lines[end_line - 1] if 0 <= end_line - 1 < len(lines) else start_text
    column = _byte_to_char(start_text, getattr(node, "col_offset", 0) or 0) + 1
    end_column = _byte_to_char(end_text, getattr(node, "end_col_offset", 0) or 0) + 1
    if end_line == line and end_column <= column:
        end_column = column + 1
    return line, column, end_line, end_column


def _literal_type(node: ast.AST) -> Optional[str]:
    """Infer the apispec type of a literal expression, or None when unknown."""
    if isinstance(node, ast.Constant):
        value = node.value
        if isinstance(value, bool):
            return apispec.BOOLEAN
        if isinstance(value, (int, float)):
            return apispec.NUMBER
        if isinstance(value, str):
            return apispec.TEXT
        return None
    if isinstance(node, (ast.List, ast.Tuple, ast.Dict, ast.Set)):
        return apispec.TABLE
    if isinstance(node, ast.JoinedStr):
        return apispec.TEXT
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
        return _literal_type(node.operand)
    return None


def _literal_value(node: ast.AST) -> tuple:
    """Return (ok, value) for scalar literals usable in enum/range checks."""
    if isinstance(node, ast.Constant):
        if isinstance(node.value, (bool, int, float, str)):
            return True, node.value
        return False, None
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        ok, value = _literal_value(node.operand)
        if ok and isinstance(value, (int, float)) and not isinstance(value, bool):
            return True, -value
    return False, None


_TYPE_LABELS = {
    apispec.NUMBER: "số (number)",
    apispec.TEXT: "chuỗi (text)",
    apispec.TABLE: "bảng (table)",
    apispec.BOOLEAN: "logic (boolean)",
}


# ----------------------------------------------------------------- scope names

class _ScopeCollector(ast.NodeVisitor):
    """Collect every name a script defines, anywhere in the module.

    Over-approximating (treating function locals as module-level) keeps the
    unknown-name check from firing on names that are legitimately defined.
    """

    def __init__(self) -> None:
        self.names: set = set()

    def _add_target(self, target: ast.AST) -> None:
        if isinstance(target, ast.Name):
            self.names.add(target.id)
        elif isinstance(target, (ast.Tuple, ast.List)):
            for element in target.elts:
                self._add_target(element)
        elif isinstance(target, ast.Starred):
            self._add_target(target.value)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self.names.add(node.name)
        self.generic_visit(node)

    visit_AsyncFunctionDef = visit_FunctionDef  # type: ignore[assignment]

    def visit_arg(self, node: ast.arg) -> None:
        # Covers plain parameters, *args / **kwargs and lambda arguments, so a
        # callback parameter used as a call target is not reported as unknown.
        self.names.add(node.arg)

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        self.names.add(node.name)
        self.generic_visit(node)

    def visit_Lambda(self, node: ast.Lambda) -> None:
        self._add_arguments(node.args)
        self.generic_visit(node)

    def _add_arguments(self, arguments: ast.arguments) -> None:
        for arg in list(arguments.posonlyargs) + list(arguments.args) + list(arguments.kwonlyargs):
            self.names.add(arg.arg)
        if arguments.vararg:
            self.names.add(arguments.vararg.arg)
        if arguments.kwarg:
            self.names.add(arguments.kwarg.arg)

    def visit_Assign(self, node: ast.Assign) -> None:
        for target in node.targets:
            self._add_target(target)
        self.generic_visit(node)

    def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
        self._add_target(node.target)
        self.generic_visit(node)

    def visit_AugAssign(self, node: ast.AugAssign) -> None:
        self._add_target(node.target)
        self.generic_visit(node)

    def visit_For(self, node: ast.For) -> None:
        self._add_target(node.target)
        self.generic_visit(node)

    visit_AsyncFor = visit_For  # type: ignore[assignment]

    def visit_With(self, node: ast.With) -> None:
        for item in node.items:
            if item.optional_vars is not None:
                self._add_target(item.optional_vars)
        self.generic_visit(node)

    visit_AsyncWith = visit_With  # type: ignore[assignment]

    def visit_Import(self, node: ast.Import) -> None:
        for alias in node.names:
            self.names.add((alias.asname or alias.name).split(".")[0])

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        for alias in node.names:
            self.names.add(alias.asname or alias.name)

    def visit_Global(self, node: ast.Global) -> None:
        self.names.update(node.names)

    def visit_Nonlocal(self, node: ast.Nonlocal) -> None:
        self.names.update(node.names)

    def visit_comprehension(self, node: ast.comprehension) -> None:
        self._add_target(node.target)
        self.generic_visit(node)

    def visit_ExceptHandler(self, node: ast.ExceptHandler) -> None:
        if node.name:
            self.names.add(node.name)
        self.generic_visit(node)


# ----------------------------------------------------------------- the checker

class _Checker(ast.NodeVisitor):
    def __init__(self, source: str) -> None:
        self.lines = source.splitlines()
        self.diagnostics: List[Dict[str, Any]] = []
        self.scope = _ScopeCollector()
        self.specs = apispec.specs()

    # -- reporting ---------------------------------------------------------

    def _report(self, code: str, severity: str, node: ast.AST, message: str) -> None:
        if len(self.diagnostics) >= MAX_DIAGNOSTICS:
            return
        self.diagnostics.append(_make_diagnostic(code, severity, node, self.lines, message))

    # -- call handling -----------------------------------------------------

    def visit_Call(self, node: ast.Call) -> None:
        self.generic_visit(node)  # check nested calls first
        resolved = self._resolve_target(node.func)
        if resolved is None:
            return
        if resolved in self.specs:
            self._check_arguments(resolved, node)
            return
        # Unknown: only complain when the base name really is unresolved.
        base = resolved.split(".", 1)[0]
        if base in apispec.namespace_roots():
            if "." in resolved:
                self._report("E200", SEVERITY_ERROR, node.func, self._unknown_message(resolved))
            return
        if base in self.scope.names:
            return
        if base in apispec.valid_globals():
            return
        self._report("E200", SEVERITY_ERROR, node.func, self._unknown_message(base))

    @staticmethod
    def _resolve_target(func: ast.AST) -> Optional[str]:
        if isinstance(func, ast.Name):
            return func.id
        if isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name):
            return func.value.id + "." + func.attr
        return None

    def _unknown_message(self, name: str) -> str:
        candidates = list(self.specs.keys())
        close = difflib.get_close_matches(name, candidates, n=1, cutoff=0.72)
        if close:
            return "Không tìm thấy hàm '%s'. Có phải bạn muốn '%s'?" % (name, close[0])
        return "Không tìm thấy hàm '%s' trong danh sách API." % name

    # -- argument validation ----------------------------------------------

    def _check_arguments(self, name: str, node: ast.Call) -> None:
        spec = self.specs[name]
        if not spec.checkable:
            return
        params = list(spec.params)
        positional_params = [p for p in params if not p.keyword and not p.keyword_only]
        variadic = next((p for p in params if p.variadic), None)
        has_var_keyword = any(p.keyword for p in params)

        has_star = any(isinstance(arg, ast.Starred) for arg in node.args)
        has_double_star = any(keyword.arg is None for keyword in node.keywords)

        provided: Dict[str, ast.AST] = {}
        positional_count = len(node.args)
        for index, arg in enumerate(node.args):
            if index < len(positional_params):
                provided[positional_params[index].name] = arg

        if not has_star and not has_double_star:
            if variadic is None and positional_count > len(positional_params):
                self._report(
                    "E201", SEVERITY_ERROR, node,
                    "Hàm '%s' chỉ nhận %d tham số, nhưng bạn truyền %d." % (
                        name, len(positional_params), positional_count),
                )

        positional_names = {positional_params[i].name for i in range(min(positional_count, len(positional_params)))}

        for keyword in node.keywords:
            if keyword.arg is None:
                continue
            if keyword.arg in positional_names:
                self._report(
                    "E204", SEVERITY_ERROR, keyword.value,
                    "Tham số '%s' của '%s' bị truyền hai lần (vị trí và tên)." % (keyword.arg, name),
                )
                continue
            if keyword.arg not in {p.name for p in params}:
                if not has_var_keyword:
                    self._report(
                        "E203", SEVERITY_ERROR, keyword.value,
                        "Hàm '%s' không có tham số tên '%s'. Các tham số hợp lệ: %s." % (
                            name, keyword.arg, ", ".join(p.name for p in params) or "(không có)"),
                    )
                continue
            provided[keyword.arg] = keyword.value

        if not has_star and not has_double_star:
            for param in params:
                if param.required and param.name not in provided and not param.variadic and not param.keyword:
                    self._report(
                        "E202", SEVERITY_ERROR, node,
                        "Hàm '%s' thiếu tham số bắt buộc '%s'." % (name, param.name),
                    )

        by_name = {p.name: p for p in params}
        for arg_name, arg_node in provided.items():
            param = by_name.get(arg_name)
            if param is not None:
                self._check_value(name, param, arg_node)

    def _check_value(self, name: str, param: apispec.ParamSpec, node: ast.AST) -> None:
        if isinstance(node, ast.Starred):
            return
        literal = _literal_type(node)
        declared = param.type not in (apispec.ANY, apispec.FUNCTION, "unknown")
        if declared and literal is not None and literal != param.type:
            self._report(
                "W300", SEVERITY_WARNING, node,
                "Tham số '%s' của '%s' cần %s nhưng nhận %s." % (
                    param.name, name,
                    _TYPE_LABELS.get(param.type, param.type),
                    _TYPE_LABELS.get(literal, literal)),
            )
            return

        # Enum/range checks run even for `any` parameters: direction/keyType
        # style arguments are strings whose accepted values are still known.
        ok, value = _literal_value(node)
        if not ok or value is None or isinstance(value, bool):
            return
        if param.enum is not None and value not in param.enum:
            self._report(
                "E301", SEVERITY_ERROR, node,
                "Tham số '%s' của '%s' chỉ nhận %s (bạn truyền %r)." % (
                    param.name, name, ", ".join(repr(v) for v in param.enum), value),
            )
            return
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            if param.min is not None and value < param.min:
                self._report(
                    "E302", SEVERITY_ERROR, node,
                    "Tham số '%s' của '%s' phải >= %s (bạn truyền %s)." % (
                        param.name, name, param.min, value),
                )
            elif param.max is not None and value > param.max:
                self._report(
                    "E302", SEVERITY_ERROR, node,
                    "Tham số '%s' của '%s' phải <= %s (bạn truyền %s)." % (
                        param.name, name, param.max, value),
                )


# ------------------------------------------------------------------- public API

def analyze(source: str = "", filename: str = "<editor>") -> Dict[str, Any]:
    """Analyse ``source`` and return ``{"ok": bool, "diagnostics": [...]}``."""
    source = source or ""
    try:
        tree = ast.parse(source, filename=filename)
    except SyntaxError as exc:
        lines = source.splitlines() or [""]
        line = exc.lineno or 1
        text = lines[line - 1] if 0 <= line - 1 < len(lines) else ""
        column = max(1, exc.offset or 1)
        message = exc.msg or "Cú pháp không hợp lệ."
        return {
            "ok": False,
            "diagnostics": [{
                "code": "E100",
                "severity": SEVERITY_ERROR,
                "line": line,
                "column": column,
                "endLine": line,
                "endColumn": max(column + 1, len(text) + 1),
                "message": "Lỗi cú pháp: %s" % message,
            }],
        }

    checker = _Checker(source)
    checker.scope.visit(tree)
    try:
        checker.visit(tree)
    except RecursionError:
        return {"ok": False, "diagnostics": [{
            "code": "E100",
            "severity": SEVERITY_ERROR,
            "line": 1,
            "column": 1,
            "endLine": 1,
            "endColumn": 2,
            "message": "Script quá phức tạp để phân tích.",
        }]}

    diagnostics = sorted(
        checker.diagnostics,
        key=lambda item: (item["line"], item["column"], item["code"]),
    )
    if len(diagnostics) >= MAX_DIAGNOSTICS:
        diagnostics.append({
            "code": "I900",
            "severity": SEVERITY_INFO,
            "line": 1,
            "column": 1,
            "endLine": 1,
            "endColumn": 2,
            "message": "Đã đạt giới hạn %d cảnh báo; sửa các lỗi trên rồi kiểm tra lại." % MAX_DIAGNOSTICS,
        })
    return {"ok": not any(item["severity"] == SEVERITY_ERROR for item in diagnostics),
            "diagnostics": diagnostics}


def summarize(result: Dict[str, Any]) -> str:
    errors = sum(1 for item in result["diagnostics"] if item["severity"] == SEVERITY_ERROR)
    warnings = sum(1 for item in result["diagnostics"] if item["severity"] == SEVERITY_WARNING)
    if not errors and not warnings:
        return "OK — không phát hiện lỗi."
    return "%d lỗi, %d cảnh báo." % (errors, warnings)


def check_file(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        return analyze(handle.read(), filename=path)


# ------------------------------------------------------------------------- CLI

def _safe_print(text: str) -> None:
    """Print without ever raising on a non-UTF-8 console (device log pipe)."""
    try:
        print(text)
    except UnicodeEncodeError:
        encoding = getattr(sys.stdout, "encoding", None) or "ascii"
        sys.stdout.write(text.encode(encoding, "replace").decode(encoding, "replace") + "\n")


def main(argv: Optional[List[str]] = None) -> int:
    argv = list(sys.argv if argv is None else argv)
    if len(argv) < 2:
        sys.stderr.write("Usage: python -m zxtouch.checker <script.py>\n")
        return 2
    # The device runs this with stdout either discarded or piped through a
    # locale that may not be UTF-8; force a lossy UTF-8 stream up front.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    path = argv[1]
    if not os.path.isfile(path):
        sys.stderr.write("zxtouch.checker: file not found: %s\n" % path)
        return 2
    try:
        result = check_file(path)
    except Exception as exc:  # never let the checker crash the caller
        result = {"ok": False, "diagnostics": [{
            "code": "E100",
            "severity": SEVERITY_ERROR,
            "line": 1,
            "column": 1,
            "endLine": 1,
            "endColumn": 2,
            "message": "Không phân tích được script: %s" % exc,
        }]}

    out_path = path + ".diag.json"
    tmp_path = out_path + ".tmp"
    try:
        with open(tmp_path, "w", encoding="utf-8") as handle:
            json.dump(result, handle, ensure_ascii=False)
        os.replace(tmp_path, out_path)
    except OSError as exc:
        sys.stderr.write("zxtouch.checker: cannot write report: %s\n" % exc)
        return 1

    _safe_print(summarize(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
