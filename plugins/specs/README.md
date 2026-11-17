# specs

The shared formats of the Alpaga agents. A format is a contract between the agent that writes a document and the agent that reads it, so its template and validator live here, in one place, and each agent calls the same commands.

```
templates/tech-spec.md        the tech spec template
bin/spec-template             prints a template:  spec-template tech
bin/validate-tech-spec.sh     checks a tech spec, prints its metadata (--help: format and meaning of each field)
```

| Document | Written by | Read by |
|---|---|---|
| tech spec | techlead-agent | dev-agent (senior-dev) |
| product spec | product-agent (to come) | techlead-agent |

## Install

```
/plugin install specs --marketplace Alp4g4/alp-agora
```

Install it next to any agent that writes or reads a spec. A plugin's `bin/` is on the PATH of the agents, so they call `spec-template` and `validate-tech-spec.sh` by name.

## Tech spec

One markdown file per tech spec, named `<id>.md`, in the `tech-specs/` folder of the project. `bin/validate-tech-spec.sh --help` gives the format and the purpose of each field.

It is the same format as the former dev-agent ticket, plus two optional fields for a story split into several specs: `story` (the product spec it comes from) and `depends_on` (the specs to deliver first).

## Status

`dev-agent` uses `validate-tech-spec.sh` from here (the `senior-dev` agent).
