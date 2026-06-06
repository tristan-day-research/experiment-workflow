# Open in d-Tale

Right-click a `.json`, `.jsonl`/`.ndjson`, or `.csv` file in VS Code or Cursor
and inspect it in [d-Tale](https://github.com/man-group/dtale) in your
browser — no notebook needed.

It adds an **"Open in d-Tale"** item to the right-click menu in:
- the Explorer (file tree),
- the editor tab (right-click the tab),
- inside an open editor.

When you click it, a d-Tale server starts on that file (in the background) and
your browser opens to it. The launcher returns immediately, so you can open as
many files as you like in quick succession — each gets its own d-Tale server
and its own browser tab. The terminal that ran it is free right away; you do
**not** need to Ctrl-C anything.

Each server keeps running in the background until you quit it from the d-Tale
UI (the menu in the top-left → "Shutdown") or end your login session.

## How it works

Three pieces:

| File | Role |
|---|---|
| [`extension.js`](extension.js) | The editor glue. Adds the right-click menu item and runs the launcher on the selected file. |
| [`../dtale_open.sh`](../dtale_open.sh) | The launcher. Finds a Python with d-Tale, picks a free port, starts the loader detached, waits until the server is up, opens the browser, returns. |
| [`../dtale_loader.py`](../dtale_loader.py) | Runs in the background. Reads the file into pandas (handling `.json`, `.jsonl`/`.ndjson`, `.csv`) and holds the d-Tale server open. |

The launcher picks its Python automatically:
1. `$DTALE_PYTHON` if you've set it,
2. otherwise your conda base (`~/miniconda3/bin/python`, if it has d-Tale),
3. otherwise whatever `python3` / `python` is on your `PATH` that has d-Tale.

To pin a specific interpreter, add to your `~/.zshrc`:

```bash
export DTALE_PYTHON=/path/to/python
```

## Install

This extension is plain JavaScript — there is **no build step** and you don't
need Node. You just need the editor to see the folder as an installed
extension. The easiest way is a symlink.

### VS Code

```bash
ln -sf ~/path/to/experiment-workflow/vscode-dtale \
       ~/.vscode/extensions/local.dtale-open-0.1.0
```

### Cursor

```bash
ln -sf ~/path/to/experiment-workflow/vscode-dtale \
       ~/.cursor/extensions/local.dtale-open-0.1.0
```

Then **fully restart** the editor (Cmd-Q and reopen — a window reload is not
always enough for a newly added extension).

To confirm it's loaded: open the Command Palette (Cmd-Shift-P) and type
"Open in d-Tale" — the command should appear.

## Uninstall

Remove the symlink and restart:

```bash
rm ~/.vscode/extensions/local.dtale-open-0.1.0
# and/or
rm ~/.cursor/extensions/local.dtale-open-0.1.0
```

## Settings

If you move `dtale_open.sh`, point the extension at the new location via the
`dtaleOpen.scriptPath` setting (Settings → search "d-Tale").

## Use it without the editor

The launcher is a normal script, so you can also run it from a terminal:

```bash
~/path/to/experiment-workflow/dtale_open.sh some/data.json
```

Or symlink it onto your PATH for a short command:

```bash
ln -sf ~/path/to/experiment-workflow/dtale_open.sh ~/.local/bin/dtale-open
dtale-open some/data.json
```
