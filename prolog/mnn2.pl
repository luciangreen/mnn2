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
:- use_module(library(date)).

:- dynamic stored_event/8.
:- dynamic stored_rule/5.
:- dynamic stored_relation/3.
:- dynamic event_counter/1.

event_counter(0).

reset :-
    retractall(stored_event(_, _, _, _, _, _, _, _)),
    retractall(stored_rule(_, _, _, _, _)),
    retractall(stored_relation(_, _, _)),
    retractall(event_counter(_)),
    assertz(event_counter(0)).

ingest(Text, Result) :-
    ingest(Text, user, Result).

ingest(Text, Speaker, Result) :-
    text_string(Text, Source),
    next_event_id(Id),
    (   parse_correction(Source, Canonical, SupersededId)
    ->  Type = correction
    ;   parse_statement(Source, Type, Canonical)
    ->  SupersededId = none
    ;   Type = utterance,
        Canonical = unparsed,
        SupersededId = none
    ),
    get_time(Now),
    stamp_date_time(Now, DateTime, 'UTC'),
    format_time(string(Time), '%FT%T%z', DateTime),
    assertz(stored_event(Id, Id, Time, Speaker, Type, Canonical, Source, conversation)),
    (   SupersededId \= none
    ->  assertz(stored_relation(supersedes, Id, SupersededId))
    ;   true
    ),
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

parse_correction(Source, employment(Person, NewEmployer), OldId) :-
    capture(Source, '^\\s*(?:actually[, ]+)?(.+?)\\s+(?:moved\\s+to|joined)\\s+(.+?),\\s+not\\s+(.+?)\\s*[.!?]?\\s*$', [PersonText, NewEmployerText, OldEmployerText]),
    entity_atom(NewEmployerText, NewEmployer),
    entity_atom(OldEmployerText, OldEmployer),
    resolve_correction_person(PersonText, OldEmployer, Person, OldEvent),
    get_dict(id, OldEvent, OldId),
    !.

resolve_correction_person(PersonText, OldEmployer, Person, Event) :-
    entity_atom(PersonText, Candidate),
    (   memberchk(Candidate, [she, he, they, it])
    ->  latest_employment_subject(Person, CurrentEmployer, Event),
        correction_employer_matches(CurrentEmployer, OldEmployer)
    ;   Person = Candidate,
        latest_employment(Person, CurrentEmployer, Event),
        correction_employer_matches(CurrentEmployer, OldEmployer)
    ).

latest_employment_subject(Person, Employer, Event) :-
    findall(Seq-(Entity-Value-Record),
            ( stored_event(Id, Seq, Time, Speaker, Type, Canonical, Source, Context),
              (Canonical = employment(Entity, Value) ; Canonical = left(Entity, _)),
              (Canonical = employment(_, _) -> true ; Value = none),
              event_record(Id, Seq, Time, Speaker, Type, Canonical, Source, Context, Record)
            ),
            Pairs),
    keysort(Pairs, Sorted),
    last(Sorted, _-(Person-Employer-Event)),
    Employer \= none.

correction_employer_matches(CurrentEmployer, OldEmployer) :-
    (   CurrentEmployer == OldEmployer
    ->  true
    ;   atom_concat(OldEmployer, '_', Prefix),
        atom_concat(Prefix, _, CurrentEmployer)
    ).

capture(Text, Pattern, Captures) :-
    re_matchsub(Pattern, Text, Match, [capture_type(string), caseless(true)]),
    dict_pairs(Match, _, [_-_|Pairs]),
    maplist(pair_value, Pairs, Captures).

pair_value(_-Value, Value).

entity_atom(Text, Atom) :-
    string_lower(Text, Lower),
    normalize_space(string(Trimmed), Lower),
    re_replace('^[[:space:]]*(the|a|an)[[:space:]]+'/i, '', Trimmed, WithoutArticle),
    re_replace('[.!?,;:]+[[:space:]]*$', '', WithoutArticle, Clean),
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
    findall(Event,
            ( stored_event(Id, Seq, Time, Speaker, Type, Canonical, Source, Context),
              event_record(Id, Seq, Time, Speaker, Type, Canonical, Source, Context, Record),
              term_string(Canonical, CanonicalText),
              put_dict(canonical, Record, CanonicalText, Event)
            ),
            Events).

event_record(Id, Seq, Time, Speaker, Type, Canonical, Source, Context, Event) :-
    findall(RelationText,
            ( stored_relation(Relation, Id, OtherId),
              RelationTerm =.. [Relation, Id, OtherId],
              term_string(RelationTerm, RelationText)
            ),
            Relationships),
    Event = _{id:Id, sequence:Seq, time:Time, speaker:Speaker, type:Type,
              canonical:Canonical, source:Source, context:Context,
              relationships:Relationships}.

rules(Rules) :-
    findall(_{id:Id, condition:Condition, conclusion:Conclusion,
              source:Source, text:Text},
            ( stored_rule(Id, ConditionTerm, ConclusionTerm, Source, Text),
              term_string(ConditionTerm, Condition),
              term_string(ConclusionTerm, Conclusion)
            ),
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
question_goal(Text, location_of_owned(Person, Object), location_question) :-
    capture(Text, '^\\s*where\\s+is\\s+(.+?)\\s*''s\\s+(.+?)\\s*\\??\\s*$', [PersonText, ObjectText]),
    !,
    entity_atom(PersonText, Person),
    entity_atom(ObjectText, Object).
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
    re_replace("'s[[:space:]]+.*$", '', Text, OwnerText),
    entity_atom(OwnerText, Owner).

answer_goal(color_of_owned(Person), colour_question, Response) :-
    ranked_event(owns(Person, Object), Ownership, _),
    ranked_event(color(Object, Color), ColourEvent, _),
    !,
    maplist(display_term, [Person, Object, Color], [PersonText, ObjectText, ColorText]),
    format(string(Answer), "~w's ~w is ~w.", [PersonText, ObjectText, ColorText]),
    evidence([Ownership, ColourEvent], Evidence),
    trace(["The selected owner has the object.", "The object has the recorded colour.", Answer], Trace),
    Response = _{status:answered, answer:Answer, evidence:Evidence, trace:Trace}.
answer_goal(color_of_owned(Person), colour_question, Response) :-
    find_event(owns(Person, Object), Ownership),
    !,
    maplist(display_term, [Person, Object], [PersonText, ObjectText]),
    format(string(Answer), "I know ~w owns ~w, but I do not have a recorded colour for it.", [PersonText, ObjectText]),
    evidence([Ownership], Evidence),
    Response = _{status:insufficient_information, answer:Answer, evidence:Evidence,
                 trace:["The ownership fact was found; no colour fact for that object was found."]}.
answer_goal(color_of_owned(Person), colour_question, Response) :-
    display_term(Person, PersonText),
    format(string(Answer), "I do not have enough information to identify the colour of ~w's object.", [PersonText]),
    Response = _{status:insufficient_information, answer:Answer, evidence:[], trace:[]}.
answer_goal(current_employer(Person), employment_question, Response) :-
    latest_employment(Person, Employer, Event),
    !,
    maplist(display_term, [Person, Employer], [PersonText, EmployerText]),
    format(string(Answer), "~w currently works at ~w.", [PersonText, EmployerText]),
    employment_evidence_trace(Event, Evidence, Trace),
    Response = _{status:answered, answer:Answer, evidence:Evidence, trace:Trace}.
answer_goal(current_employer(Person), employment_question, Response) :-
    find_event(left(Person, Employer), Event),
    !,
    maplist(display_term, [Person, Employer], [PersonText, EmployerText]),
    format(string(Answer), "The latest recorded employment event says ~w left ~w; no later workplace is recorded.", [PersonText, EmployerText]),
    evidence([Event], Evidence),
    Response = _{status:insufficient_information, answer:Answer, evidence:Evidence,
                 trace:["A departure was found, with no later employment event."]}.
answer_goal(current_employer(Person), employment_question, Response) :-
    display_term(Person, PersonText),
    format(string(Answer), "I do not have a recorded workplace for ~w.", [PersonText]),
    Response = _{status:insufficient_information, answer:Answer, evidence:[], trace:[]}.
answer_goal(receives(Person, Benefit), yes_no_question, Response) :-
    stored_rule(_, is_a(Person, Category), receives(Person, Benefit), RuleSource, RuleText),
    ranked_event(is_a(Person, Category), Fact, _),
    !,
    maplist(display_term, [Person, Category, Benefit], [PersonText, CategoryText, BenefitText]),
    format(string(Answer), "Yes. ~w is a ~w, and the recorded rule says that ~w receive ~w.", [PersonText, CategoryText, CategoryText, BenefitText]),
    evidence([Fact], FactEvidence),
    term_string(rule(is_a(Person, Category), receives(Person, Benefit)), RuleCanonical),
    RuleEvidence = _{id:rule, canonical:RuleCanonical,
                     source:RuleText, source_type:RuleSource},
    append(FactEvidence, [RuleEvidence], Evidence),
    Response = _{status:answered, answer:Answer, evidence:Evidence,
                 trace:["The customer's category matches the rule condition.", "The rule derives the requested benefit."]}.
answer_goal(receives(Person, Benefit), yes_no_question, Response) :-
    maplist(display_term, [Person, Benefit], [PersonText, BenefitText]),
    format(string(Answer), "I cannot determine whether ~w receives ~w from the recorded facts and rules.", [PersonText, BenefitText]),
    Response = _{status:insufficient_information, answer:Answer, evidence:[], trace:[]}.
answer_goal(location_of_owned(Person, Object), location_question, Response) :-
    ranked_event(owns(Person, Object), Ownership, _),
    location_chain(Object, [Object], Locations, LocationEvents),
    !,
    maplist(display_term, [Person, Object], [PersonText, ObjectText]),
    location_answer(PersonText, ObjectText, Locations, Answer),
    evidence([Ownership|LocationEvents], Evidence),
    maplist(event_source, [Ownership|LocationEvents], SourceLines),
    append(SourceLines, ["The location facts form a linked path from the owned object."], Trace),
    Response = _{status:answered, answer:Answer, evidence:Evidence, trace:Trace}.
answer_goal(location_of_owned(Person, Object), location_question, Response) :-
    find_event(owns(Person, Object), Ownership),
    !,
    maplist(display_term, [Person, Object], [PersonText, ObjectText]),
    format(string(Answer), "I know ~w owns ~w, but I do not have a recorded location for it.", [PersonText, ObjectText]),
    evidence([Ownership], Evidence),
    Response = _{status:insufficient_information, answer:Answer, evidence:Evidence,
                 trace:["The ownership fact was found; no location fact for that object was found."]}.
answer_goal(location_of_owned(Person, _Object), location_question, Response) :-
    display_term(Person, PersonText),
    format(string(Answer), "I do not have enough information to identify the location of ~w's object.", [PersonText]),
    Response = _{status:insufficient_information, answer:Answer, evidence:[], trace:[]}.
answer_goal(latest_events, summary_question, Response) :-
    findall(Seq-Event,
            ( stored_event(Id, Seq, Time, Speaker, Type, Canonical, Source, Context),
              term_string(Canonical, CanonicalText),
              Event = _{id:Id, sequence:Seq, time:Time, speaker:Speaker, type:Type,
                        canonical:CanonicalText, source:Source, context:Context}
            ),
            Pairs),
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
              event_record(Id, Seq, Time, Speaker, Type, Canonical, Source, Context, Record)
            ),
            Pairs),
    keysort(Pairs, Sorted),
    last(Sorted, _-(Employer-Event)),
    Employer \= none.

ranked_event(Canonical, Event, Rank) :-
    findall(Seq-(Fact-Record),
            (             stored_event(Id, Seq, Time, Speaker, Type, Fact, Source, Context),
            event_record(Id, Seq, Time, Speaker, Type, Fact, Source, Context, Record)
            ),
            Pairs),
    include(matches_canonical(Canonical), Pairs, Matching),
    keysort(Matching, Sorted),
    reverse(Sorted, [_-(SelectedCanonical-Event0)|_]),
    Canonical = SelectedCanonical,
    Rank = [exact_entity_match(1), exact_predicate_match(1), recency(Sequence)],
    get_dict(sequence, Event0, Sequence),
    put_dict(ranking, Event0, Rank, Event).

matches_canonical(Canonical, _-(Fact-_)) :-
    copy_term(Canonical, Pattern),
    Fact = Pattern.

find_event(Canonical, Event) :-
    stored_event(Id, Seq, Time, Speaker, Type, Canonical, Source, Context),
    event_record(Id, Seq, Time, Speaker, Type, Canonical, Source, Context, Event),
    !.

employment_evidence_trace(Event, Evidence, Trace) :-
    get_dict(id, Event, EventId),
    (   stored_relation(supersedes, EventId, PreviousId),
        find_event_by_id(PreviousId, PreviousEvent)
    ->  evidence([PreviousEvent, Event], Evidence),
        format(string(TraceLine), "The latest workplace statement corrects the earlier statement: ~w", [Event.source]),
        Trace = [PreviousEvent.source, TraceLine]
    ;   evidence([Event], Evidence),
        Trace = ["Employment events are ordered by insertion sequence.", Event.source]
    ).

find_event_by_id(Id, Event) :-
    stored_event(Id, Seq, Time, Speaker, Type, Canonical, Source, Context),
    event_record(Id, Seq, Time, Speaker, Type, Canonical, Source, Context, Event).

location_chain(Object, Seen, [Place|FurtherPlaces], [Event|FurtherEvents]) :-
    ranked_event(location(Object, Place), Event, _),
    \+ memberchk(Place, Seen),
    (   location_chain(Place, [Place|Seen], FurtherPlaces, FurtherEvents)
    ->  true
    ;   FurtherPlaces = [],
        FurtherEvents = []
    ).

location_answer(PersonText, ObjectText, [Place|Places], Answer) :-
    display_term(Place, PlaceText),
    format(string(Subject), "~w's ~w", [PersonText, ObjectText]),
    (   Places = []
    ->  format(string(Answer), "~w is in ~w.", [Subject, PlaceText])
    ;   maplist(display_term, Places, PlaceTexts),
        maplist(location_clause, PlaceTexts, Clauses),
        atomic_list_concat(Clauses, ', which is ', Suffix),
        format(string(Answer), "~w is in ~w, which is ~w.", [Subject, PlaceText, Suffix])
    ).

location_clause(Place, Clause) :-
    format(string(Clause), "in ~w", [Place]).

evidence(Records, Evidence) :-
    maplist(event_evidence, Records, Evidence).

event_evidence(Event, _{id:Event.id, canonical:CanonicalText, source:Event.source,
                        sequence:Event.sequence, context:Event.context,
                        ranking:RankingText}) :-
    term_string(Event.canonical, CanonicalText),
    (   get_dict(ranking, Event, Ranking)
    ->  maplist(term_string, Ranking, RankingText)
    ;   RankingText = []
    ).

event_source(Event, Event.source).

display_term(Term, Display) :-
    (   atom(Term)
    ->  atomic_list_concat(Parts, '_', Term),
        atomic_list_concat(Parts, ' ', Display)
    ;   term_string(Term, Display)
    ).

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
