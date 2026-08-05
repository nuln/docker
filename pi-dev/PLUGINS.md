# Pi Plugin Catalog

This document is compiled from the official pi.dev [Package Catalog](https://pi.dev/packages) (currently 5426 packages, as of 2026-08) and the well-known extension repo [narumiruna/pi-extensions](https://github.com/narumiruna/pi-extensions), curating the mainstream plugins by download count/ecosystem.

## How to install

The **curated default set is already preinstalled in the image** (baked into `/home/pi/.pi-plugins`; on first start the s6 service `wire-plugins` writes a `settings.json` referencing them by absolute path — see README). Commands below are for **adding/removing your own plugins**, which persist in the mounted `~/.pi/agent` (`data/pi` volume) alongside the baked ones:

```bash
docker compose exec pi pi install npm:pi-mcp-adapter
```

Temporary try-out (not saved to config): `docker compose exec pi pi -e npm:pi-mcp-adapter`
Remove: `pi remove npm:<package>`　Update: `pi update --extensions`　List: `pi list`

> The full catalog is at [pi.dev/packages](https://pi.dev/packages) — filter by type (extension/skill/theme/prompt) and sort by downloads, 109 pages total.

---

## 1. Core enhancements (highest downloads, most worth attention)

| Plugin | Type | Function | Downloads |
|--------|------|----------|-----------|
| `pi-mcp-adapter` | extension | MCP (Model Context Protocol) adapter, connect to any MCP server | 246K/mo |
| `pi-web-access` | extension | Web search, URL scrape, GitHub clone, PDF extraction, YouTube video understanding, local video analysis; supports OpenAI/Brave/Tavily/Kagi/Ollama etc. search providers | 175K/mo |
| `pi-subagents` | package | Subagent delegation: chained, parallel execution, TUI clarification | 172K/mo |
| `context-mode` | package | Saves 98% context window: sandboxed code execution, FTS5 knowledge base, intent-driven search | 72K/mo |
| `@tintinweb/pi-subagents` | extension | Claude Code style autonomous subagents | 43K/mo |
| `pi-lens` | extension | Real-time code feedback: LSP, linters, formatting, type checks, structure analysis | 41K/mo |
| `@remnic/plugin-pi` | package | Remnic memory extension | 42K/mo |

## 2. Security & permissions

| Plugin | Type | Function |
|--------|------|----------|
| `@gotgenes/pi-permission-system` | extension | Permission enforcement system |
| `@vigolium/piolium` | extension | Multi-stage security audit: expert subagents, isolated context, concurrency caps, resumable state |
| `pi-hermes-memory` | extension+skill | Persistent memory + session search + secret scanning (SQLite FTS5, 732 tests) |
| `pi-sandbox` | extension | OS-level sandboxed pi runtime, interactive permission prompts |
| `cc-safety-net` | package | Coding agent CLI hooks: blocks destructive git/file commands before execution |
| `pi-lean-ctx` | package | Routes bash/read/grep/find/ls through lean-ctx to save tokens massively, built-in MCP bridge session cache |

## 3. Subagents & autonomous workflows

| Plugin | Type | Function |
|--------|------|----------|
| `@quintinshaw/pi-dynamic-workflows` | package | Dynamic workflows: fan out tasks to hundreds of subagents, real model routing, token/cost accounting, resume, git-worktree isolation, /workflows TUI, /deep-research |
| `@kky42/pi-flow` | package | Multi-backend subagents + dynamic workflow orchestration |
| `@narumitw/pi-subagents` | extension | Delegated isolated work: single/parallel/chained execution |
| `@narumitw/pi-goal` | extension | Autonomous goal completion until verified; optional experimental ordered queue |
| `pi-goal-list-loop-audit` | extension | Command center for autonomous pi: interview-drafted goals, audit task queue, continuous loops (metrics/spec/project audits) |
| `pi-codex-goal` | extension | Codex-style goal tracking and continuation |
| `gentle-pi` | package | Senior architect dev framework: SDD/OpenSpec, TDD evidence, review guardrails, skill discovery |
| `@cynos-ai/engineer` | extension | Cynos autonomous AI engineering runtime, evidence-verified completion |
| `pi-autoresearch` | extension | Autonomous experiment loop: run -> measure -> keep or discard (inspired by karpathy/autoresearch) |
| `pi-autopilot` | package | Perfect-quality autopilot orchestration: transaction coordination, deterministic deadlock resolution, isolated worktree, quality gates |
| `pi-maestro-flow` | skill | Multi-agent orchestration family: parallel teammate scheduling, goals, plans, knowledge system, MCP/LSP/browser, cockpit visualization |
| `pi-crew` | package | AI team coordination, workflows, worktrees, async task orchestration |
| `pi-soly` | extension | Workflow + project management: plans, status, enforced rules, self-review, multi-issue selector, zero config |
| `@mjasnikovs/pi-task` | extension | Deterministic task planning and spec orchestration: crash-safe /task pipeline, verify/enforce gates, real-time remote web view |
| `pi-spine` | package | Orchestration backbone for long-running pi development |
| `@giladbarnea/pi-simple-team` | package | Flat, real-time collaborative pi agent team |
| `@mammothb/pi-subagents` | package | Interactive subagents |
| `@ferris1225/pi-subagents` | package | Focused subagent delegation: explore/worker/reviewer, isolated context, proactive dispatch, per-agent model selection |
| `@narumitw/pi-plan-mode` | extension | Codex-style read-only /plan collaboration mode |
| `@bacnh85/pi-plan` | extension | Plan mode: read-only gate + plan -> implement -> verify -> review workflow |
| `@plannotator/pi-extension` | package | Interactive plan review: annotations, annotate agent messages, review code/PR |

## 4. Memory & knowledge

| Plugin | Type | Function |
|--------|------|----------|
| `pi-memory` | package | qmd semantic search memory: daily logs, long-term memory, scratchpad |
| `pi-hermes-memory` | extension+skill | See "Security": FTS5 search + automatic consolidation |
| `open-zk-kb` | package | Persistent memory: corrections stick, context accumulates, smarter every session |
| `pi-vault-mind` | extension+skill | Obsidian vault integration: listens for @agent tags, dispatches subagents, LanceDB vector+FTS+graph |
| `pi-goosedump` | extension | goosedump session search, persistent memory, compaction |
| `gentle-engram` | extension | Persistent memory for pi: local or cloud brain, shared across sessions/compaction/MCP agents |
| `@eleboucher/pi-memini` | extension | Cross-session shared memory (memini service) |
| `pi-experiences` | extension | Human-reviewed behavioral habits layer (local-first, like skills+memory) |
| `pi-tasks` | package | pi-native execution contracts: evidence-gated completion, ordered plans, compaction-safe recovery |

## 5. Web & research

| Plugin | Type | Function |
|--------|------|----------|
| `pi-web-access` | extension | See "Core enhancements" |
| `pi-deepseek-search` | extension | DeepSeek server-side search (DeepSeek models only) |
| `@ollama/pi-web-search` | extension | Uses Ollama's web search/fetch API |
| `pi-web-search` | extension | Provider-native web search: Google Gemini/OpenAI/Anthropic + Gemini URL context |
| `@narumitw/pi-firecrawl` | extension | Firecrawl scrape/crawl/URL discovery/search |
| `@narumitw/pi-google-genai` | extension | Google Search/Maps/URL context |
| `opencode-codebase-index` | package | Semantic codebase search: embeddings, symbol discovery, call graphs (host-agnostic) |
| `pi-readseek` | extension | LINE:HASH anchored file operations and structured code navigation |
| `@mrclrchtr/supi-web` | extension | Web scraping + Context7 docs expansion |
| `@xaccefy/pi-lookup` | extension | Web search, page scraping, library docs (Context7), GitHub repo Q&A (DeepWiki) |
| `@houndmcp/hound-mcp-pi` | package | Hound web research: keyless search, anti-bot scraping, deep crawl, screenshots, Internet Archive dead-link recovery |

## 6. Browser automation

| Plugin | Type | Function |
|--------|------|----------|
| `pi-agent-browser-native` | extension | Exposes agent-browser as native tools |
| `@narumitw/pi-chrome-devtools` | extension | Chrome DevTools protocol: inspect tabs, navigate, execute JS, screenshots |
| `pire-browser` | extension+skill | Cross-platform pi extension + Firefox bridge for local browser automation |
| `betterwright` | package | Persistent, policy-guarded Playwright browser: network control, trusted credential filling, evidence screenshots, CAPTCHA helper |

## 7. UI & terminal experience

| Plugin | Type | Function |
|--------|------|----------|
| `pi-powerline-footer` | extension | Powerline-style bottom status bar |
| `@narumitw/pi-statusline` | extension | Info-rich status bar: model, tools, git status, context usage, tokens, cost, time |
| `pi-zentui` | extension+theme | Starship-style status bar + Opencode-style TUI |
| `@narumitw/pi-starship` | extension | Native Starship-style TOML footer (no Starship binary dependency) |
| `@juicesharp/rpiv-todo` | extension | Real-time todo overlay, survives /reload and compaction |
| `@juicesharp/rpiv-ask-user-question` | extension | Structured questionnaires: typed options instead of free input when the model asks |
| `pi-ask-user` | extension | Interactive ask_user tool: searchable split-screen selection UI, multi-select, free input |
| `@narumitw/pi-btw` / `pi-btw` / `@juicesharp/rpiv-btw` | extension | /btw sidebar quick questions, no main-conversation pollution |
| `@juicesharp/rpiv-voice` | extension | Voice dictation: local Whisper STT + microphone capture |
| `@ayulab/pi-rewind` | extension | /rewind checkpoint navigation |
| `@xynogen/pix-pretty` | extension | Enhanced tool output rendering: syntax highlight, file icons, tree views, diff rendering, FFF search |
| `@heyhuynhgiabuu/pi-pretty` | extension | Beautified terminal output: syntax-highlighted file reads, colored bash, tree dirs |
| `pi-cc-extensions` | extension | Claude Code style UI productivity suite: pinned editor, context check, agent/session references |
| `@esso0428/pi-sidebar` | extension | Floating right sidebar: git diff/status + session metadata |
| `pi-oc-style-agent-switcher` | extension | Keyboard-driven main agent model switching (Alt+Shift+Left/Right) |
| `pi-interview` | extension | Interactive interview form |
| `@firstpick/pi-package-webui` | extension | Local browser UI + /webui-start /webui-status |
| `@jmfederico/pi-web` | package | Web UI for persistent pi sessions (real workspace) |

## 8. Dev toolchain & LSP

| Plugin | Type | Function |
|--------|------|----------|
| `@narumitw/pi-lsp` | extension | Language-agnostic LSP tools: JS/TS/Python/Rust/Go/Ruby/C/C++/JVM/.NET/Swift/shell etc. |
| `@narumitw/pi-worktree` | extension | git worktree create/switch/delete/cleanup, sessions follow migration |
| `@narumitw/pi-github-pr` | extension | Current-branch PR status/review/comment count (via gh CLI) |
| `pi-simplify` | extension | Reviews recently changed code for clarity/consistency/maintainability |
| `@ff-labs/pi-fff` | extension | FFF fuzzy file/content search |
| `pi-hashline-edit-pro` | extension | Strict hashline read/replace tools (hash-anchored editing, 3-char/62-symbol/perfect hash) |
| `pi-markdown-preview` | package | Markdown + LaTeX preview: terminal/browser/PDF output |
| `@mammothb/pi-office` | extension | Read/search PDF, DOCX, XLSX (pure JS, zero system deps) |
| `@mammothb/pi-ghsearch` | extension | ghsearch tool: search GitHub code |
| `pi-provider-litellm` | extension | LiteLLM proxy provider |
| `pi-lmstudio` | package | LM Studio model provider |
| `pi-llama-cpp` | extension | llama.cpp integration: router, single/legacy models, multi-server |
| `pi-cursor-sdk` | extension | Provider for @cursor/sdk local and cloud agents |
| `pi-xai-oauth` | package | xAI OAuth provider + authenticated-account Grok model catalog |
| `@amaster.ai/pi-image-gen` | extension | Image generation: OpenAI gpt-image, Google Nano Banana, Qwen-Image, OpenRouter, custom |
| `pi-cache-optimizer` | package | Improves prompt/KV cache hit rate: stable prompts, cache keys, provider-compat warnings, footer cache stats |
| `@narumitw/pi-retry` | extension | Retry empty details/Codex websocket limits/stuck provider errors |

## 9. Observability & usage stats

| Plugin | Type | Function |
|--------|------|----------|
| `@braintrust/pi-extension` | package | Braintrust automatic tracing: session/turn/LLM/tool executions |
| `@raindrop-ai/pi-agent` | package | Raindrop observability: subscriber or extension automatic tracing |
| `@narumitw/pi-langfuse` | extension | Langfuse tracing: agent runs, generations, tokens, cost, tool activity |
| `@narumitw/pi-usage` | extension | Codex subscription limits / OpenRouter API-key spend limits |
| `@alexanderfortin/pi-deepseek-usage` | extension | DeepSeek API balance monitoring |
| `@tmustier/pi-usage-extension` | package | Session usage stats dashboard |
| `pi-harness-runtime` | extension | Codex-style /usage + autonomous coding harness (BETA) |
| `@mrclrchtr/supi-context` | extension | Context window and token usage monitoring |
| `@mrclrchtr/supi-cache` | extension | Prompt cache health monitoring + cross-session forensics |
| `pi-token-burden` | extension | Parses the assembled system prompt, shows token budget breakdown per section |
| `pine-of-glass` | extension | pi observability extension (tmustier) |

## 10. Messaging / remote / chat bridges

| Plugin | Type | Function |
|--------|------|----------|
| `@llblab/pi-telegram` | extension | Telegram runtime adapter |
| `pi-courier` | package | Run pi from Matrix: slash commands/skills/prompts available on the messaging side via RPC protocol |
| `@gamalan/pi-gateway` | extension | Multi-platform chat bridge: Telegram/Discord/Slack etc., real-time streaming, per-chat sessions, RBAC |
| `@pi-unipi/notify` | package | Cross-platform notifications: native OS, Gotify, Telegram |
| `pi-intercom` | package | (by nicopreme, multi-machine/messaging interop) |
| `@pi-stef/atlassian` | extension | Atlassian Jira/Confluence verification tools |
| `pi-sync` / `@narumitw/pi-sync` | extension | Sync pi config and sessions via Git/WebDAV/Cloudflare R2/S3 |
| `@misunders2d/agentnet` | extension | Self-hosted, agent-agnostic secure comms network (Claude/Codex/Pi/Antigravity/A2A) |

## 11. All-in-one suites / methodologies / skills

| Plugin | Type | Function |
|--------|------|----------|
| `pi-agent-extensions` | package | Single package with 17 extensions + 4 themes: session/ask-user/handoff/notify/context/files/review/loop/todos/control/answer/cwd-history/btw/powerline-footer/workflow etc. |
| `@pi-unipi/unipi` | package | pi all-in-one extension suite |
| `pi-spark` | package | Polishes daily experience |
| `bigpowers` | skill | 73 agent skills, 17 years of software engineering discipline methodology |
| `superpowers-zh` | skill | superpowers Chinese enhanced edition (250k+ stars fully localized) + 4 original Chinese skills |
| `@dietrichgebert/ponytail` | skill | Lazy senior dev mode: "the best code is the code that was never written" |
| `mitsupi` | extension+skill+theme | Armin (mitsuhiko)'s pi commands, skills, extensions, themes |
| `@selesai/code` | package | Well-maintained extension-first pi: built-in workflows, subagents, web research, questions, skills, enhanced terminal UI |
| `@xynogen/pix-core` | package | Installs and activates all core pix-* extensions |
| `@howaboua/pi-stuff` / `@howaboua/pi-codex-conversion` | package/extension | Codex-oriented tools and prompt adapter family |
| `@reddb-io/red-skills-dev` / `-memory` / `-brain` | package | reddb.io engineering skills: autonomous /afk loops, /go dispatch, triage, tdd, graph-aware code understanding, governed memory, project-local knowledge base |
| `pi-draw` | extension | Drawing/diagram extension (by Armin Ronacher) |
| `pi-generative-ui` | extension | Generative UI: LLM renders interactive HTML/SVG to macOS windows (charts, sliders, dashboards) |
| `pi-tmux` | extension | tmux helper: coordinate long-running commands via semaphore locks, /supervise orchestration, tmux-bash/capture/send/kill |
| `pi-side-agents` | extension | Short-lived tmux/worktree side agents: /agent generation, /agents supervision, async coding sprints |
| `pi-boomerang` | extension | Token-efficient autonomous task execution with context collapse |
| `pi-agentic-compaction` | extension | Virtual filesystem summarizer replacing one-shot compaction, configurable model |
| `runline` | package | Code mode: turn any API or command into a callable action |
| `projectops` | package | Fully automated GitHub project management template integration CLI |
| `@danypops/papyrus` | package | Daemon-backed graph artifacts, evidence-based tasks, rules, skills, native TUI workflows |
| `@danypops/pi-packed` | package | pi package lifecycle, validation, daemons, tools, config, TUI |
| `@danypops/pi-tickets` | extension | tickets daemon (GitHub/GitLab/Jira issue tracking) exposed as LLM-callable tools |
| `@xaccefy/pi-xpi` / `pi-casefile` / `pi-xtodo` / `pi-exploitsearch` | extension | Offensive security toolkit: casefile tracking, web search, exploit technique search, todos |

---

## 12. Curated de-duplication by type (install only one per type)

Many plugins in the catalog overlap. Below, per category we recommend only 1 winner based on "downloads + maintenance activity + security". **Installing multiple of the same type registers same-named tools that interfere with each other — pick one.**

| Category | ✅ Recommended (downloads) | Alternatives (not recommended to install together) | Conflict note |
|----------|---------------------------|---------------------------------------------------|---------------|
| **Subagents** | `pi-subagents` (172.7K/mo, author nicopreme) | `@tintinweb/pi-subagents`, `@narumitw/pi-subagents`, `@mammothb/pi-subagents`, `@ferris1225/pi-subagents`, `@kky42/pi-flow`, `@chaotic1988/pi-subagent` | All register same-named subagent/spawn tools |
| **Web search/scrape** | `pi-web-access` (175.6K/mo) | `pi-deepseek-search`, `@ollama/pi-web-search`, `pi-web-search`, `@narumitw/pi-firecrawl` | All register same-named search/fetch tools |
| **MCP adapter** | `pi-mcp-adapter` (246.4K/mo) | — | The only reliable choice |
| **Code feedback/LSP** | `pi-lens` (41.3K/mo, full-featured) | `@narumitw/pi-lsp` (15.4K/mo, lighter) | Both register LSP/diagnostic tools, would double-diagnose |
| **Plan mode** | `@narumitw/pi-plan-mode` (15.2K/mo) | `@plannotator/pi-extension` (34.4K/mo, **needs a browser GUI, and bash is unrestricted**), `@bacnh85/pi-plan` (heavy all-in-one) | Both intercept editing for read-only planning; plannotator depends on browser + weak security model |
| **Permissions** | `@gotgenes/pi-permission-system` (29.3K/mo) | `pi-sandbox`, `cc-safety-net`, `pi-security-scanner` | See "permissions recommended vs alternatives" below |
| **Security audit** | `@vigolium/piolium` (**478.7K/mo, #1 in catalog**) | `@panzenbaby/pi-secure-extension` | piolium is audit, complements (does not conflict with) the permission gate |
| **Memory** | `pi-hermes-memory` (19.4K/mo, SQLite FTS5 search + auto consolidation + **built-in secret scanning**, 732 tests) ✅ user-chosen | `@remnic/plugin-pi` (42.1K/mo), `pi-memory`, `open-zk-kb`, `pi-vault-mind`, `pi-goosedump`, `gentle-engram` | All register memory tools/event hooks, install only one |
| **Autonomy/goals** | `@narumitw/pi-goal` (24.2K/mo, lightweight single-purpose) | `pi-goal-list-loop-audit`, `pi-autopilot`, `pi-autoresearch`, `gentle-pi`, `@quintinshaw/pi-dynamic-workflows`, `@mjasnikovs/pi-task` | **Two-Driver Rule**: any plugin that auto-continues via `agent_end` is mutually exclusive; only one driver per session |
| **Context optimization** | `pi-lean-ctx` | `context-mode` (72.8K/mo, **includes a hosted cloud analytics page**), `pi-agentic-compaction`, `pi-boomerang`, `@hypabolic/pi-hypa`, `pi-rtk-optimizer` | All rewrite tool output/compress context; context-mode uploads usage data to the cloud |
| **UI status bar** | `@narumitw/pi-statusline` | `pi-powerline-footer` (11.8K/mo), `pi-zentui`, `@narumitw/pi-starship` | All modify the bottom status bar, stacking conflicts |
| **Todo overlay** | `@juicesharp/rpiv-todo` (34.6K/mo) | `pi-todos` (inside the all-in-one suite) | Both render a todo overlay |

> Independent plugins with no same-type competition, install on demand: standalone tools beyond `pi-lens`, `pi-hashline-edit-pro`, `@mammothb/pi-office`, `@mammothb/pi-ghsearch`, `@narumitw/pi-worktree`, `@narumitw/pi-github-pr`, `pi-tmux`, `pi-draw`, `pi-markdown-preview`, `@juicesharp/rpiv-ask-user-question`, `pi-ask-user`, `pi-interview`, `pi-cache-optimizer`, `pi-provider-litellm`, `pi-lmstudio` etc.

## 13. Security notes (important)

**1. Two fixed CVEs in pi itself (this image's pi 0.83.0 is not affected)**
- **CVE-2026-54328** (high): pi `<0.78.1` temporary extension install paths are predictable, enabling local privilege escalation on shared Linux hosts -> **fixed in 0.78.1**.
- **CVE-2026-54325** (medium): pi `<0.79.0` loads project-local `.pi/` extensions without asking for trust, so a malicious repo can inject code -> **fixed in 0.79.0** (added project trust gating).

**2. Known malicious npm packages (do not install)**
- `pi-exa-mcp` contains malicious code (MAL-2026-3280 / GHSA-fpc5-w8c8-3mhv). **If you already installed it, consider yourself fully compromised; rotate all keys on another machine immediately.**
- Mini Shai Hulud supply-chain attack: the `@antv` npm org was compromised, 640 versions were blacklisted, 61K tokens invalidated. Reminder: use `npm install --ignore-scripts` when installing untrusted packages to prevent preinstall hooks.

**3. Extensions are not sandboxes**: all pi extensions run with **the caller's full permissions** (can read files, keys, network). Always review third-party extension source before installing.

**4. Security-enhancement plugins (keep 1-2 in the image)**
- `@vigolium/piolium` (478.7K/mo) — multi-stage security audit (expert subagents, isolated context, concurrency caps)
- `@gotgenes/pi-permission-system` (29.3K/mo) — permission enforcement gate
- `pi-security-scanner` — runtime interception of dangerous bash (curl/wget/nc) + static scan of installed extensions
- `pi-hermes-memory` — memory plugin but with **built-in secret scanning**

## 14. Final install list (user-confirmed)

> ✅ = user-confirmed install. All plugins are installed by the container's built-in `install.sh` into the mounted `~/.pi/agent` (`docker compose exec pi install.sh plugins all`, or specify `--core/--perms/--im/--web/--remote/--memory`). Only one plugin per type is installed, to avoid tool-name conflicts.

**Core (required, 6) ✅:**
1. `pi-mcp-adapter` (246K) — MCP ecosystem entry
2. `pi-subagents` (173K) — subagent parallel/dispatch
3. `pi-web-access` (176K) — web search/scrape/PDF/video
4. `pi-lens` (41K) — real-time code feedback
5. `@gotgenes/pi-permission-system` (29K) — permission gate (also required in the perms group)
6. `@narumitw/pi-statusline` — status bar

**Permissions/security group (all 3) ✅:**
- `@gotgenes/pi-permission-system` — gate (required)
- `@vigolium/piolium` — session audit (recommended)
- `@panzenbaby/pi-secure-extension` — source review before plugin install (optional but confirmed)

**IM chat group (one per channel) ✅:**
- Telegram: `@llblab/pi-telegram`
- Feishu/Lark: `pi-feishu-lark`
- WeChat: `pi-wechat-assistant`

**Web UI ✅:** `pi-web-chat` (`pi --web`, port 3141)

**Remote control ✅:** `remote-pi` (iOS/Android App + self-hosted relay)

**Memory ✅:** `pi-hermes-memory` (with secret scanning)

**Other on-demand (not installed, add later if needed):**
- Planning: `@narumitw/pi-plan-mode`
- Autonomy goals: `@narumitw/pi-goal`
- Context savings: `pi-lean-ctx`
- Strict large-file editing: `pi-hashline-edit-pro`
- Document preview: `pi-markdown-preview`
- Office/PDF reading: `@mammothb/pi-office`

**Not recommended to pre-install (into the image layer):**
- Need external service/API key: `pi-firecrawl`, `@braintrust/pi-extension`, `pi-langfuse`, `@llblab/pi-telegram`, `pi-deepseek-search`, `pi-web-search`, `pi-intercom`
- Need GUI/browser/mic (no GUI in a container): `pi-agent-browser-native`, `rpiv-voice`, `pi-image-drop`, `betterwright`, `pi-generative-ui`
- Heavyweight suites (change pi's default behavior; you decide): `gentle-pi`, `pi-goal-list-loop-audit`, `@pi-unipi/unipi`, `pi-maestro-flow`, `bigpowers`
- Malicious-package red line: **`pi-exa-mcp` must never be installed**

> Pre-install method (during Dockerfile build or in the first-startup script):
> ```bash
> pi install npm:pi-mcp-adapter npm:pi-subagents npm:pi-web-access \
>            npm:pi-lens npm:@gotgenes/pi-permission-system npm:@narumitw/pi-statusline
> ```
> Plugins themselves are tiny (most <1MB); the bulk comes from external toolchains, so baking them in is no burden.

### Rationale for four key choices

In these categories the highest-download option is **not necessarily the best fit** for your scenario; here is why we picked each:

**1. Status bar -> `@narumitw/pi-statusline` (not powerline-footer)**
- The higher-download `pi-powerline-footer` (11.8K/mo) is flashy, but it **takes over the TUI's fixed-editor, mouse scrolling, and setFooter()**, is invasive, and the community has multiple confusing forks.
- `@narumitw/pi-statusline` **does only the status bar cleanly**: zero config, responsive auto-degradation, optional info levels (model/thinking/branch/context/tokens/cost/time), and is compatible with other extensions' status displays.
- **Same author/ecosystem as planning**: `@narumitw/pi-plan-mode` injects a plan status icon into its status bar; both come from the same monorepo, so compatibility is guaranteed.
- Official docs say the two cannot be enabled together (both use setFooter()).

**2. Context -> `pi-lean-ctx` (not the top-download context-mode)**
- The top-download `context-mode` (72.8K/mo) is powerful (sandbox execution + FTS5 knowledge base), but **includes a hosted analytics page and uploads usage data to context-mode.com** — a privacy/security concern for a local Docker box.
- `pi-lean-ctx` uses a **local standalone binary + deterministic compression** (no LLM summarizer, source/command output never leaves the machine), tool output is not stuffed into context, and unchanged re-reads cost only ~13 tokens.
- Default **additive** (keeps pi's built-in read/bash/grep) rather than replace, reducing collateral damage; ships a `/lean-ctx` self-check command.

**3. Planning -> `@narumitw/pi-plan-mode` (not the top-download plannotator)**
- The higher-download `@plannotator/pi-extension` (34.4K/mo) needs **a browser GUI to approve/annotate the plan after planning** — no browser in a container, unusable; also, bash is unrestricted during planning, constrained only by the system prompt, a weak security model.
- `@narumitw/pi-plan-mode` is **pure terminal, Codex style**: `/plan` read-only exploration, editing/writing disabled by default, injects `plan_mode_question` clarification + `plan_mode_complete` wrap-up. Fits the container's no-GUI nature and is safer (fail-closed).

**4. Autonomy -> `@narumitw/pi-goal` (not the all-in-one suites)**
- This category has the **Two-Driver Rule**: any plugin that auto-continues via `agent_end` is mutually exclusive; only one per session. `pi-goal-list-loop-audit`, `pi-autopilot`, `pi-autoresearch`, `gentle-pi` are all heavy suites (interview-style goals/audit loops); installing more than one conflicts and changes default behavior.
- `@narumitw/pi-goal` is **lightweight and single-purpose**: adds only `/goal` + completion/blocked tools + evidence audit, no extra session drivers; its companion `pi-subagents` is enough.
- If you truly need "implement/verify separation" with very strong safe autonomy, consider `pi-goal-list-loop-audit` (isolated audit session to prevent self-flattery), but it hard-conflicts with pi-goal — pick one.

## 15. Permissions/security: recommended vs alternatives (detailed)

This category is easy to confuse. First distinguish the two very different mechanisms, **"gate"** and **"audit"**, then decide what to install:

### Gate type (intercepts before execution, prevents dangerous actions)
| Plugin | Mechanism | Coverage | Key differences |
|--------|-----------|----------|-----------------|
| **`@gotgenes/pi-permission-system` (recommended)** | Hides/disables tools in `before_agent_start` + adjudicates on `tool_call` via **allow/ask/deny** (fail-closed: unparseable commands -> ask, not allow) | tool, bash, MCP, skill, special operations, cross-tool `path` surface, dirs outside `cwd` | **Most complete**: bash wildcards (`git *: ask`, `rm -rf *: deny`), unified protection of sensitive files like `.env`/`~/.ssh` across all tools, symlink aliases can't bypass, subagent ask forwarding. JSON config, layered global/project/per-agent |
| `pi-sandbox` | OS-level sandbox wrapping the pi process + interactive permission prompts | whole process | Higher isolation (sandboxed), but changes how it runs, more complex config; not fine-grained |
| `cc-safety-net` | CLI hooks intercept **destructive git/file commands** before execution | git/file commands only | Minimal; only blocks rm -rf/git push etc., does not cover MCP/skill; can complement permission-system |

**-> Gate conclusion: in a container choose `@gotgenes/pi-permission-system` (fine-grained + fail-closed + subagent support); `cc-safety-net` can stack but is not required; `pi-sandbox` is of little use in Docker (the container is already a sandbox).**

### Audit type (finds problems / post-hoc review, does not block)
| Plugin | Mechanism | Key differences |
|--------|-----------|-----------------|
| `@vigolium/piolium` (**478.7K/mo, #1 downloads in catalog**) | Multi-stage security audit: dispatches expert subagents, isolated context, concurrency caps, resumable state | Audits the **session process**; the most community-endorsed |
| `@panzenbaby/pi-secure-extension` | Reads plugin source with the current LLM before install/update, scores by rules (data exfiltration/sensitive files/code execution/supply chain) | Targets **pre-install** review of plugins, guards against malicious npm packages (like the pi-exa-mcp incident) |
| `pi-security-scanner` | Runtime interception of dangerous bash + static scan of installed extension source | Gate+audit hybrid, `/security-shield` toggle |

**-> Audit conclusion: can coexist and complement the gate. If you pick only one security enhancement, choose `@vigolium/piolium` (dominates downloads, most ecosystem endorsement); `pi-secure-extension` is a great complement for blocking malicious plugins.**

### Recommended combo
```
permission gate   -> @gotgenes/pi-permission-system   (required, intercepts before execution)
security audit    -> @vigolium/piolium                 (recommended, session audit)
plugin review     -> @panzenbaby/pi-secure-extension  (optional, guards against malicious npm packages)
```

## 16. Three direction-specific plans for your needs

> Research found: **TG/Feishu/WeChat have no all-in-one plugin**, each channel must be wired separately. Below is recommended by your priority.

### 1. Web UI (want simple, self-extensible, not bloated)
| Option | Features | Best for |
|--------|----------|----------|
| **`pi-web-chat` (recommended)** | Minimal OpenWebUI style, `pi --web` one-command start (default port 3141), session list/streaming/tool display; pure pi extension, <1MB | **Simple + extend it yourself later**, no extra Go/Node binaries |
| `@ygncode/pi-web` (alternative) | Go single binary + PWA (installable as a mobile app), Tailscale remote, multilingual, token auth | PWA mobile experience + built-in remote |
| `@jmfederico/pi-web` (heavy) | Persistent session daemon, remote fleet, built-in terminal, most features | Not recommended: complex UI, contradicts "simple" |

**-> Choose `pi-web-chat` (simplest, free to extend), exclude `@jmfederico/pi-web`.**

### 2. IM chat (TG / Feishu / WeChat)
| Channel | ✅ Option | Notes |
|---------|-----------|-------|
| Telegram | `@gamalan/pi-gateway` or `@llblab/pi-telegram` | Former is multi-platform + RBAC (port 3847), latter is TG-only and lighter |
| Feishu/Lark | `pi-feishu-lark` | Most mature and easy: scan to create bot, separate private/group/topic sessions, background daemon, supports card streaming + markdown |
| WeChat | `pi-wechat-assistant` | Published npm extension (v0.3.0): WeChat iLink scan-to-connect, two-way sync with one pi TUI session, image/file/voice, `/wechat` autostart. (The old `pi-wechat-bridge` is a separate GitHub service, not an `npm:` package — dropped) |
| Unified gateway (optional) | `@gamalan/pi-gateway` | One-stop TG/Discord/Slack/WhatsApp/Twitch/WS integration, but **does not include Feishu/WeChat** |

**-> Combo: TG via `@gamalan/pi-gateway` (if you also want Discord/Slack), or `@llblab/pi-telegram` (TG only) + Feishu `pi-feishu-lark` + WeChat `pi-wechat-assistant`. The three can coexist (each on its own channel, no tool-name conflicts).**

### 3. Remote control (want App + self-hostable service)
| Option | Features |
|--------|----------|
| **`remote-pi` (recommended)** | Flutter iOS/Android **native App** + control Pi from phone: QR pairing, real-time tool-call view, multi-machine UDS mesh proxy chat; relay self-hostable with a single Docker command + VPN (Tailscale/WireGuard); or use the official hosted relay. **Exactly the shape you want** |
| `@pragmaticcoder/pi-remote-control` | Android APK controls the TUI session, Android only |
| `sxwxs/pi2web` | Web UI + Android native client (Kotlin/Compose), Bearer pairing, listens on 127.0.0.1 by default |

**-> Choose `remote-pi`: ships both-end Apps + self-hosted relay, matches "has an app + self-hostable service".**

### Summary recommendation
```
Web UI      -> pi-web-chat (lightweight, add features later)
IM chat     -> TG: @llblab/pi-telegram (or @gamalan/pi-gateway)
               Feishu: pi-feishu-lark   WeChat: pi-wechat-assistant
Remote ctrl -> remote-pi (iOS/Android App + self-hosted relay + Tailscale)
```
Service ports: pi-web-chat 3141, gateway 3847, remote-pi relay (customizable) — no conflicts.

## Other sources
- Official catalog: <https://pi.dev/packages> (109 pages, 5426 packages, filterable by type/downloads)
- npm search: `npm search pi-package` (with `pi-package` / `pi-coding-agent` keywords)
- narumiruna extensions monorepo: <https://github.com/narumiruna/pi-extensions>
- Ecosystem tracking: <https://taoofmac.com/space/ai/agentic/pi>
- Discord community #packages channel (Discord ID `1456806362351669492`)
