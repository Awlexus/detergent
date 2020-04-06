%%%-------------------------------------------------------------------
%%% Created : 29 Nov 2006 by Torbjorn Tornkvist <tobbe@tornkvist.org>
%%% Author  : Willem de Jong (w.a.de.jong@gmail.com).
%%% Desc.   : Common SOAP code.
%%%-------------------------------------------------------------------

%%% modified (WdJ, May 2007): deal with imports in the WSDL.
%%% modified (WdJ, August 2007): the WSDL can contain more than 1 schema

-module(detergent).

-export([initModel/1, initModel/2, initModel/3, initModel/5,
     initModelFile/1,
     config_file_xsd/0,
     call/3, call/4, call/5, call/6, call/7,
     call_attach/4, call_attach/5, call_attach/6, call_attach/8,
     write_hrl/2, write_hrl/3,
     findHeader/2,
     parseMessage/2,
     makeFault/2,
     is_wsdl/1, wsdl_model/1, wsdl_op_service/1,
     wsdl_op_port/1, wsdl_op_operation/1,
     wsdl_op_binding/1, wsdl_op_address/1,
     wsdl_op_action/1, wsdl_operations/1,
     get_operation/2
    ]).


%%% For testing...
-export([qtest/0]).


-include_lib("detergent.hrl").
-include_lib("xmerl/include/xmerl.hrl").

-define(HTTP_REQ_TIMEOUT, 20000).

%%-define(dbg(X,Y),
%%        error_logger:info_msg("*dbg ~p(~p): " X,
%%                              [?MODULE, ?LINE | Y])).
-define(dbg(X,Y), true).


-record(soap_config, {atts, xsd_path,  user_module, wsdl_file, add_files}).
-record(xsd_file, {atts, name, prefix, import_specs}).
-record(import_specs, {atts, namespace, prefix, location}).



%%%
%%% Writes the header file (record definitions) for a WSDL file
%%%
write_hrl(WsdlURL, Output) when is_list(WsdlURL) ->
    write_hrl(initModel(WsdlURL), Output);
write_hrl(#wsdl{model = Model}, Output) when is_list(Output) ->
    erlsom:write_hrl(Model, Output).

write_hrl(WsdlURL, Output, Prefix) when is_list(WsdlURL),is_list(Prefix) ->
    write_hrl(initModel(WsdlURL, Prefix), Output).



%%% For testing only...
qtest() ->
  call("http://www.webservicex.net/WeatherForecast.asmx?WSDL",
        "GetWeatherByPlaceName",
        ["Boston"]).

%%% --------------------------------------------------------------------
%%% Access functions
%%% --------------------------------------------------------------------
is_wsdl(Wsdl) when is_record(Wsdl,wsdl) -> true;
is_wsdl(_)                           -> false.

wsdl_operations(#wsdl{operations = Ops}) -> Ops.

wsdl_model(#wsdl{model = Model}) -> Model.

wsdl_op_service(#operation{service = Service}) -> Service.

wsdl_op_port(#operation{port = Port}) -> Port.

wsdl_op_operation(#operation{operation = Op}) -> Op.

wsdl_op_binding(#operation{binding = Binding}) -> Binding.

wsdl_op_address(#operation{address = Address}) -> Address.

wsdl_op_action(#operation{action = Action}) -> Action.


%%% --------------------------------------------------------------------
%%% For Quick deployment
%%% --------------------------------------------------------------------
call(Wsdl, Operation, ListOfData) ->
    call(Wsdl, Operation, ListOfData, #call_opts{}).

call(WsdlURL, Operation, ListOfData, #call_opts{prefix=Prefix}=CallOpts)
    when is_list(WsdlURL) ->
    Wsdl = initModel(WsdlURL, Prefix),
    call(Wsdl, Operation, ListOfData, CallOpts);
call(Wsdl, Operation, ListOfData, #call_opts{prefix=Prefix}=CallOpts) when is_record(Wsdl, wsdl) ->
    case get_operation(Wsdl#wsdl.operations, Operation) of
    {ok, Op} ->
        Msg = mk_msg(Prefix, Operation, ListOfData),
        call(Wsdl, Operation, Op#operation.port,
                 Op#operation.service, [], Msg, CallOpts);
    Else ->
        Else
    end;
%%% --------------------------------------------------------------------
%%% Takes the actual records for the Header and Body message.
%%% --------------------------------------------------------------------
call(Wsdl, Operation, Header, Msg) ->
    call(Wsdl, Operation, Header, Msg, #call_opts{}).



call(WsdlURL, Operation, Header, Msg, #call_opts{prefix=Prefix}=CallOpts)
    when is_list(WsdlURL) ->
    Wsdl = initModel(WsdlURL, Prefix),
    call(Wsdl, Operation, Header, Msg, CallOpts);
call(Wsdl, Operation, Header, Msg, CallOpts) when is_record(Wsdl, wsdl) ->
    case get_operation(Wsdl#wsdl.operations, Operation) of
    {ok, Op} ->
        call(Wsdl, Operation, Op#operation.port, Op#operation.service,
         Header, Msg, CallOpts);
    Else ->
        Else
    end.


mk_msg(Prefix, Operation, ListOfData) ->
    list_to_tuple([list_to_atom(Prefix++":"++Operation), % record name
           []                                    % anyAttribs
           | ListOfData]).                       % rest of record data

get_operation([#operation{operation = X} = Op|_], X) ->
    {ok, Op};
get_operation([_|T], Op)                             ->
    get_operation(T, Op);
get_operation([], _Op)                               ->
    {error, "operation not found"}.


%%% --------------------------------------------------------------------
%%% Make a SOAP request (no attachments)
%%% --------------------------------------------------------------------
call(Wsdl, Operation, Port, Service, Headers, Message) ->
    call(Wsdl, Operation, Port, Service, Headers, Message, #call_opts{}).

call(Wsdl, Operation, Port, Service, Headers, Message, CallOpts) ->
    call_attach(Wsdl, Operation, Port, Service, Headers, Message, [], CallOpts).


%%% --------------------------------------------------------------------
%%% For Quick deployment (with attachments)
%%% --------------------------------------------------------------------
call_attach(Wsdl, Operation, ListOfData, Attachments)  ->
    call_attach(Wsdl, Operation, ListOfData, Attachments, #call_opts{}).

call_attach(WsdlURL, Operation, ListOfData, Attachments, #call_opts{prefix=Prefix}=CallOpts)
  when is_list(WsdlURL) ->
    Wsdl = initModel(WsdlURL, Prefix),
    call_attach(Wsdl, Operation, ListOfData, Attachments, CallOpts);
call_attach(Wsdl, Operation, ListOfData, Attachments, #call_opts{prefix=Prefix}=CallOpts)
  when is_record(Wsdl, wsdl) ->
    case get_operation(Wsdl#wsdl.operations, Operation) of
    {ok, Op} ->
        Msg = mk_msg(Prefix, Operation, ListOfData),
        call_attach(Wsdl, Operation, Op#operation.port,
                        Op#operation.service, [], Msg, Attachments, CallOpts);
    Else ->
        Else
    end.

%%% --------------------------------------------------------------------
%%% Takes the actual records for the Header and Body message
%%% (with attachments)
%%% --------------------------------------------------------------------
call_attach(WsdlURL, Operation, Header, Msg, Attachments, #call_opts{prefix=Prefix}=CallOpts)
  when is_list(WsdlURL) ->
    Wsdl = initModel(WsdlURL, Prefix),
    call_attach(Wsdl, Operation, Header, Msg, Attachments, CallOpts);
call_attach(Wsdl, Operation, Header, Msg, Attachments, CallOpts)
  when is_record(Wsdl, wsdl) ->
    case get_operation(Wsdl#wsdl.operations, Operation) of
    {ok, Op} ->
        call_attach(Wsdl, Operation, Op#operation.port,
                        Op#operation.service,
         Header, Msg, Attachments, CallOpts);
    Else ->
        Else
    end.


%%% --------------------------------------------------------------------
%%% Make a SOAP request (with attachments)
%%% --------------------------------------------------------------------
call_attach(#wsdl{operations = Operations, model = Model},
            Operation, Port, Service, Headers, Message, Attachments,
            #call_opts{url=Url, http_headers=HttpHeaders,
                       http_options=HttpOptions,
                       http_client_options=HttpClientOptions,
                       request_logger=RequestLogger,
                       response_logger=ResponseLogger}) ->
    %% find the operation
    case findOperation(Operation, Port, Service, Operations) of
    #operation{address = Address, action = SoapAction} ->
        %% Add the Soap envelope
        Envelope = mk_envelope(Message, Headers),
        %% Encode the message
        case erlsom:write(Envelope, Model, [{output, chardata}]) of
        {ok, XmlMessage} ->
            RequestLogger(XmlMessage),
            {ContentType, Request} =
                        make_request_body(XmlMessage, Attachments),
                    ?dbg("+++ Request = ~p~n", [Request]),
            URL = case Url of
                undefined ->
                    Address;
                _ ->
                   Url
            end,
            HttpRes = http_request(URL, SoapAction, Request,
                                           HttpOptions,
                                           HttpClientOptions, HttpHeaders,
                                           ContentType),
                    ?dbg("+++ HttpRes = ~p~n", [HttpRes]),
            case HttpRes of
            {ok, _Code, _ReturnHeaders, {Body, ResponseAttachments}} ->
                ResponseLogger(Body),
                ParsedMessage = parseMessage(Body, Model),
                appendAttachments(ParsedMessage, ResponseAttachments);
            {ok, _Code, _ReturnHeaders, Body} ->
                ResponseLogger(Body),
                ParsedMessage = parseMessage(Body, Model),
                appendAttachments(ParsedMessage, []);
            Error ->
                %% in case of HTTP error: return
                            %% {error, description}
                Error
            end;
        {error, EncodingError} ->
            {error, {encoding_error, EncodingError}}
        end;
    false ->
        {error, {unknown_operation, Operation}}
    end.

appendAttachments(Tuple, Attachments) ->
  erlang:insert_element(tuple_size(Tuple) + 1, Tuple, Attachments).
%%%
%%% returns {ok, Header, Body} | {error, Error}
%%%
parseMessage(Message, #wsdl{model = Model}) ->
    parseMessage(Message, Model);
%%
parseMessage(Message, Model) ->
    case erlsom:scan(Message, Model, [{output_encoding, utf8}]) of
    {ok, #'soap:Envelope'{'Body' = #'soap:Body'{choice = Body},
                  'Header' = undefined}, _} ->
        {ok, undefined, Body};
    {ok, #'soap:Envelope'{'Body' = #'soap:Body'{choice = Body},
                  'Header' = #'soap:Header'{choice = Header}}, _} ->
        {ok, Header, Body};
    {error, ErrorMessage} ->
        {error, {decoding, ErrorMessage}}
    end.


findOperation(_Operation, _Port, _Service, []) ->
    false;
findOperation(Operation, Port, Service,
              [Op = #operation{operation = Operation,
                               port = Port, service = Service} | _]) ->
    Op;
findOperation(Operation, Port, Service, [#operation{} | Tail]) ->
    findOperation(Operation, Port, Service, Tail).


mk_envelope(M, H) when is_tuple(M) -> mk_envelope([M], H);
mk_envelope(M, H) when is_tuple(H) -> mk_envelope(M, [H]);
%%
mk_envelope(Messages, []) when is_list(Messages) ->
    #'soap:Envelope'{'Body' =  #'soap:Body'{choice = Messages}};
mk_envelope(Messages, Headers) when is_list(Messages),is_list(Headers) ->
    #'soap:Envelope'{'Body'   =  #'soap:Body'{choice   = Messages},
             'Header' =  #'soap:Header'{choice = Headers}}.

%%% --------------------------------------------------------------------
%%% Parse a WSDL file and return a 'Model'
%%% --------------------------------------------------------------------
initModel(WsdlFile) ->
    initModel(WsdlFile, ?DEFAULT_PREFIX).

initModel(WsdlFile, Prefix) ->
    initModel(WsdlFile, Prefix, []).

initModel(WsdlFile, Prefix, HttpOptions) ->
    PrivDir = priv_dir(),
    initModel2(WsdlFile, HttpOptions, Prefix, PrivDir, undefined, undefined).

initModel(WsdlFile, Prefix, HttpOptions, Import, AddFiles) ->
    PrivDir = priv_dir(),
    initModel2(WsdlFile, HttpOptions, Prefix, PrivDir, Import, AddFiles).

initModelFile(ConfigFile) ->
    {ok, ConfigSchema} = erlsom:compile_xsd(config_file_xsd()),
    %% read (parse) the config file
    {ok, Config, _} = erlsom:scan_file(ConfigFile, ConfigSchema),
    #soap_config{xsd_path = XsdPath,
              wsdl_file = Wsdl,
              add_files = AddFiles} = Config,
    #xsd_file{name = WsdlFile, prefix = Prefix, import_specs = Import} = Wsdl,
    initModel2(WsdlFile, [], Prefix, XsdPath, Import, AddFiles).

priv_dir() ->
    case code:priv_dir(detergent) of
        {error, bad_name} ->
           filename:join([filename:dirname(code:which(detergent)),"..", "priv"]);
        A ->
            A
    end.

initModel2(WsdlFile, HttpOptions, Prefix, Path, Import, AddFiles) ->
    WsdlName = filename:join([Path, "wsdl.xsd"]),
    IncludeWsdl = {"http://schemas.xmlsoap.org/wsdl/", "wsdl", WsdlName},
    {ok, WsdlModel} = erlsom:compile_xsd_file(filename:join([Path, "soap.xsd"]),
                          [{prefix, "soap"},
                           {include_files, [IncludeWsdl]}]),
    %% add the xsd model (since xsd is also used in the wsdl)
    WsdlModel2 = erlsom:add_xsd_model(WsdlModel),
    IncludeDir = filename:dirname(WsdlFile),
    OneUpPath = case filename:basename(IncludeDir) of
      "esor" -> filename:dirname(IncludeDir); % Bad Hack, actually we'd need the absolute location
      "esor12" -> filename:dirname(IncludeDir); % Bad Hack, actually we'd need the absolute location
      _ -> IncludeDir
    end,
    Options = [{dir_list, [OneUpPath]} | makeOptions(Import)],
    Options2 = [{include_fun, fun(N, L, F, D) -> findFile(N, L, F, D, HttpOptions) end} | Options],
    %% parse Wsdl
    {Model, Operations} = parseWsdls([WsdlFile], HttpOptions, Prefix, WsdlModel2, Options2, {undefined, []}),
    %% TODO: add files as required
    %% now compile envelope.xsd, and add Model
    {ok, EnvelopeModel} = erlsom:compile_xsd_file(filename:join([Path, "envelope.xsd"]),
                          [{prefix, "soap"}]),
    SoapModel = erlsom:add_model(EnvelopeModel, Model),
    SoapModel2 = addModels(AddFiles, SoapModel),
    #wsdl{operations = Operations, model = SoapModel2}.


%%% --------------------------------------------------------------------
%%% Parse a list of WSDLs and import (recursively)
%%% Returns {Model, Operations}
%%% --------------------------------------------------------------------
parseWsdls([], _HttpOptions, _Prefix, _WsdlModel, _Options, Acc) ->
  Acc;
parseWsdls([WsdlFile | Tail], HttpOptions, Prefix, WsdlModel, Options, {AccModel, AccOperations}) ->
  {ok, WsdlFileContent} = get_url_file(rmsp(WsdlFile), HttpOptions),
  {ok, ParsedWsdl, _} = erlsom:scan(WsdlFileContent, WsdlModel),
  %% get the xsd elements from this model, and hand it over to erlsom_compile.
  Xsds = getXsdsFromWsdl(ParsedWsdl),
  %% Now we need to build a list: [{Namespace, Prefix, Xsd}, ...] for all the Xsds in the WSDL.
  %% This list is used when a schema inlcudes one of the other schemas. The AXIS java2wsdl
  %% generates wsdls that depend on this feature.
  ImportList = makeImportList(Xsds, []),
  %% Append ImportList to include_files in Options
  IncludeFiles = case lists:keyfind('include_files', 1, Options) of
                   {_, Files} -> Files;
                   _ -> []
                 end,
  Options2 = lists:keystore('include_files', 1, Options, {'include_files', ImportList++IncludeFiles}),
  Model2 = addSchemas(Xsds, AccModel, Prefix, Options2),
  Ports = getPorts(ParsedWsdl),
  Operations = getOperations(ParsedWsdl, Ports),
  Imports = getImports(ParsedWsdl),
  Acc2 = {Model2, Operations ++ AccOperations},
  %% process imports (recursively, so that imports in the imported files are
  %% processed as well).
  %% For the moment, the namespace is ignored on operations etc.
  %% this makes it a bit easier to deal with imported wsdl's.
  Acc3 = parseWsdls(Imports, HttpOptions, Prefix, WsdlModel, Options, Acc2),
  parseWsdls(Tail, HttpOptions, Prefix, WsdlModel, Options, Acc3).

%% resolve relative import URIs
%% s.a. https://github.com/willemdj/erlsom/blob/master/src/erlsom_lib.erl#L719 findFile/4
%% and https://github.com/willemdj/erlsom/blob/master/src/erlsom_lib.erl#L790 find_xsd/4

findFile(Namespace, Location, IncludeFiles, IncludeDirs, HttpOptions) ->
      %io:format("(1) IncludeFiles: ~p~n", [IncludeFiles]),
      %io:format("(2) Namespace: ~p~n", [Namespace]),
  case lists:keyfind(Namespace, 1, IncludeFiles) of
% given and known Namespace (xs:import and initModelFile/1)
    {_, Prefix, Loc} ->
      %io:format("(3a) Loc: ~p~n", [Loc]),
      {ok, FileContent} = get_url_file(Loc, HttpOptions),
      {FileContent, Prefix};
% missing/unknown Namespace, need to find Location (xs:include and initModel/1,2,3)
    _ ->
      ResolvedLocation = resolveRelativeLocation(Location, IncludeDirs),
      %io:format("(3b) ResolvedLocation: ~p~n", [ResolvedLocation]),
      %io:format("(3b) IncludeDirs: ~p~n", [IncludeDirs]),
      {ok, FileContent} = get_url_file(ResolvedLocation, HttpOptions),
      {FileContent, undefined}
  end.

resolveRelativeLocation("https://"++_ = URL, _BaseLocation) ->
    URL;
resolveRelativeLocation("http://"++_ = URL, _BaseLocation) ->
    URL;
resolveRelativeLocation("file://"++Fname, _BaseLocation) ->
    Fname;
%resolveRelativeLocation("/"++RelLocation, []) ->
%    RelLocation;
%resolveRelativeLocation(Location, []) ->
%    Location;
resolveRelativeLocation("/"++RelLocation = Location, [BaseLocation]) ->
  case http_uri:parse(BaseLocation) of
    {ok, {Scheme, _UserInfo, Host, Port, _Path, _Query}} ->
      atom_to_list(Scheme)++"://"++Host++":"++integer_to_list(Port)++Location;
    _ -> RelLocation
  end;
resolveRelativeLocation(Location, [BaseLocation]) ->
  case http_uri:parse(BaseLocation) of
    {ok, {Scheme, _UserInfo, Host, Port, Path, _Query}} ->
      atom_to_list(Scheme)++"://"++Host++":"++integer_to_list(Port)++Path++"/"++Location;
    _ -> filename:join([BaseLocation, Location])
  end.

%%% --------------------------------------------------------------------
%%% build a list: [{Namespace, Prefix, Xsd}, ...] for all the Xsds in the WSDL.
%%% This list is used when a schema inlcudes one of the other schemas. The AXIS java2wsdl
%%% generates wsdls that depend on this feature.
makeImportList([], Acc) ->
  Acc;
makeImportList([ Xsd | Tail], Acc) ->
  makeImportList(Tail, [{erlsom_lib:getTargetNamespaceFromXsd(Xsd),
                         undefined, Xsd} | Acc]).


%%% --------------------------------------------------------------------
%%% compile each of the schemas, and add it to the model.
%%% Returns Model
%%% (TODO: using the same prefix for all XSDS makes no sense)
%%% --------------------------------------------------------------------
addSchemas([], AccModel, _Prefix, _Options) ->
  AccModel;
addSchemas([Xsd| Tail], AccModel, Prefix, Options) ->
  Model2 = case Xsd of
             undefined ->
               AccModel;
             _ ->
               {ok, Model} =
                 erlsom_compile:compile_parsed_xsd(Xsd,
                                                   [{prefix, Prefix} | Options]),
               case AccModel of
                 undefined -> Model;
                 _ -> erlsom:add_model(AccModel, Model)
               end
           end,
  addSchemas(Tail, Model2, Prefix, Options).

%%% --------------------------------------------------------------------
%%% Get a file from an URL spec.
%%% --------------------------------------------------------------------
get_url_file({binary, Bin}, _) ->
    {ok, Bin};

get_url_file(URL, HttpOptions) ->
    SchemaFun = fun(SchemeStr) ->
        case SchemeStr of
            "http" -> valid;
            "https" -> valid;
            _ -> {error, "Not supported"}
        end
    end,
    case http_uri:parse(URL, [{schema_validation_fun, SchemaFun}]) of
        {ok, _} -> get_remote_file(URL, HttpOptions);
        _Other -> get_local_file(URL)
    end.

get_remote_file(URL, HttpOptions) ->
    case httpc:request(get, {URL, []}, HttpOptions, []) of
    {ok,{{_HTTP,200,_OK}, _Headers, Body}} ->
        {ok, Body};
    {ok,{{_HTTP,RC,Emsg}, _Headers, _Body}} ->
        error_logger:error_msg("~p: http-request got: ~p~n", [?MODULE, {RC, Emsg}]),
        {error, "failed to retrieve: "++URL};
    {error, Reason} ->
        error_logger:error_msg("~p: http-request failed: ~p~n", [?MODULE, Reason]),
        {error, "failed to retrieve: "++URL}
    end.

get_local_file(Fname) ->
    file:read_file(Fname).

%%% --------------------------------------------------------------------
%%% Make a HTTP Request
%%% --------------------------------------------------------------------
http_request(URL, SoapAction, Request, HttpOptions, Options, Headers, ContentType) ->
    % ibrowse disabled, because unknown how it supports the binary formats:
    case hackney of %% code:ensure_loaded(ibrowse) of
    {module, ibrowse} ->
        %% If ibrowse exist in the path then let's use it...
        ibrowse_request(URL, SoapAction, Request, HttpOptions, Options, Headers, ContentType);
    hackney ->
        %% So far hackney is the best way we could think of in order to support multipart responses
        hackney_request(URL, SoapAction, Request, HttpOptions, Options, Headers, ContentType);
    _ ->
        %% ...otherwise, let's use the OTP http client.
        inets_request(URL, SoapAction, Request, HttpOptions, Options, Headers, ContentType)
    end.

hackney_request(URL, SoapAction, Request, HttpOptions, _Options, Headers, ContentType) ->
    NewHeaders = [{"Content-Type", ContentType} | [{"SOAPAction", SoapAction} | Headers]],
    BinaryHeaders = binary_headers(NewHeaders, []),
    {timeout, Timeout} = proplists:lookup(timeout, HttpOptions),
    {ssl, SSLOptions} = proplists:lookup(ssl, HttpOptions),
    NewHttpOptions = [{with_body, true}, {ssl_options, SSLOptions}, {recv_timeout, Timeout}, {checkout_timeout, Timeout}] ++ HttpOptions,
    case hackney:request(post, URL, BinaryHeaders, Request, NewHttpOptions) of
        {ok, 200, ResponseHeaders, Body} ->
            {ok, 200, ResponseHeaders, parse_hackney_response(ResponseHeaders, Body)};
        Other ->
            Other
    end.

parse_hackney_response(ResponseHeaders, Body) ->
    case hackney_headers:parse(<<"Content-Type">>, ResponseHeaders) of
        {<<"multipart">>, _, [_, {<<"boundary">>, Boundary} | _]} ->
            Parser = hackney_multipart:parser(Boundary),
            parse_multipart(Parser(Body));
        _ ->
            binary:bin_to_list(Body)
    end.

parse_multipart(Init) ->
    {headers, _Headers, Parser1} = Init,
    {body, Body, Parser2} = Parser1(),
    {end_of_part, Parser3} = Parser2(),
    % Return attachments directly, if there are some
    case parse_attachments(Parser3, []) of
      [] ->
        binary:bin_to_list(Body);

      Attachments when is_list(Attachments) ->
        {inject_attachments(Body), Attachments}
    end.

parse_attachments(Parser0, Acc) ->
    case Parser0() of
        {headers, Headers, Parser1} ->
            {_, ContentId} = proplists:lookup(<<"Content-Id">>, Headers),
            NewContentId = binary:part(ContentId, {1, byte_size(ContentId) - 2}),
            {body, Content, Parser2} = Parser1(),
            {end_of_part, Parser3} = Parser2(),
            parse_attachments(Parser3, [{NewContentId, Content} | Acc]);
        eof ->
            Acc
    end.

inject_attachments(#xmlElement{name='xop:Include', parents=Parents, attributes=Attributes, pos=Pos}) ->
  Href = lists:keyfind(href, 2, Attributes),
  {xmlText, Parents, Pos, [], Href#xmlAttribute.value, text};
inject_attachments(#xmlElement{content=Content} = Elem) ->
  Elem#xmlElement{content=lists:map(fun inject_attachments/1, Content)};
inject_attachments(Tuple) when is_tuple(Tuple) ->
  Tuple;
inject_attachments(Body) ->
  {Xml, _} = xmerl_scan:string(erlang:binary_to_list(Body)),
  lists:flatten(xmerl:export([inject_attachments(Xml)], xmerl_xml)).

binary_headers([], Acc) -> Acc;
binary_headers([{_, _} = Header | Rest], Acc) -> binary_headers(Rest, [do_binary_header(Header) | Acc]).
do_binary_header({K, V}) when is_list(K) -> do_binary_header({binary:list_to_bin(K), V});
do_binary_header({K, V}) when is_list(V) -> do_binary_header({K, binary:list_to_bin(V)});
do_binary_header(Header) -> Header.

inets_request(URL, SoapAction, Request, HttpOptions, Options, Headers, ContentType) ->
    % To pass an iolist we need to wrap it in a fun.
    RequestFun = {fun(Acc) -> Acc end, {ok, Request, eof}},
    ContentLength = erlang:iolist_size(Request),
    Headers2 = [{"content-length", integer_to_list(ContentLength)} | Headers],
    NewHeaders = [{"SOAPAction", SoapAction}|Headers2],
    NewOptions = [{cookies, enabled}|Options],
    httpc:set_options(NewOptions),
    NewHttpOptions = case lists:keymember(timeout, 1, HttpOptions) of
      false -> [{timeout,?HTTP_REQ_TIMEOUT}|HttpOptions];
      true -> HttpOptions
    end,
    case httpc:request(post,
                      {URL,NewHeaders,
                       ContentType,
                       RequestFun},
                      NewHttpOptions,
                      [{sync, true}, {full_result, true}, {body_format, binary}]) of
        {ok,{{_HTTP,200,_OK},ResponseHeaders,ResponseBody}} ->
            {ok, 200, ResponseHeaders, ResponseBody};
        {ok,{{_HTTP,500,_Descr},ResponseHeaders,ResponseBody}} ->
            {ok, 500, ResponseHeaders, ResponseBody};
        {ok,{{_HTTP,ErrorCode,_Descr},ResponseHeaders,ResponseBody}} ->
            {ok, ErrorCode, ResponseHeaders, ResponseBody};
        Other ->
            Other
    end.

ibrowse_request(URL, SoapAction, Request, [], Options, Headers, ContentType) ->
    case start_ibrowse() of
        ok ->
            FlatRequest = lists:flatten(Request),
            NewHeaders = [{"Content-Type", ContentType}, {"SOAPAction", SoapAction} | Headers],
            NewOptions = Options,
                         %%[{content_type, "text/xml; encoding=utf-8"} | Options],
            case ibrowse:send_req(URL, NewHeaders, post, FlatRequest, NewOptions) of
                {ok, Status, ResponseHeaders, ResponseBody} ->
                    {ok, list_to_integer(Status), ResponseHeaders, ResponseBody};
                {error, Reason} ->
                    {error, Reason}
            end;
        error ->
            {error, "could not start ibrowse"}
    end.

start_ibrowse() ->
    case ibrowse:start() of
    {ok, _} -> ok;
    {error, {already_started, _}} -> ok;
    _ -> error
    end.


rmsp(Str) -> string:strip(Str, left).


make_request_body(Content, []) ->
        {"text/xml; charset=utf-8", ["<?xml version=\"1.0\" encoding=\"utf-8\"?>", Content]};
make_request_body(Content, AttachedFiles) ->
        {"application/dime", detergent_dime:encode(lists:flatten(["<?xml version=\"1.0\" encoding=\"utf-8\"?>", Content]), AttachedFiles)}.


makeFault(FaultCode, FaultString) ->
  try
    "<SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\">"
     "<SOAP-ENV:Body>"
      "<SOAP-ENV:Fault>"
       "<faultcode>SOAP-ENV:" ++ FaultCode ++ "</faultcode>" ++
       "<faultstring>" ++ FaultString ++ "</faultstring>" ++
      "</SOAP-ENV:Fault>"
     "</SOAP-ENV:Body>"
    "</SOAP-ENV:Envelope>"
  catch
    _:_ ->
      "<SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\">"
       "<SOAP-ENV:Body>"
        "<SOAP-ENV:Fault>"
         "<faultcode>SOAP-ENV:Server</faultcode>"
         "<faultstring>Server error</faultstring>"
        "</SOAP-ENV:Fault>"
       "</SOAP-ENV:Body>"
      "</SOAP-ENV:Envelope>"
  end.

%% record http_header is not defined??
findHeader(Label, Headers) ->
    findHeader0(string:to_lower(Label), Headers).

findHeader0(_Label, []) ->
  undefined;
findHeader0(Label, [{_,_,Hdr,_,Val}|T]) ->
    case {Label, string:to_lower(Hdr)} of
    {X,X} -> Val;
    _     -> findHeader0(Label, T)
    end;
findHeader0(_Label, undefined) ->
  undefined.


makeOptions(undefined) ->
  [];
makeOptions(Import) ->
  [{include_files, lists:map(fun makeOption/1, Import)}].

%% -record(import_specs, {atts, namespace, prefix, location}).
makeOption(#import_specs{namespace = Ns, prefix = Pf, location = Lc}) ->
  {Ns, Pf, Lc}.


addModels(undefined, Model) ->
  Model;
addModels(Import, Model) ->
  lists:foldl(fun addModel/2, Model, Import).

%% -record(xsd_file, {atts, name, prefix, import_specs}).
addModel(undefined, Acc) ->
  Acc;
addModel(#xsd_file{name = XsdFile, prefix = Prefix, import_specs = Import}, Acc) ->
  Options = makeOptions(Import),
  {ok, Model2} = erlsom:add_xsd_file(XsdFile, [{prefix, Prefix} | Options], Acc),
  Model2.

%% returns [#port{}]
%% -record(port, {service, port, binding, address}).
getPorts(ParsedWsdl) ->
  Services = getTopLevelElements(ParsedWsdl, 'wsdl:tService'),
  getPortsFromServices(Services, []).

getPortsFromServices([], Acc) ->
  Acc;
getPortsFromServices([Service|Tail], Acc) ->
  getPortsFromServices(Tail, getPortsFromService(Service) ++ Acc).

getPortsFromService(#'wsdl:tService'{name = Name, port = Ports}) ->
  getPortsInfo(Ports, Name, []).

getPortsInfo([], _Name, Acc) ->
  Acc;

getPortsInfo([#'wsdl:tPort'{name = Name,
                            binding = Binding,
                            choice = [#'soap:tAddress'{location = URL}]} | Tail], ServiceName, Acc) ->
  getPortsInfo(Tail, ServiceName, [#port{service = ServiceName, port = Name, binding = Binding, address = URL}|Acc]);
%% non-soap bindings are ignored.
getPortsInfo([#'wsdl:tPort'{} | Tail], ServiceName, Acc) ->
  getPortsInfo(Tail, ServiceName, Acc).


getTopLevelElements(#'wsdl:tDefinitions'{choice = TLElements}, Type) ->
  getTopLevelElements(TLElements, Type, []).

getTopLevelElements([], _Type, Acc) ->
  Acc;
getTopLevelElements([#'wsdl:anyTopLevelOptionalElement'{choice = Tuple}| Tail], Type, Acc) ->
  case element(1, Tuple) of
    Type -> getTopLevelElements(Tail, Type, [Tuple|Acc]);
    _ -> getTopLevelElements(Tail, Type, Acc)
  end.

getImports(Definitions) ->
  Imports = getTopLevelElements(Definitions, 'wsdl:tImport'),
  lists:map(fun(Import) -> Import#'wsdl:tImport'.location end, Imports).

%% returns [#operation{}]
getOperations(ParsedWsdl, Ports) ->
  Bindings = getTopLevelElements(ParsedWsdl, 'wsdl:tBinding'),
  getOperationsFromBindings(Bindings, Ports, []).

getOperationsFromBindings([], _Ports, Acc) ->
  Acc;
getOperationsFromBindings([Binding|Tail], Ports, Acc) ->
  getOperationsFromBindings(Tail, Ports, getOperationsFromBinding(Binding, Ports) ++ Acc).

getOperationsFromBinding(#'wsdl:tBinding'{name = BindingName,
                                          type = BindingType,
                                          choice = _Choice,
                                          operation = Operations}, Ports) ->
  %% TODO: get soap info from Choice
  getOperationsFromOperations(Operations, BindingName, BindingType, Operations, Ports, []).

getOperationsFromOperations([], _BindingName, _BindingType, _Operations, _Ports, Acc) ->
  Acc;

getOperationsFromOperations([#'wsdl:tBindingOperation'{name = Name, choice = Choice} | Tail],
                            BindingName, BindingType, Operations, Ports, Acc) ->
  %% get SOAP action from Choice,
  case Choice of
    [#'soap:tOperation'{soapAction = Action}] ->
      %% lookup Binding in Ports, and create a combined result
      Ports2 = searchPorts(BindingName, Ports),
      %% for each port, make an operation record
      CombinedPorts = combinePorts(Ports2, Name, BindingName, Action),
      getOperationsFromOperations(Tail, BindingName, BindingType, Operations, Ports, CombinedPorts ++ Acc);
    _ ->
      getOperationsFromOperations(Tail, BindingName, BindingType, Operations, Ports, Acc)
  end.

combinePorts(Ports, Name, BindingName, Action) ->
  combinePorts(Ports, Name, BindingName, Action, []).

combinePorts([], _Name, _BindingName, _Action, Acc) ->
  Acc;
combinePorts([#port{service = Service, port = PortName, address = Address} | Tail],
             Name, BindingName, Action, Acc) ->
  combinePorts(Tail, Name, BindingName, Action,
               [#operation{service = Service, port = PortName, operation = Name,
                           binding = BindingName, address = Address, action = Action} | Acc]).

searchPorts(BindingName, Ports) ->
  searchPorts(BindingName, Ports, []).

searchPorts(_BindingName, [], Acc) ->
  Acc;
searchPorts(BindingName, [Port | Tail], Acc) ->
  PortBinding = erlsom_lib:localName(Port#port.binding),
  case PortBinding of
    BindingName ->
      searchPorts(BindingName, Tail, [Port | Acc]);
    _ ->
      searchPorts(BindingName, Tail, Acc)
  end.


getXsdsFromWsdl(Definitions) ->
  case getTopLevelElements(Definitions, 'wsdl:tTypes') of
    [#'wsdl:tTypes'{choice = Xsds}] -> Xsds;
    [] -> undefined
  end.

config_file_xsd() ->
"<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"
"  <xs:element name=\"soap_config\">"
"     <xs:complexType>"
"       <xs:sequence>"
"         <xs:element name=\"xsd_path\" type=\"xs:string\" minOccurs=\"0\"/>"
"         <xs:element name=\"user_module\" type=\"xs:string\"/>"
"         <xs:element name=\"wsdl_file\" type=\"xsd_file\"/>"
"         <xs:element name=\"add_file\" type=\"xsd_file\" minOccurs=\"0\" maxOccurs=\"unbounded\"/>"
"       </xs:sequence>"
"     </xs:complexType>"
"  </xs:element>"
"  <xs:complexType name=\"xsd_file\">"
"    <xs:sequence>"
"      <xs:element name=\"import_specs\" type=\"import_specs\" minOccurs=\"0\" maxOccurs=\"unbounded\"/>"
"    </xs:sequence>"
"    <xs:attribute name=\"name\" type=\"string\" use=\"required\"/>"
"    <xs:attribute name=\"prefix\" type=\"string\"/>"
"  </xs:complexType>"
"  <xs:complexType name=\"import_specs\">"
"    <xs:attribute name=\"namespace\" type=\"string\" use=\"required\"/>"
"    <xs:attribute name=\"prefix\" type=\"string\"/>"
"    <xs:attribute name=\"location\" type=\"string\"/>"
"  </xs:complexType>"
"</xs:schema>".
