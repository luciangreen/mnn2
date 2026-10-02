:- module(mnn2,
          [ reset/0,
            ingest/2,
            ingest/3,
            ask/2,
            respond/2,
            events/1,
            rules/1,
            export_knowledge/1
          ]).

:- use_module(library(lists)).
:- use_module(library(pcre)).

:- dynamic stored_event/8.
:- dynamic stored_rule/5.
:- dynamic event_counter/1.

event_counter(0).

reset :-
    retractall(stored_event(_, _, _, _, _, _, _, _)),
    retractall(stored_rule(_, _, _, _, _)),
    retractall(event_counter(_)),
    assertz(event_counter(0)).

ingest(Text, Result) :-
    ingest(Text, user, Result).

ingest(Text, Speaker, Result) :-
    text_string(Text, Source),
    next_event_id(Id),
    (   parse_statement(Source, Type, Canonical)
    ->  true
    ;   Type = utterance,
        Canonical = unparsed
    ),
    assertz(stored_event(Id, Id, now, Speaker, Type, Canonical, Source, conversation)),
    maybe_store_rule(Id, Source, Canonical),
    Result = _{id:Id, type:Type, canonical:Canonical, source:Source}.

next_event_id(Id) :-
    retract(event_counter(Current)),
    Id is Current + 1,
    assertz(event_counter(Id)).

text_string(Text, String) :-
    (string(Text) -> String = Text ; atom_string(Text, String)).

parse_statement(Source, fact, owns(Owner, Object)) :-
    capture(Source, '^\\s*(.+?)\\s+owns\\s+(.+?)\\s*[.!?]?\\s*$', [OwnerText, ObjectText]),
    !,
    entity_atom(OwnerText, Owner),
    entity_atom(ObjectText, Object).
parse_statement(Source, fact, color(Entity, Color)) :-
    capture(Source, '^\\s*(.+?)\\s+is\\s+(?:a\\s+|an\\s+)?(red|blue|green|yellow|black|white|orange|purple)\\s*[.!?]?\\s*$', [EntityText, ColorText]),
    !,
    entity_atom(EntityText, Entity),
    entity_atom(ColorText, Color).
parse_statement(Source, fact, employment(Entity, Employer)) :-
    capture(Source, '^\\s*(.+?)\\s+works\\s+at\\s+(.+?)\\s*[.!?]?\\s*$', [EntityText, EmployerText]),
    !,
    entity_atom(EntityText, Entity),
    entity_atom(EmployerText, Employer).
parse_statement(Source, fact, employment(Entity, Employer)) :-
    capture(Source, '^\\s*(.+?)\\s+(?:joined|moved\\s+to)\\s+(.+?)\\s*[.!?]?\\s*$', [EntityText, EmployerText]),
    !,
    entity_atom(EntityText, Entity),
    entity_atom(EmployerText, Employer).
parse_statement(Source, fact, left(Entity, Employer)) :-
    capture(Source, '^\\s*(.+?)\\s+left\\s+(.+?)\\s*[.!?]?\\s*$', [EntityText, EmployerText]),
    !,
    entity_atom(EntityText, Entity),
    entity_atom(EmployerText, Employer).
parse_statement(Source, fact, location(Entity, Place)) :-
    capture(Source, '^\\s*(.+?)\\s+is\\s+in\\s+(.+?)\\s*[.!?]?\\s*$', [EntityText, PlaceText]),
    !,
    entity_atom(EntityText, Entity),
    entity_atom(PlaceText, Place).
parse_statement(Source, fact, is_a(Entity, Category)) :-
    capture(Source, '^\\s*(.+?)\\s+is\\s+(?:a|an)\\s+(.+?)\\s*[.!?]?\\s*$', [EntityText, CategoryText]),
    !,
    entity_atom(EntityText, Entity),
    entity_atom(CategoryText, Category).
parse_statement(Source, fact, property(Entity, Property, Value)) :-
    capture(Source, '^\\s*(.+?)\\s+has\\s+(.+?)\\s*[.!?]?\\s*$', [EntityText, PropertyText]),
    !,
    entity_atom(EntityText, Entity),
    entity_atom(PropertyText, Property),
    Value = true.

capture(Text, Pattern, Captures) :-
    re_matchsub(Pattern, Text, Match, [capture_type(string), caseless(true)]),
    Match =.. [_|Values],
    Values = [_|Captures].

entity_atom(Text, Atom) :-
    string_lower(Text, Lower),
    normalize_space(string(Trimmed), Lower),
    re_replace('^[[:space:]]*(the|a|an)[[:space:]]+'/i, '', Trimmed, WithoutArticle),
    re_replace('[.!?,;:]+[[:space:]]*$'/'', WithoutArticle, Clean),
    normalize_space(string(Flat), Clean),
    split_string(Flat, " ", " ", Parts),
    atomic_list_concat(Parts, '_', Atom).

maybe_store_rule(Id, Source, _) :-
    capture(Source, '^\\s*(?:a|an)\\s+(.+?)\\s+receives\\s+(.+?)\\s*[.!?]?\\s*$', [CategoryText, BenefitText]),
    !,
    entity_atom(CategoryText, Category),
    entity_atom(BenefitText, Benefit),
    assertz(stored_rule(Id, is_a(Entity, Category), receives(Entity, Benefit), user, Source)).
maybe_store_rule(_, _, _).

events(Events) :-
    findall(_{id:Id, sequence:Seq, time:Time, speaker:Speaker, type:Type,
              canonical:Canonical, source:Source, context:Context},
            stored_event(Id, Seq, Time, Speaker, Type, Canonical, Source, Context),
            Events).

rules(Rules) :-
    findall(_{id:Id, condition:Condition, conclusion:Conclusion,
              source:Source, text:Text},
            stored_rule(Id, Condition, Conclusion, Source, Text),
            Rules).

export_knowledge(_{events:Events, rules:Rules}) :-
    events(Events),
    rules(Rules).

respond(Text, Response) :-
    text_string(Text, Source),
    (   is_question(Source)
    ->  ask(Source, Response)
    ;   ingest(Source, _),
        Response = _{status:stored, answer:"I recorded that information.",
                     evidence:[], trace:[]}
    ).

is_question(Text) :-
    (   sub_string(Text, _, _, _, "?")
    ->  true
    ;   string_lower(Text, Lower),
        re_match('^\\s*(who|what|when|where|why|how|which|does|do|did|is|are|was|were|can|could|would|will)\\b', Lower)
    ).

ask(Text, Response) :-
    text_string(Text, Source),
    (   question_goal(Source, Goal, QueryType)
    ->  answer_goal(Goal, QueryType, Response)
    ;   Response = _{status:unsupported_question,
                     answer:"I could not identify a supported question pattern.",
                     evidence:[], trace:[]}
    ).

question_goal(Text, color_of_owned(Person), colour_question) :-
    capture(Text, '^\\s*what\\s+colou?r\\s+is\\s+(.+?)\\s*\\??\\s*$', [SubjectText]),
    !,
    possessive_owner(SubjectText, Person).
question_goal(Text, current_employer(Person), employment_question) :-
    capture(Text, '^\\s*where\\s+does\\s+(.+?)\\s+work\\s*\\??\\s*$', [SubjectText]),
    !,
    entity_atom(SubjectText, Person).
question_goal(Text, current_employer(Person), employment_question) :-
    capture(Text, '^\\s*where\\s+does\\s+(.+?)\\s+currently\\s+work\\s*\\??\\s*$', [SubjectText]),
    !,
    entity_atom(SubjectText, Person).
question_goal(Text, receives(Person, Benefit), yes_no_question) :-
    capture(Text, '^\\s*does\\s+(.+?)\\s+receive\\s+(.+?)\\s*\\??\\s*$', [PersonText, BenefitText]),
    !,
    entity_atom(PersonText, Person),
    entity_atom(BenefitText, Benefit).
question_goal(Text, latest_events, summary_question) :-
    re_match('^\\s*(what\\s+happened|summari[sz]e|what\\s+changed)', Text, [caseless(true)]),
    !.

possessive_owner(Text, Owner) :-
    re_replace("'s[[:space:]]+.*$"/'', Text, OwnerText),
    entity_atom(OwnerText, Owner).

answer_goal(color_of_owned(Person), colour_question, Response) :-
    ranked_event(owns(Person, Object), Ownership, _),
    ranked_event(color(Object, Color), ColourEvent, _),
    !,
    format(string(Answer), "~w's ~w is ~w.", [Person, Object, Color]),
    evidence([Ownership, ColourEvent], Evidence),
    trace(["The selected owner has the object.", "The object has the recorded colour.", Answer], Trace),
    Response = _{status:answered, answer:Answer, evidence:Evidence, trace:Trace}.
answer_goal(color_of_owned(Person), colour_question, Response) :-
    find_event(owns(Person, Object), Ownership),
    !,
    format(string(Answer), "I know ~w owns ~w, but I do not have a recorded colour for it.", [Person, Object]),
    evidence([Ownership], Evidence),
    Response = _{status:insufficient_information, answer:Answer, evidence:Evidence,
                 trace:["The ownership fact was found; no colour fact for that object was found."]}.
answer_goal(color_of_owned(Person), colour_question, Response) :-
    format(string(Answer), "I do not have enough information to identify the colour of ~w's object.", [Person]),
    Response = _{status:insufficient_information, answer:Answer, evidence:[], trace:[]}.
answer_goal(current_employer(Person), employment_question, Response) :-
    latest_employment(Person, Employer, Event),
    !,
    format(string(Answer), "~w currently works at ~w.", [Person, Employer]),
    evidence([Event], Evidence),
    Response = _{status:answered, answer:Answer, evidence:Evidence,
                 trace:["Employment events are ordered by insertion sequence.", Answer]}.
answer_goal(current_employer(Person), employment_question, Response) :-
    find_event(left(Person, Employer), Event),
    !,
    format(string(Answer), "The latest recorded employment event says ~w left ~w; no later workplace is recorded.", [Person, Employer]),
    evidence([Event], Evidence),
    Response = _{status:insufficient_information, answer:Answer, evidence:Evidence,
                 trace:["A departure was found, with no later employment event."]}.
answer_goal(current_employer(Person), employment_question, Response) :-
    format(string(Answer), "I do not have a recorded workplace for ~w.", [Person]),
    Response = _{status:insufficient_information, answer:Answer, evidence:[], trace:[]}.
answer_goal(receives(Person, Benefit), yes_no_question, Response) :-
    stored_rule(_, is_a(Person, Category), receives(Person, Benefit), RuleSource, RuleText),
    ranked_event(is_a(Person, Category), Fact, _),
    !,
    format(string(Answer), "Yes. ~w is a ~w, and the recorded rule says that ~w receive ~w.", [Person, Category, Category, Benefit]),
    evidence([Fact], FactEvidence),
    RuleEvidence = _{id:rule, canonical:rule(is_a(Person, Category), receives(Person, Benefit)),
                     source:RuleText, source_type:RuleSource},
    append(FactEvidence, [RuleEvidence], Evidence),
    Response = _{status:answered, answer:Answer, evidence:Evidence,
                 trace:["The customer's category matches the rule condition.", "The rule derives the requested benefit."]}.
answer_goal(receives(Person, Benefit), yes_no_question, Response) :-
    format(string(Answer), "I cannot determine whether ~w receives ~w from the recorded facts and rules.", [Person, Benefit]),
    Response = _{status:insufficient_information, answer:Answer, evidence:[], trace:[]}.
answer_goal(latest_events, summary_question, Response) :-
    findall(Seq-Event, stored_event(_, Seq, _, _, fact, _, _, _), Pairs),
    keysort(Pairs, Sorted),
    reverse(Sorted, Descending),
    take(5, Descending, Recent),
    pairs_events(Recent, Selected),
    !,
    (   Selected = []
    ->  Answer = "No conversation facts have been recorded."
    ;   maplist(event_source, Selected, Lines),
        atomic_list_concat(Lines, ' ', Answer)
    ),
    evidence(Selected, Evidence),
    Response = _{status:answered, answer:Answer, evidence:Evidence,
                 trace:["The summary uses the latest recorded factual events."]}.

latest_employment(Person, Employer, Event) :-
    findall(Seq-(Value-Record),
            ( stored_event(Id, Seq, Time, Speaker, Type, Canonical, Source, Context),
              (Canonical = employment(Person, Value) ; Canonical = left(Person, _)),
              (Canonical = employment(_, _) -> true ; Value = none),
              Record = _{id:Id, sequence:Seq, time:Time, speaker:Speaker, type:Type,
                         canonical:Canonical, source:Source, context:Context}
            ),
            Pairs),
    keysort(Pairs, Sorted),
    last(Sorted, _-(Employer-Event)),
    Employer \= none.

ranked_event(Canonical, Event, Rank) :-
    findall(Seq-Record,
            ( stored_event(Id, Seq, Time, Speaker, Type, Canonical, Source, Context),
              Record = _{id:Id, sequence:Seq, time:Time, speaker:Speaker, type:Type,
                         canonical:Canonical, source:Source, context:Context}
            ),
            Pairs),
    keysort(Pairs, Sorted),
    reverse(Sorted, [_-Event|_]),
    Rank = [exact_entity_match(1), exact_predicate_match(1), recency(Event.sequence)].

find_event(Canonical, Event) :-
    stored_event(Id, Seq, Time, Speaker, Type, Canonical, Source, Context),
    Event = _{id:Id, sequence:Seq, time:Time, speaker:Speaker, type:Type,
              canonical:Canonical, source:Source, context:Context},
    !.

evidence(Records, Evidence) :-
    maplist(event_evidence, Records, Evidence).

event_evidence(Event, _{id:Event.id, canonical:Event.canonical, source:Event.source,
                        sequence:Event.sequence, context:Event.context}).

event_source(Event, Event.source).

trace(Lines, Trace) :-
    maplist(string_string, Lines, Trace).

string_string(Value, String) :-
    (string(Value) -> String = Value ; term_string(Value, String)).

take(0, _, []) :- !.
take(_, [], []) :- !.
take(N, [Head|Tail], [Head|Rest]) :-
    Next is N - 1,
    take(Next, Tail, Rest).

pairs_events([], []).
pairs_events([_-Event|Tail], [Event|Events]) :-
    pairs_events(Tail, Events).
