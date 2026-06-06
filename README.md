# RunPod workflow

Your Mac holds the code. RunPod runs it on a GPU. Results come back to your Mac.
The pod is **wiped every time you stop it** — nothing on it survives. Your Mac is
always the source of truth.

## The one thing that trips everyone up: there are TWO terminals

Almost every problem in this workflow comes from running a command in the wrong
place. There are two completely separate terminals:

| Terminal | Where it is | Prompt looks like | Used for |
|---|---|---|---|
| **Mac Terminal** | The Terminal app on your Mac (or Cursor's terminal) | `you@your-mac %` | `set-pod`, `run-persona`, `pull-results`, `ssh` |
| **Pod web terminal** | In your browser, in the RunPod UI | `root@<random-id>:~#` | `apt-get`, adding your SSH key |

Rules of thumb:
- `apt-get` **only works on the pod.** If you see `zsh: command not found: apt-get`, you typed it on your Mac by mistake.
- `set-pod`, `run-persona`, `pull-results` **only work on your Mac.** They are your local helper commands.
- If the prompt says `root@something`, you are **on the pod**. If it says `you@your-mac`, you are **on your Mac**.

---

## Part 1 — One-time setup on your Mac

Do this once, ever. All commands here run in your **Mac Terminal**.

### Step 1 — Check the config file

Open [runpod.env](runpod.env). Confirm these match your project (they are already set for `persona_introspection`):

- **`LOCAL_DIR`** — path to your repo on your Mac. Change the folder name at the end if your repo is named differently.
- **`RUN_ENTRYPOINT`** — the command that runs your experiment. Currently `python run.py`.
- **`REQUIREMENTS_FILE`** — the requirements file the pod installs. Currently `remote_requirements.txt`.

### Step 2 — Make the scripts executable

```bash
cd ~/path/to/experiment-workflow
chmod +x set_pod.sh sync_up.sh run_persona.sh pull_results.sh
```

### Step 3 — Create the short command names

```bash
mkdir -p ~/.local/bin
ln -sf ~/path/to/experiment-workflow/set_pod.sh      ~/.local/bin/set-pod
ln -sf ~/path/to/experiment-workflow/sync_up.sh      ~/.local/bin/sync-up
ln -sf ~/path/to/experiment-workflow/run_persona.sh  ~/.local/bin/run-persona
ln -sf ~/path/to/experiment-workflow/pull_results.sh ~/.local/bin/pull-results
```

### Step 4 — Make those commands work in every terminal window

Open your shell config file in TextEdit:

```bash
open -e ~/.zshrc
```

Add this line at the very bottom, then save and close the window:

```
export PATH="$HOME/.local/bin:$PATH"
```

Back in Terminal, load the change:

```bash
source ~/.zshrc
```

Confirm it worked:

```bash
which set-pod
```

You should see `~/.local/bin/set-pod` (shown as a full path). If you see `command not found`, the line didn't save — redo this step.

---

## Part 2 — Every day you work

The pod is wiped when you stop it, so you repeat this every morning. **Do the steps in this exact order.** Each step says which terminal to use.

### Step 1 — [RunPod UI] Start the pod

Start a pod from your template. Wait until its status shows **Running**.

### Step 2 — [RunPod UI] Copy the SSH command

Click **Connect** on the running pod. Under **SSH over exposed TCP**, copy the whole command. It looks like:

```
ssh root@64.247.201.35 -p 17543 -i ~/.ssh/id_ed25519
```

(The IP and port are different every time you start a pod — that's normal.)

### Step 3 — [Pod web terminal] Install your SSH key and rsync

In the RunPod UI, click **Web Terminal → Open web terminal**. A terminal opens **in your browser**. The prompt looks like `root@<random-id>:~#`.

Paste this entire line and press Enter:

```bash
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEH+qiIYfOqW6gmWpgN+1/HfMmi1eCcNdh3nV/IrfReQ rp_sync" >> ~/.ssh/authorized_keys && apt-get update && apt-get install -y rsync tmux
```

This installs your SSH key (so your Mac can connect without a password), rsync (so your code can be copied to the pod), and tmux (so your runs survive disconnections — see Step 7). Takes ~30 seconds. **Required every new pod.**

> If `run-persona` ever can't find tmux, it installs it for you automatically — but installing it here up front is one less thing that can go wrong.

> If you see only `gotty.hash` and `gotty.log` when you `ls` here, that's normal — those are the web terminal's own files. Your code isn't here yet; it gets synced to `/workspace` in Step 6 or 7.

### Step 4 — [Mac Terminal] Point your Mac at today's pod

Type `set-pod ` and then paste the SSH command from Step 2:

```bash
set-pod ssh root@64.247.201.35 -p 17543 -i ~/.ssh/id_ed25519
```

This updates `~/.ssh/config` so the name `local_first_workflow` reaches today's pod.

### Step 5 — [Mac Terminal] Confirm the connection works

```bash
ssh local_first_workflow
```

You should land on the pod (prompt becomes `root@...`) with **no password prompt**. Type `exit` to come back to your Mac.

- If it **asks for a password**: Step 3's key line didn't take. Redo it in the web terminal.
- If it says **Connection refused/reset**: the pod isn't ready yet. Wait 30–60s and retry.

### Step 6 — [Mac Terminal] Sync your code to the pod (without running it)

If you just want your latest code on the pod — to inspect it, set things up, or
sanity-check files — *without* starting an experiment yet:

```bash
sync-up
```

This pushes your Mac's code up to the pod's `/workspace`. It's the exact same
push `run-persona` does first (Step 7 always syncs before running), so you don't
*have* to run `sync-up` separately — it's here for when you want your code on the
pod and to look around before running anything.

To then poke around your code on the pod over SSH:

```bash
ssh local_first_workflow
cd /workspace      # leading slash — it's /workspace, NOT ~/workspace
ls
```

> **`cd workspace` → `No such file or directory`?** Your code lives at the
> absolute path `/workspace`, not inside root's home folder. From the pod you
> must `cd /workspace` (with the leading slash). It also only exists *after* a
> sync — on a brand-new pod, before `sync-up` or `run-persona`, there's nothing
> there yet (an `ls` in `~` showing only `gotty.hash`/`gotty.log` is expected and
> normal).

### Step 7 — [Mac Terminal] Run your experiment

`run-persona` runs **any** experiment in the repo — despite the name, it isn't
tied to the persona experiment. You pass it a *config name*, and `run.py` figures
out which experiment that config belongs to (it scans every
`experiments/*/config.yaml`). So the same command runs whichever experiment you
point it at:

```bash
run-persona self_recognition_dev     # the persona self-recognition experiment
run-persona paper_replication_dev    # the paper-replication experiment
```

Replace the config name with the one you want. To list all configs across all
experiments:

```bash
ssh local_first_workflow "cd /workspace && python run.py --list"
```

You can pass flags and overrides too — anything after the config name is handed
straight through to `python run.py`. So whatever you'd type as
`python run.py <config> …` works verbatim with `run-persona <config> …`:

```bash
run-persona paper_replication_dev --override sample_size=20
run-persona self_recognition_dev --override sample_size=5 temperature=0.7
```

> Only `--attach`, `--status`, `--stop`, and `--no-deps` are consumed by
> `run-persona` itself — every other argument passes through to `run.py`.

> **One run at a time per pod.** All runs share a single tmux session, so you
> can't run two experiments simultaneously on the same pod — start the second
> only after the first finishes (or `run-persona --stop` it). Running them one
> after another is fine.

One `run-persona` does all of this automatically:
1. Pushes your latest code from your Mac to the pod (`/workspace`)
2. Installs Python deps from `remote_requirements.txt` if they changed (first run on a fresh pod takes a few minutes — normal)
3. Launches your experiment **inside tmux on the pod**, then attaches you to it so you see live output

> Skip the dependency check with `run-persona --no-deps self_recognition_dev` once deps are already installed in this pod session — saves a few seconds.

#### Your run survives disconnections

Because the experiment runs in tmux **on the pod**, it keeps running no matter what happens to your laptop. You can change wifi, switch VPN, close the lid, or lose signal — **the GPU job keeps going.** This is the whole point: your connection is just a window into the run, not the thing keeping it alive.

While you're watching the live output:

- **To stop watching but leave the run going:** press **Ctrl-b**, then **d** (for "detach"). You're back on your Mac; the run continues on the pod.
- **To actually cancel the run:** press **Ctrl-c**.

If you ever get disconnected (or detached), these commands get you back:

```bash
run-persona --attach    # jump back into the live output, right where it is
run-persona --status    # "is it still running?" + the last 25 lines of output
run-persona --stop      # cancel a running job
```

So the safe habit after a wifi change is simply: `run-persona --status` to confirm it's still going, then `run-persona --attach` if you want to watch again.

### Step 8 — [Mac Terminal] Pull results back

When the run finishes (check with `run-persona --status` — it'll say **DONE/STOPPED** when complete):

```bash
pull-results
```

This copies every experiment's `results/` folder down to your Mac (it pulls
`experiments/*/results/` for all experiments, not just the one you ran). Results
land at:

```
~/path/to/persona_introspection/experiments/<experiment_name>/results/
```

e.g. `experiments/paper_replication/results/` for the paper-replication runs.

**Always do this before stopping the pod** — once stopped, everything on the pod is gone.

### Step 9 — [RunPod UI] Stop the pod

Click **Stop**. GPU billing stops immediately.

---

## Troubleshooting

**My wifi/VPN changed / my laptop slept / I got disconnected mid-run**
Your run is fine — it's running in tmux on the pod, independent of your connection. Reconnect and check on it:
```bash
run-persona --status     # is it still running? shows recent output
run-persona --attach     # jump back into the live view
```
If `--status` says it's still RUNNING, nothing was lost. (Your pod's IP/port don't change when *your* network changes, so `ssh local_first_workflow` still works.)

**`zsh: command not found: apt-get`**
You ran an `apt-get` command in your **Mac Terminal**. `apt-get` only exists on the pod. Run it in the **RunPod web terminal** (Step 3) instead.

**`command not found: set-pod` / `run-persona` / `pull-results`**
These are Mac commands and you skipped Part 1 Step 3–4, or didn't run `source ~/.zshrc`. Redo Part 1 Steps 3–4.

**SSH asks for a password**
Step 3 (the key line in the web terminal) didn't run or didn't take. Open the web terminal and paste the `echo "ssh-ed25519 ..."` line again.

**`Connection reset` / `Connection refused`**
The pod isn't fully booted. Wait 30–60 seconds and retry `ssh local_first_workflow`.

**`rsync: command not found`**
rsync isn't installed on the pod — Step 3 was skipped. In the web terminal run:
```bash
apt-get update && apt-get install -y rsync
```

**`Unable to locate package rsync`**
You ran `apt-get install` without `apt-get update` first. Run them together in the web terminal:
```bash
apt-get update && apt-get install -y rsync
```

**`⚠ no remote_requirements.txt found …` during run-persona**
The pod can't find your requirements file. Confirm the filename in your repo matches `REQUIREMENTS_FILE` in [runpod.env](runpod.env).

**First run of the day is slow**
Normal. A fresh pod has no installed deps, so it runs `pip install -r remote_requirements.txt` from scratch (and may re-download model weights). Later runs the same day are fast.

**Results are gone**
You stopped the pod before running `pull-results`. The pod is wiped on stop and results can't be recovered. Always pull first.

**`[freeze] skipped …` warnings from `python run.py --list`**
Normal when deps aren't installed yet. They disappear after `run-persona` installs dependencies.

---

## Inspecting results with d-Tale

Once you've pulled results back to your Mac, you'll want to look at them. This
repo also ships a small tool for opening a `.json`, `.jsonl`/`.ndjson`, or `.csv`
file in [d-Tale](https://github.com/man-group/dtale) — a spreadsheet-style data
viewer — in your browser, with no notebook needed.

It comes in two forms:

| File | What it is |
|---|---|
| [dtale_open.sh](dtale_open.sh) + [dtale_loader.py](dtale_loader.py) | The launcher: loads a data file into pandas, starts a d-Tale server, and opens your browser to it. |
| [vscode-dtale/](vscode-dtale/) | A VS Code / Cursor extension that adds an **"Open in d-Tale"** right-click menu item, so you can inspect a file straight from the file tree. |

### From the terminal

```bash
dtale-open experiments/paper_replication/results/run.json
```

This starts a d-Tale server on the file and opens it in your browser. The
terminal is freed immediately — open as many files as you like; they all share
one server (default port `40000`), each as a new tab.

To set up the short `dtale-open` command:

```bash
ln -sf ~/path/to/experiment-workflow/dtale_open.sh ~/.local/bin/dtale-open
```

(Same `~/.local/bin` on your `PATH` as the RunPod commands — see Part 1.)

### From VS Code / Cursor (right-click a file)

Right-click a `.json`, `.jsonl`/`.ndjson`, or `.csv` file in the Explorer, the
editor tab, or inside an open editor, and choose **"Open in d-Tale"**. A `d-Tale`
terminal opens, the server starts, and your browser opens to it. Leave that
terminal running while you inspect; close it (or Ctrl-C) to stop the server.

See [vscode-dtale/README.md](vscode-dtale/README.md) for install instructions
(it's a symlink — no build step).

### Which Python it uses

`dtale-open` needs a Python with d-Tale installed. It picks one automatically:

1. `$DTALE_PYTHON` if you've set it,
2. otherwise your conda base (`~/miniconda3/bin/python`),
3. otherwise whatever `python3` / `python` on your `PATH` has d-Tale.

To pin a specific interpreter, add to your `~/.zshrc`:

```bash
export DTALE_PYTHON=/path/to/python
```

If none has it: `python3 -m pip install dtale`.
