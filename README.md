# Workato Connector Inspector — README

A fast, static analyzer for Workato-style Ruby connectors. It **parses without executing**, builds an internal representation (IR) and call graph, flags issues, and emits machine- and human-friendly artifacts (JSON, DOT/Graphviz, NDJSON, SARIF, etc.). Salvage mode recovers structure even when the connector doesn’t parse cleanly.

---

## What this tool gives you

* **Static safety:** Never `eval`s. Reads source, builds AST, analyzes, emits artifacts.
* **Scales to big connectors:** Single-pass walkers, careful allocations, source slicing.
* **Grounded debugging:** Every IR node carries source locations (line/column/byte range).
* **Call-graph extraction:** Finds lambda blocks in actions/triggers/methods; detects HTTP calls.
* **Schema + SARIF:** A coarse JSON Schema for the IR and SARIF for code-scanning pipelines.
* **Salvage mode:** If parsing fails, `Ripper`-based lexical recovery still surfaces actions/triggers/methods.

---

## Quick start

```bash
# 1) Install Ruby (3.x recommended) and the parser gem
gem install parser

# 2) Run against a connector file
ruby workato_connector_inspect.rb path/to/connector.rb \
  --emit json,dot,ndjson,graphjson,sarif,index \
  --outdir ./out \
  --graph-name "MyConnector"

# 3) (Optional) Render the DOT graph to PNG
dot -Tpng ./out/connector.graph.dot -o ./out/connector.graph.png
```

On success you’ll see:

```
Wrote outputs to ./out
```

Set `ANALYZER_DEBUG=1` to print Ruby and parser versions to STDERR.

---

## Installation & requirements

* **Ruby:** 3.0–3.3 supported (uses `Parser::Ruby3x` when available, falls back to `Parser::CurrentRuby`).
* **Gems:** `parser` (AST parsing). Standard library provides `json`, `set`, `ripper`, `strscan`, `digest`.
* **Optional:** Graphviz (`dot`) to render call graphs.

---

## CLI

```
Usage: workato_connector_inspect.rb PATH/TO/connector.rb [options]

--outdir DIR          Output directory (default: ./out)
--base NAME           Base filename for outputs (default: connector)
--emit LIST           Comma-separated artifacts to emit (see list below)
--pretty / --no-pretty  Pretty-print JSON (default: pretty on)
--graph-name NAME     Graphviz graph name (default: Connector)
--max-warnings N      Cap number of collected warnings (default: 10000)
-h, --help            Show help
```

### Common `--emit` values

* `json` — IR bundle with nodes/issues/graph/stats (machine-readable).
* `dot` — Graphviz DOT (human-viewable; render with `dot`).
* `graphjson` — Graph as JSON (`nodes`, `edges`) for UIs.
* `ndjson` — Line-oriented events: issues + http calls (append-friendly).
* `sourcemap` — Node ID → location map (compact lookup).
* `embed` — JSONL “atoms”: node metadata + source slices (RAG-friendly).
* `tokens` — Lexical token stream via `Ripper.lex` (fallback introspection).
* `sarif` — SARIF 2.1.0 report (static analysis pipelines).
* `schema` — JSON Schema for the IR format (coarse).
* `index` — Index file enumerating emitted artifacts.

> **Note:** The README header mentions `md` (markdown summary). The current script **defines** a `markdown_summary` method but **does not write** a `.md` file in `Emit.write_all`. See **Known gaps** for details.

---

## Outputs (what’s in `./out`)

| File                       | What it contains                                                                          |                                            |
| -------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------ |
| `connector.ir.json`        | Entire IR: connector tree, issues, graph nodes/edges (IDs), stats, lambda records.        |                                            |
| `connector.graph.dot`      | Call graph in DOT. Nodes: actions/triggers/methods/HTTP calls; edges: call relationships. |                                            |
| `connector.graph.json`     | JSON graph: `{ nodes: [{id,label,kind}], edges: [{from,to,label}] }`.                     |                                            |
| `connector.events.ndjson`  | One JSON object per line: `{type: "issue"                                                 | "http_call", ...}` for indexing/streaming. |
| `connector.sourcemap.json` | Node IDs mapped to `{kind,name,loc}` for fast reverse lookups.                            |                                            |
| `connector.embed.jsonl`    | JSONL of “atoms” with `loc` and a **sliced** `text` snippet (capped to 16 KB per node).   |                                            |
| `connector.tokens.ndjson`  | Lex tokens with byte ranges. Useful when AST parse fails.                                 |                                            |
| `connector.sarif.json`     | SARIF 2.1.0 file for GitHub Code Scanning/DevSecOps ingestion.                            |                                            |
| `connector.schema.json`    | Coarse JSON Schema describing the IR shape (versioned).                                   |                                            |
| `connector.index.json`     | `{ artifacts: { ...paths... } }` manifest for downstream tooling.                         |                                            |

**HTTP summary enrichment:** For each action/trigger/method node, `Emit.http_summary` collects HTTP verbs and endpoints observed in that node’s lambda blocks and records them in the “atoms” emitted by `embed`.

---

## What the analyzer looks for

* **Connector shape:** Finds top-level hash that looks like a Workato connector by scoring known root keys.
* **Actions/Triggers/Methods:** Extracts children, validates required keys (e.g., `input_fields/execute/output_fields` for actions), notes duplicates.
* **Lambdas:** Registers lambdas in `input_fields`, `execute`, `output_fields`, `sample_output`; for triggers also `poll`, `webhook_*`, `dedup`, etc.
* **HTTP calls:** Inside lambdas, detects `get/post/put/patch/delete/options/head` and records edges to “HTTP” nodes.
* **Method usage:** Tracks `call(:method_name)` patterns to relate methods defined vs used.
* **Danger surfaces:** Flags `eval`, `system`, backticks (`xstr`) with warnings.

---

## Salvage mode (when parse fails)

If `parser` cannot produce an AST, the tool:

* Emits a **syntax_error** issue with diagnostics,
* Uses `Ripper.lex` to recover **root keys** and **names** of actions/triggers/methods by label scanning,
* Produces a minimal IR with the recovered items and marks the bundle as `salvaged: true`.

You still get artifacts like `connector.ir.json` and can index tokens/events.

---

## Exit codes

* **0** — Success.
* **1** — Missing dependency (`parser` gem not installed).
* **2** — Bad usage (no file provided or path not a file).

---

## Examples

### Minimal run

```bash
ruby workato_connector_inspect.rb my_connector.rb
```

Emits the default set into `./out`.

### Focused artifacts + compact JSON

```bash
ruby workato_connector_inspect.rb my_connector.rb \
  --emit json,dot \
  --no-pretty \
  --outdir ./inspect
```

### Large projects: artifact suite + graph render

```bash
ruby workato_connector_inspect.rb connectors/big.rb \
  --emit json,dot,graphjson,ndjson,sarif,index \
  --outdir ./out/big --graph-name BigConnector

dot -Tsvg ./out/big/connector.graph.dot -o ./out/big/connector.graph.svg
```

---

## Interpreting the IR

* **Nodes** carry: `kind` (`connector`, `actions`, `action`, `trigger`, `method`, etc.), `name`, `loc`, `meta`, and `children`.
* **Graph** has:

  * `nodes`: map of node-id → `{label,kind}`.
  * `edges`: array of `[from, to, meta]`, where `meta.label` often equals `"calls"`.
* **Issues** carry: `severity` (`info|warning|error`), `code` (stable rule id), `message`, `loc`, `context`.

Example IR snippet (abridged):

```json
{
  "root": {
    "kind": "connector",
    "name": "Vertex AI",
    "loc": {"line": 1, "column": 0, "begin": 0, "end": 12345},
    "meta": {"filename": "vertex.rb", "root_keys": ["connection","actions","methods"]},
    "children": [
      {"kind": "actions", "children": [
        {"kind": "action", "name": "text_generate", "loc": {"line": 200}}
      ]}
    ]
  },
  "issues": [
    {"severity":"warning","code":"action_missing_required_keys","message":"Action foo missing keys: execute","loc":{"line":321}}
  ],
  "graph": { "nodes": { ... }, "edges": [ ["action:text_generate#execute","action:text_generate#execute::http#post(...)",{"label":"calls"} ] ] },
  "salvaged": false
}
```

---

## Integration ideas

* **Workato QA:** Gate changes by diffing `connector.ir.json` between commits; fail CI when new `dangerous_*` issues appear.
* **Docs generation:** Consume `graph.dot`/`graph.json` to render action/trigger maps in internal docs.
* **RAG pipelines:** Index `embed.jsonl` (atoms + source slices) to enrich LLMs with connector context.
* **Code scanning:** Upload `connector.sarif.json` into GitHub Code Scanning or Azure DevOps.

---

## Performance tips

* Prefer `--emit` only what you need to cut I/O.
* For very large files, rely on `graphjson` over `dot` for UI consumption.
* `embed` slices are capped at **16 KB** per node to avoid ballooning outputs.

---

## Troubleshooting

* **`Missing dependency 'parser'`:** Run `gem install parser`. If behind a proxy, set `HTTP_PROXY/HTTPS_PROXY`.
* **“Parser failed; salvage mode engaged”:** Check `issues[] -> context.diagnostics`. Salvage output still includes actions/triggers/methods discovered via labels.
* **No `.md` summary:** See **Known gaps** below.
* **Graph won’t render:** Ensure `dot -V` works; install Graphviz (`brew install graphviz`, `apt-get install graphviz`, etc.).
* **Encoding errors:** File must be UTF-8. Re-encode if necessary: `iconv -f utf-8 -t utf-8 -c`.

---

## Security posture

* **Static only:** The analyzer never executes connector code. It reads files and walks AST/lex streams.
* **Red flags:** Emits warnings for `eval`, `system`, and backticks found in source.
* **Safe for untrusted code:** As safe as reading text files; still treat outputs as untrusted in downstream systems.

---

## Known gaps & notes

* **Markdown summary (`md`):** The script defines `Emit.markdown_summary` but **does not currently write** a `connector.summary.md` file. If you pass `--emit md`, nothing will be produced. To enable, add an `md` branch in `Emit.write_all` that calls `write_text(..., Emit.markdown_summary(bundle))`.
* **Duplicate `graphjson` assignment:** `Emit.write_all` assigns `graph_json` twice; the second block duplicates the first. Harmless but redundant.
* **Warning cap:** `--max-warnings` sets a cap in options, but the walker does not currently stop at the cap; it collects all. If you need hard caps, wire the option into `issue(...)`.

---

## FAQ

**Q: Does it mutate my source or depend on Workato runtime?**
No. It reads files and analyzes statically; no SDK needed; no mutation.

**Q: How does it detect HTTP calls?**
Inside lambdas, it looks for `send` nodes whose method is in `{get, post, put, patch, delete, options, head}` and records them as “HTTP” nodes with labels like `POST /v1/...` when a literal path is present.

**Q: What method invocations are linked?**
Calls like `call(:my_helper)` where the symbol looks like an identifier (not a model name like `"gemini-1.5-pro"`). It matches to `methods.my_helper`.

**Q: What if my connector uses Ruby 3.3+ features?**
The parser selects `Parser::Ruby33` when available; else `Parser::CurrentRuby`. Most modern syntax is supported.

---

## Contributing

* Open issues for false positives/negatives or performance bumps.
* Proposals welcome for:

  * Additional detectors (e.g., streaming usage, auth schema validation).
  * Richer IR for `object_definitions` and `pick_lists`.
  * Enabling the markdown emitter and de-duping emit blocks.

---

## Roadmap (suggested)

* **Implement `md` emitter** in `Emit.write_all`.
* **Hard warning cap** honoring `--max-warnings`.
* **HTTP endpoint normalization** (fold dynamic fragments, capture base URIs).
* **First-class `object_definitions` schema** extraction for doc autogen.
* **Multi-file connectors** (merge IR across includes).

---

## License


All Rights Reserved

Copyright (c) ruby-connector-inspector.2025 Emily Cabaniss

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

---

## Appendix: Minimal API surface (advanced)

You can import components for programmatic use:

```ruby
source, _ = Util.read_source("connector.rb")
ast_res = AstParser.new(filename: "connector.rb", source: source).parse
walker  = ConnectorWalker.new(filename: "connector.rb", ast: ast_res[:ast], comments: ast_res[:comments])
bundle  = walker.walk
File.write("connector.ir.json", JSON.pretty_generate(bundle.to_h))
```
