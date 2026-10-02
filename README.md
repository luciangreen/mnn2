# MNN2 — Interpretive Manual Neuronet

MNN2 is a deterministic, data-readable Prolog chatbot foundation. It records
utterances as ordered events, retains source text, applies explicit user rules,
answers a small set of supported questions, and returns evidence and a
human-readable trace separately from the answer.

This repository is an initial implementation, not the complete research
programme in [`pr1.txt`](pr1.txt). The current language interface deliberately
supports a limited set of patterns and preserves unrecognised statements
without inferring facts from them. MNN1 and the other systems named in the
specification do not yet exist here; the reasoning boundary is kept symbolic
so adapters can be added without making language generation authoritative.

## Requirements

- SWI-Prolog 9 or newer

No external Prolog packages are required.

## Run the chatbot

From the repository root:

```sh
swipl -q -s prolog/server.pl -- 8080
```

Open <http://localhost:8080>. Information is kept in memory for the lifetime of
the server. Use **Clear conversation** to remove it, or **Export knowledge** to
download event and rule data as JSON.

The interface supports statement entry, questions, plain-text/Markdown import
(one statement per non-empty line), source evidence, a conversation timeline,
and rule inspection. Supported examples include:

```text
John owns an apple.
The apple is red.
What colour is John's apple?
```

```text
A premium customer receives free shipping.
Alice is a premium customer.
Does Alice receive free shipping?
```

Employment statements such as “John works at A”, “John left A”, and “John
joined B” are ordered by insertion sequence; the latest recorded state is used
for a workplace question.

## Tests

Run the plunit suite from the repository root:

```sh
swipl -q -g run_tests -t halt tests/test_mnn2.pl
```

## Current scope

The core exposes `ingest/2-3`, `ask/2`, `respond/2`, `events/1`, `rules/1`,
`reset/0`, and `export_knowledge/1` in `prolog/mnn2.pl`. Its event sequence
provides deterministic conversational ordering, while query answers include
the source statements actually selected. Natural-language dates, arbitrary
document formats, broad paraphrase interpretation, context switching,
hypotheticals, and external MNN1/S2A/AIOC adapters remain future work.
