const vscode = require("vscode");
const cp = require("child_process");
const fs = require("fs");
const path = require("path");

function activate(context) {
  const disposable = vscode.commands.registerCommand(
    "dtaleOpen.open",
    async (uri) => {
      // `uri` is provided when invoked from a context menu. When invoked from
      // the Command Palette, fall back to the active editor's file.
      let target = uri;
      if (!target || !target.fsPath) {
        const editor = vscode.window.activeTextEditor;
        if (editor) {
          target = editor.document.uri;
        }
      }

      if (!target || !target.fsPath) {
        vscode.window.showErrorMessage(
          "Open in d-Tale: no file selected."
        );
        return;
      }

      const filePath = target.fsPath;

      const config = vscode.workspace.getConfiguration("dtaleOpen");
      // Use the configured path if set; otherwise fall back to the launcher
      // bundled one level up from this extension (the repo's dtale_open.sh).
      const scriptPath =
        config.get("scriptPath") ||
        path.join(__dirname, "..", "dtale_open.sh");

      if (!scriptPath || !fs.existsSync(scriptPath)) {
        vscode.window.showErrorMessage(
          `Open in d-Tale: launcher script not found at "${scriptPath}". ` +
            "Set dtaleOpen.scriptPath in settings."
        );
        return;
      }

      // Run the launcher in a dedicated, reused terminal so the d-Tale server
      // stays alive (the script blocks) and the user can see its output / stop it.
      const terminalName = "d-Tale";
      let terminal = vscode.window.terminals.find(
        (t) => t.name === terminalName
      );
      if (!terminal) {
        terminal = vscode.window.createTerminal(terminalName);
      }
      terminal.show();
      terminal.sendText(
        `${shellQuote(scriptPath)} ${shellQuote(filePath)}`
      );

      vscode.window.showInformationMessage(
        `Opening ${basename(filePath)} in d-Tale…`
      );
    }
  );

  context.subscriptions.push(disposable);
}

function shellQuote(s) {
  // Single-quote for POSIX shells; escape embedded single quotes.
  return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

function basename(p) {
  return p.split(/[\\/]/).pop();
}

function deactivate() {}

module.exports = { activate, deactivate };
