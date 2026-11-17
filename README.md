# alp-agora

A Claude Code marketplace of skills and agents that hold how I work: the rules, the examples, and the checks I would give a colleague. The skills carry the knowledge, and the agents do the work with it.

## Plugins

| Plugin | What it holds |
|---|---|
| `go` | Skills for Go applications: clean architecture, SQL with sqlc and goose, server-rendered pages with templ and htmx, and the definition of done of a Go change |
| `web-design` | A skill for the UI and UX of web interfaces built with Tailwind CSS, not tied to a language |
| `specs` | The shared formats of the agents: the tech spec template and its validator. Agents that write or read a spec install it |
| `dev-agent` | `senior-dev`, an agent that implements a ticket in its own worktree, opens a pull request, and handles the review rounds. It never merges |

### Skills

| Skill | Use it for |
|---|---|
| `go:go-clean-architecture` | the domain, use cases and their ports, infrastructure, delivery, and `main`, with the dependency rule checked by a script |
| `go:go-sql` | the schema, the goose migrations, and the sqlc queries, on PostgreSQL or SQLite |
| `go:go-ssr` | pages, forms, and htmx interactions rendered with templ |
| `go:go-definition-of-done` | the `make check` gate a Go change must pass, and its template |
| `web-design:ui-ux-design` | the theme of design tokens, the component catalog, accessibility, and responsive layouts |

### Agents

| Agent | Started with |
|---|---|
| `dev-agent:senior-dev` | `bin/dev implement <ticket>` or `bin/dev review <PR URL>`, see `plugins/dev-agent/README.md` |

## Install

```
/plugin marketplace add Alp4g4/alp-agora
/plugin install go@alp-agora
/plugin install web-design@alp-agora
/plugin install specs@alp-agora
/plugin install dev-agent@alp-agora
```

## Layout

```
.claude-plugin/marketplace.json     the list of plugins
plugins/<plugin>/
├── .claude-plugin/plugin.json      name, description, version, metadata
├── skills/<skill>/
│   ├── SKILL.md                    what the skill does, when to use it, and which file to read for a task
│   ├── <topic>.md                  the rules of one topic, read only when the task needs it
│   ├── references/                 complete examples, tested
│   └── scripts/                    checks a command can run better than a reader
├── agents/                         agents
├── hooks/                          hooks of the plugin's agents
└── bin/                            scripts on the PATH of the plugin's agents
```

## Conventions

- **A skill stands alone.** It never requires another plugin. Skills of the same plugin may point to each other by name.
- **`SKILL.md` routes, the files hold the rules.** It stays short and tells which file to read for a task, so a task loads only what it needs. Every other file is linked directly from it.
- **Examples compile.** Code in `references/` is tested before it is published.
- **Checks are scripts.** What a command can verify (the dependency rule, a ticket's format, `make check`) is a script, not an instruction.

## Checking the marketplace

```
claude plugin validate . --strict
```
