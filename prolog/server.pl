:- module(mnn2_server, [start/1]).

:- use_module(mnn2).
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).
:- use_module(library(http/http_parameters)).

:- http_handler(root(.), home, []).
:- http_handler(root(assets/Path), asset(Path), [prefix]).
:- http_handler(root(api/message), message, [method(post)]).
:- http_handler(root(api/state), state, []).
:- http_handler(root(api/reset), clear, [method(post)]).
:- http_handler(root(api/export), export, []).

start(Port) :-
    http_server(http_dispatch, [port(Port)]).

home(Request) :-
    web_file('index.html', File),
    http_reply_file(File, [], Request).

asset(Path, Request) :-
    memberchk(Path, ['app.js', 'style.css']),
    web_file(Path, File),
    http_reply_file(File, [], Request).

web_file(Name, File) :-
    source_file(mnn2_server:start(_), ServerFile),
    file_directory_name(ServerFile, PrologDir),
    directory_file_path(PrologDir, '..', RootDir),
    directory_file_path(RootDir, 'web', WebDir),
    directory_file_path(WebDir, Name, File).

message(Request) :-
    http_read_json_dict(Request, Payload),
    (   get_dict(text, Payload, Text),
        string(Text),
        string_length(Text, Length),
        Length > 0,
        Length =< 10000
    ->  mnn2:respond(Text, Response),
        reply_json_dict(Response)
    ;   throw(http_error(bad_request, 'text must contain 1 to 10000 characters'))
    ).

state(_Request) :-
    mnn2:events(Events),
    mnn2:rules(Rules),
    reply_json_dict(_{events:Events, rules:Rules}).

clear(_Request) :-
    mnn2:reset,
    reply_json_dict(_{status:cleared}).

export(_Request) :-
    mnn2:export_knowledge(Knowledge),
    reply_json_dict(Knowledge).

:- initialization(main, main).

main :-
    current_prolog_flag(argv, Arguments),
    (   Arguments = [PortAtom|_],
        atom_number(PortAtom, Port)
    ->  true
    ;   Port = 8080
    ),
    start(Port).
