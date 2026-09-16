"""Script runner: ``python -u -m zxtouch.runner <entry.py> [args...]``.

Injects IOSControl-style globals (see zxtouch.prelude) into the user
script's ``__main__`` namespace, then executes it with runpy so that
``tap(200, 300)`` works with zero boilerplate.

Keeps SpringBoard integration intact:
- stdout/stderr still flow to the caller's pipe (add_datetime.sh -> output)
- exit code propagates (ScriptPlayer reads last_python_status)
- SIGKILL to the process group still terminates the script
"""
import runpy
import sys


def main(argv):
    if len(argv) < 2:
        print("Usage: python -m zxtouch.runner <script.py> [args...]", file=sys.stderr)
        return 2
    script = argv[1]
    sys.argv = argv[1:]  # user script sees its own path as argv[0]

    from zxtouch import prelude
    prelude.setScriptDir(script)
    # Pre-connect (with retries inside); on failure runpy still runs so the
    # traceback is visible in Logs instead of a silent exit.
    try:
        prelude.get_device()
    except Exception as e:
        print("zxtouch.runner: device connect failed (continuing): %s" % (e,),
              file=sys.stderr)

    # Inject globals into a fresh __main__ dict, then run the user file.
    main_dict = {"__name__": "__main__", "__file__": script}
    prelude.install(main_dict)
    try:
        runpy.run_path(script, init_globals=main_dict, run_name="__main__")
        return 0
    except SystemExit as e:
        return e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
    finally:
        try:
            prelude.disconnect()
        except Exception:
            pass


if __name__ == "__main__":
    sys.exit(main(sys.argv))
