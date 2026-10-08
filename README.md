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
swipl -q -s prolog/server.pl -g "mnn2_server:start(8080),thread_get_message(stop)"
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

Location facts can be composed for an owned object, for example: “John owns an
apple”, “The apple is in the kitchen”, “The kitchen is in the house”, and “Where
is John's apple?”. Explicit workplace corrections of the form “Actually, she
moved to Gamma, not Beta” supersede the latest matching workplace event and
retain the correction relationship in exported event data.

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

## Remaining unfinished features from the specification

The implementation is an intentionally small foundation; the following
specification areas are not complete:

- **Language interpretation:** broad paraphrase support, interpretation
  alternatives and ambiguity handling, general pronoun/reference resolution,
  sentence-function classification, and preservation of nuance and negation.
- **Discourse and temporal reasoning:** signpost/causal/contrast relationships,
  general temporal relations and natural-language date handling, explicit state
  transitions, contradiction analysis, and general correction language. The
  current correction support is limited to explicit workplace destination
  corrections.
- **Context and memory:** multiple isolated contexts, context stacks,
  hypothetical worlds, working-memory layers, topic tracking, goals, decisions,
  and unresolved-question tracking.
- **Reasoning:** general question decomposition, recursive knowledge/rule
  application, constrained knowledge composition, algorithm selection, and an
  MNN1 reasoning adapter. Current rule and question handling covers only a few
  fixed patterns.
- **Responses and explanations:** structured response planning, selectable
  response modes, broader explanation/trace structures, and explanations for
  ranking and temporal transitions.
- **Documents and provenance:** structured JSON/CSV/HTML import, document
  segmentation and revision histories, and source metadata beyond retained
  utterance text.
- **Interfaces and evaluation:** current-context and algorithm viewers,
  benchmark controls, systematic benchmarks/metrics, ablation configurations,
  and the broader regression suite required by the specification.

The full requirements and examples remain in [`pr1.txt`](pr1.txt); these items
should be treated as future work rather than implied supported behavior.
