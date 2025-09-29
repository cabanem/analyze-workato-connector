# Codespace Quickstart

1. Open in **GitHub Codespaces**.
2. Dev container auto-installs Ruby 3.2 and gems (`parser`).
3. Put connector somewhere (e.g., `samples/connector.rb`).
4. Run:
   ```bash
   bin/run samples/connector.rb --outdir ./out --emit json,md,dot,ndjson --pretty
    ```

5. Outputs:
    out/connector.ir.json
    out/connector.graph.dot
    out/connector.summary.md
    out/connector.events.ndjson

---

## Notes & gotchas

- Script already warns if `parser` is missing. The `Gemfile` + `bundle install` in `postCreateCommand` ensures it’s present. No native extensions, so builds are fast and drama-free.
- The earlier error (“Additional text encountered after finished reading JSON content”) typically comes from **invalid JSON** (e.g., two objects in one file, stray characters after the closing brace, or comments). The `devcontainer.json` above is strict JSON—no trailing commas, no comments.
- To pin `parser` exactly, change `~> 3.3` to an explicit version like `"3.3.4.0"` and run `bundle update parser`.
- In the event of pref to a different Ruby minor, change `"version": "3.2"` in the feature and `.ruby-version` to match.

---

## How to use in Codespaces (once opened)

Terminal:
```bash
bundle install                # run automatically on create/attach
bin/run path/to/connector.rb  # produces ./out/* by default flags you pass
```

VS Code:
- Task → “Analyze connector → ./out”
- Debug (F5) → “Ruby: Inspect connector” and edit args in launch.json if needed.