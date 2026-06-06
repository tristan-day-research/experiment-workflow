#!/usr/bin/env python3
"""dtale_loader — load a data file into a d-Tale server and keep it alive.

Invoked (detached) by dtale_open.sh. Reads the data file into a pandas
DataFrame, starts/joins a d-Tale instance on a fixed port, and writes the
instance URL to the given url_file so the launcher can open a browser.

Usage:
    dtale_loader.py <data_file> <url_file> <port>
"""
import sys
import json
import os

import pandas as pd
import dtale


def load(path):
    ext = os.path.splitext(path)[1].lower()

    if ext == ".csv":
        return pd.read_csv(path)

    if ext in (".jsonl", ".ndjson"):
        # Line-delimited JSON: one JSON object per line. Normalize so nested
        # fields become columns.
        records = []
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    records.append(json.loads(line))
        return pd.json_normalize(records)

    # Plain JSON. Try the structured-table reader first; fall back to
    # normalizing whatever shape the file actually has (list of dicts, dict of
    # columns, single object, or nested object) so inspection still works.
    try:
        return pd.read_json(path)
    except ValueError:
        with open(path) as f:
            data = json.load(f)
        if isinstance(data, list):
            return pd.json_normalize(data)
        if isinstance(data, dict):
            # dict-of-columns -> columns; otherwise treat as a single row.
            try:
                return pd.DataFrame(data)
            except ValueError:
                return pd.json_normalize(data)
        return pd.DataFrame({"value": [data]})


def main():
    path, url_file, port = sys.argv[1], sys.argv[2], int(sys.argv[3])

    df = load(path)
    print(f"dtale-open: loaded {len(df)} rows x {len(df.columns)} columns")

    # d-Tale's `name` only allows letters, numbers and spaces.
    raw_name = os.path.splitext(os.path.basename(path))[0]
    safe_name = "".join(
        c if (c.isalnum() or c == " ") else " " for c in raw_name
    ).strip()
    if not safe_name:
        safe_name = "data"

    # This file gets its own d-Tale server on the port the launcher picked.
    #
    # dtale.show(subprocess=False) blocks inside show() once the server is up
    # and never returns, so we cannot read instance._main_url afterwards.
    # Instead we write the URL up front, derived from the known port and the
    # instance name (d-Tale slugifies the display name, spaces -> underscores).
    url_name = safe_name.replace(" ", "_")
    url = f"http://localhost:{port}/dtale/main/{url_name}"
    with open(url_file, "w") as f:
        f.write(url + "\n")
    print(f"dtale-open: serving at {url}")

    # Blocks here for the lifetime of the server. We're detached from the
    # terminal, so this does not tie up the user's shell.
    dtale.show(
        df,
        name=safe_name,
        open_browser=False,  # the launcher opens the browser
        subprocess=False,    # block in this (detached) process to hold it open
        port=port,
    )


if __name__ == "__main__":
    main()
