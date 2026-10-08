:- begin_tests(mnn2).

:- use_module('../prolog/mnn2').

test(canonical_facts_and_provenance,
     [setup(reset), cleanup(reset)]) :-
    ingest("John owns an apple.", _),
    ingest("The apple is red.", _),
    ask("What colour is John's fruit?", Response),
    assertion(Response.status == answered),
    assertion(sub_string(Response.answer, _, _, _, "apple is red")),
    assertion(length(Response.evidence, 2)),
    get_dict(evidence, Response, [Ownership, _]),
    assertion(Ownership.canonical == "owns(john,apple)").

test(latest_employment_state,
     [setup(reset), cleanup(reset)]) :-
    ingest("John works at A.", _),
    ingest("John left A.", _),
    ingest("John joined B.", _),
    ask("Where does John work?", Response),
    assertion(Response.status == answered),
    assertion(sub_string(Response.answer, _, _, _, "works at b")).

test(departure_without_new_workplace,
     [setup(reset), cleanup(reset)]) :-
    ingest("John works at A.", _),
    ingest("John left A.", _),
    ask("Where does John work?", Response),
    assertion(Response.status == insufficient_information),
    assertion(sub_string(Response.answer, _, _, _, "left a")).

test(rule_application_with_evidence,
     [setup(reset), cleanup(reset)]) :-
    ingest("A premium customer receives free shipping.", _),
    ingest("Alice is a premium customer.", _),
    ask("Does Alice receive free shipping?", Response),
    assertion(Response.status == answered),
    assertion(sub_string(Response.answer, _, _, _, "Yes.")),
    assertion(length(Response.evidence, 2)).

test(missing_property_is_not_invented,
     [setup(reset), cleanup(reset)]) :-
    ingest("John owns an apple.", _),
    ask("What colour is John's apple?", Response),
    assertion(Response.status == insufficient_information),
    assertion(sub_string(Response.answer, _, _, _, "do not have a recorded colour")).

test(latest_state_is_selected_and_cited,
     [setup(reset), cleanup(reset)]) :-
    ingest("John owns an apple.", _),
    ingest("The apple is red.", _),
    ingest("The apple is green.", _),
    ask("What colour is John's apple?", Response),
    assertion(Response.status == answered),
    assertion(sub_string(Response.answer, _, _, _, "apple is green")),
    get_dict(evidence, Response, [_, ColourEvidence]),
    assertion(ColourEvidence.source == "The apple is green."),
    assertion(member("recency(3)", ColourEvidence.ranking)).

test(composed_owned_object_location,
     [setup(reset), cleanup(reset)]) :-
    ingest("John owns the apple.", _),
    ingest("The apple is in the kitchen.", _),
    ingest("The kitchen is in the house.", _),
    ask("Where is John's apple?", Response),
    assertion(Response.status == answered),
    assertion(sub_string(Response.answer, _, _, _, "john's apple is in kitchen")),
    assertion(sub_string(Response.answer, _, _, _, "which is in house")),
    assertion(length(Response.evidence, 3)).

test(workplace_correction_preserves_supersession,
     [setup(reset), cleanup(reset)]) :-
    ingest("Alice works at Alpha.", _),
    ingest("Alice moved to Beta last month.", _),
    ingest("Actually, she moved to Gamma, not Beta.", Result),
    assertion(Result.type == correction),
    ask("Where does Alice work?", Response),
    assertion(Response.status == answered),
    assertion(sub_string(Response.answer, _, _, _, "works at gamma")),
    assertion(length(Response.evidence, 2)),
    events(Events),
    last(Events, Correction),
    assertion(Correction.relationships == ["supersedes(3,2)"]).

test(summary_uses_recorded_source_text,
     [setup(reset), cleanup(reset)]) :-
    ingest("John owns an apple.", _),
    ask("What happened?", Response),
    assertion(sub_string(Response.answer, _, _, _, "John owns an apple.")).

test(unsupported_language_is_preserved,
     [setup(reset), cleanup(reset)]) :-
    ingest("A complex unsupported sentence.", Result),
    assertion(Result.type == utterance),
    events([Event]),
    assertion(Event.source == "A complex unsupported sentence.").

:- end_tests(mnn2).
