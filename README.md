# The transaction application


__Authors:__ Alexander Beniaminov ([`abeniaminov@gmail.com`](mailto:abeniaminov@gmail.com))


Scalable deadlock-resolving MVCC (MultiVersion Concurrency Control) read-committed transaction system




## transaction ##


A scalable, deadlock-resolving transaction application for Erlang/OTP gen_server like behaviour  


This application is inspired on MVCC algorithms and ideas, belonging to [David Patrick Reed](https://www.google.com/url?q=https://en.wikipedia.org/wiki/David_P._Reed)
, [Philip A. Bernstein, Nathan Goodman](https://www.cs.berkeley.edu/~brewer/cs262/concurrency-distributed-databases.pdf) and [Jim Starkey](https://en.wikipedia.org/wiki/Jim_Starkey)


Smart and efficient deadlock resolution algorithm was designed by Manuel Prieto, Jesús Villadangos, Federico Fariña, Alberto Córdoba, Dept. de Matemática e Informática Universidad Pública de Navarra.
[“An O(n) distributed deadlock resolution algorithm”](http://www.gsd.unavarra.es/gsd/files/spora/pdp20061.pdf)


About [MVCC](https://en.wikipedia.org/w/index.php?title=Multiversion_concurrency_control&oldid=701098838) and [isolation levels](https://en.wikipedia.org/wiki/Isolation_(database_systems)) can be read at Wikipedia 

## Preamble


## Using transaction 

Call 'application:start(transaction)' on each node where you plan to use processes with tgen_server behaivour.
Before any action with tgen_server process, client must obtain transaction context by call

	Tr1 = transaction:start(Options).

  
Options is a map of type:

	-type tr_options() :: #{i_level => version_level(), wait => wait(), overwrite => overwrite()}.
	-type version_level() :: record_version |no_record_version.
	-type wait() :: wait | no_wait.
	-type overwrite() :: boolean().

OR you call one of the functions

	Tr = transaction:start(). %% record_version, no_wait, no overwrite
	Tr = transaction:start_o(). %% record_version, no_wait, overwrite
	Tr = transaction:start_n(). %% no_record_version, no_wait, no overwrite
	Tr = transaction:start_no(). %% no_record_version, no_wait, overwrite 
	Tr = transaction:start_nw(). %% no_record_version, wait, no overwrite
	Tr = transaction:start_nwo(). %% no_record_version, wait, overwrite

These functions returns map() with five elements: 
* tr_id - unique transaction id, has reference type
* tr_bet - integer, the bet from transaction for deadlock-resolving algorithm
* other three are options of transaction


## Transaction API

    transaction:commit(Tr).

The coordinated transfer of all processes from active to committed state. All changes of all processes that made in the context of the transaction Tr, will be saved. All processes are started or stopped in the context of this transaction, will be respectively alive or be stopped.
  
    transaction:rollback(Tr).

The coordinated transfer of all processes from active to committed state. All changes of all processes that made in the context of the transaction Tr, will be roll back. All processes are started or stopped in the context of this transaction, will be respectively stoped or be alive with last committed state.

    transaction:set_locks(Tr, L)

Trying to transfer to the active state all the processes in the list L. Returns ok, if it's able to do, busy or deadlock, if not managed. 

## tgen_server API
tgen_server is gen_server like behaviour. 

    start(Mod, Args, Tr, Options)
    start(Name, Mod, Args, Tr, Options)
    start_link(Mod, Args, Tr, Options)
    start_link(Name, Mod, Args, Tr, Options)
There are analog of start and start_link functions of gen_server. The only difference is parameter Tr. I think you've guessed, it's transaction contexts. The tgen_server process calls Module:init/2 to initialize.



    lock(Pid, Tr)
Attempt to change to the active state the processes with pid Pid. Returns ok, if it's able to do, busy or deadlock, if not managed.
    
    stop(Pid, Tr)
Attempt to stop process with pid Pid. Actually the process  transfer to state "stopping", rather then stop really. Process stops only after transaction commit. If transaction is rolled back, the process transfer to previously committed state. The tgen_server will call Module:terminate/3 before exiting.  

    call(Pid, Tr, Request)
Makes a synchronous call to the tgen_server ServerRef by sending a request and waiting until a reply arrives. Second parameter is transaction context. The tgen_server will call Module:handle_call/4 to handle the request.

## callback functions
	init(Tr, Args)
	handle_call(Tr, Request, From, State)
	terminate(Tr, Reason, State)

This is analogous to the callback functions of gen_server. First parameter is transaction context.

## Приложение transaction
Приложение поддерживающее транзакции для процессов типа gen_server 


Использование транзакции в системе означает, что у некого подмножества процессов  в конкурентной среде можно согласованно изменять их состояния либо целиком и успешно, соблюдая целостность и независимость от параллельно идущих других транзакций, либо изменения не будут выполнены вообще для этого подмножества процессов.  

В приложении реализован механизм управления транзакциями MVCC  — MultiVersion Concurrency Control (управление конкурентным доступом с помощью многоверсионности) для уровня изоляции Read Committed в трех версиях: record_version_no_wait, no_record_version_ wait и no_record_ version_ no_wait.



Процесс transaction должен быть предварительно запущен либо как отдельное приложение, 
	
	application:start(transaction)

либо в качестве worker процесса в супервизоре верхнего уровня. 

Поведение (behaviour) tgen_server реализовано как процесс OTP с поведением gen_server. 
 
Все действия с tgen_server процессом должны производиться в контексте какой-нибудь транзакции.

Транзакция запускается одной из функцией: 
	Tr = transaction:start(). %% record_version, no_wait, no overwrite
	Tr = transaction:start_o(). %% record_version, no_wait, overwrite
	Tr = transaction:start_n(). %% no_record_version, no_wait, no overwrite
	Tr = transaction:start_no(). %% no_record_version, no_wait, overwrite 
	Tr = transaction:start_nw(). %% no_record_version, wait, no overwrite
	Tr = transaction:start_nwo(). %% no_record_version, wait, overwrite


 
tgen_server запускается функцией 

	start_link(Module, Args, Tr, Options)

, т.е в отличие от gen_server обязан запускаться в контексте транзакции. 
 
Клиентский процесс, имея намерение запросить или изменить данные  одного или нескольких серверных процессов с поведением tgen_server, должен перед этим стартовать транзакцию. После успешного чтения и/или изменения данных нужно подтвердить изменения, вызвав transaction:commit(Tr), в случае неудачи откатиться, вызвав  transaction:rollback(Tr).  

tgen_server процесс может находиться в четырех состояниях: starting, committed (данные процесса были сохранены в контексте  закончившейся транзакции и в данный момент никто не пытается  изменить данные процесса), active (в контексте какой-то транзакции пытаются изменить данные процесса) и stopping. Данные процесса в состоянии committed могут читаться в контексте любых транзакций вне зависимости от их параметров.  
tgen_server процесс  переходит из committed в active, когда в контексте транзакции он изменяет данные стэйта. Такую транзакцию будем называть активной для этого процесса. В этот момент внутри процесса создается вариант стэйта, который будет доступен для чтения и изменения только в контексте этой активной транзакции. Таким образом, в активном состоянии процесс содержит два варианта данных стейта: committed вариант и active вариант. Видимость данных стэйта этого активного процесса в контексте других  конкурирующих транзакций зависит от их параметров использования версий и поведения при блокировке.

	record_version
В контексте такой конкурирующей транзакции active процесс беспрепятственно дает читать свой committed вариант стейта. При попытке изменить стейт, клиентский процесс получит информацию, что серверный процесс занят (busy). 

	no_record version no_wait
И при чтении и при записи клиентский процесс  получит от активного серверного процесса информацию, что он занят  

	no_record version wait
При попытке прочитать или изменить данные активного процесса, клиент переходит в состояние ожидания, перед этим подписавшись на сообщение от серверного процесса, что  активная транзакция подтверждена или отменена  и  процесс перешел в состояние committed. После получения сообщения, клиент продолжает попытку работы с актуальными ( свеже-закоммиченными) данными процесса. Если сообщение от сервера не приходит за некоторое время (?DEADLOCK_TIMEOUT), клиент получает сообщение о том, что возникла ситуация, которая похожа на взаимную блокировку процессов (deadlock). После этого  клиент ( совместно с другими клиентами в той-же ситуации)  реализует алгоритм разрешения этого конфликта.   

	overwrite (true or false)
Параметр транзакции определяющий, допустим ли dirty update.  Описание проблемы можно прочитать, например, у [Джо Армстронга](http://armstrongonsoftware.blogspot.ru/2006/09/pure-and-simple-transaction-memories.html).   
Предположим, что в контексте транзакции с номером 269 было прочтено последнее, подтвержденное транзакцией с номером 85, состояние некоторого процесса. После этого в контексте транзакции с номером 290 были произведены изменения состояния этого процесса и подтверждены. Теперь транзакция 269 пытается изменить состояние процесса на основе данных 85-ой транзакции. Параметр overwrite  true позволяет это сделать, в false клиенту возвращается, что он опоздал (lost).

## API transaction

Функции создания уникальной транзакции 

	transaction:start(). %% record_version, no_wait, no overwrite
	transaction:start_o(). %% record_version, no_wait, overwrite
	transaction:start_n(). %% no_record_version, no_wait, no overwrite
	transaction:start_no(). %% no_record_version, no_wait, overwrite 
	transaction:start_nw(). %% no_record_version, wait, no overwrite
	transaction:start_nwo(). %% no_record_version, wait, overwrite

Функция возвращает мэп из пяти элементов: уникальный номер транзакции, параметр величины ставки для разрешения ситуации deadlock, параметр использования версии (record_version или  no_record_version), параметр поведения при блокировке (wait или no_wait) и overwrite - разрешение перекрывающих изменений, который по-умолчанию false. 


	transaction:commit(Tr). 

Согласованный перевод всех процессов из состояния active в committed. Все изменения во всех процессах, сделанные в контексте транзакции Tr, будут сохранены. Все процессы, созданные или остановленные в контексте этой транзакции, будут соответственно работать или будут остановлены.  


	transaction:rollback(Tr).

Согласованный перевод всех процессов из состояния active в committed. Все изменения во всех процессах, сделанные в контексте транзакции Tr, будут отменены. Все процессы, созданные в контексте этой транзакции, будут остановлены, а остановленные процессы останутся живы с последним committed состоянием. 


	transaction:set_locks(Tr, L)

Попытка перевести в состояние active все процессы из списка L. Возвращает ok, если это удалось сделать, busy или deadlock, если не удалось. При этом часть процессов может остаться в состоянии active. Решать, что делать дальше  остается на усмотрение клиента. 


## API tgen_server

	tgen_server:start(Mod, Args, Tr, Options).
	tgen_server:start(Name, Mod, Args, Tr, Options). 
	tgen_server:start_link(Mod, Args, Tr, Options).
	tgen_server:start_link(Name, Mod, Args, Tr, Options).

аналог старта процесса gen_server, только третьим параметром является контекст транзакции. В процессе старта запускается функция обратного вызова init. Процесс в это время в состоянии starting и виден только в контексте создавшей его транзакции. Для всех остальных транзакций любого типа он будет недоступен. После подтверждения транзакции процесс перейдет в состояние committed и станет виден другим транзакциям. Если создавшая этот процесс транзакция откатится, то процесс будет остановлен.

	tgen_server:lock(Pid, Tr)

Попытка перевода процесса с уникальным идентификатором процесса Pid в состояние active в контексте транзакции Tr.  Возвращает ok, если это удалось сделать, busy или deadlock, если не удалось. 

	tgen_server:lock(Res, Pid, Tr)

То же, что и предыдущая функция, за исключением того, что в первый параметр является индикатором, следует ли действительно вызывать фунцию. Используется для написания более простого кода.  

	lock(Res, Pid, Tr) ->
	   case Res of
	       deadlock -> deadlock;
	       busy -> busy;
	       lost -> lost;
	       _ ->  lock(Pid, Tr)
	   end.

 

	tgen_server:stop(Pid,  Tr)
	
Попытка остановить процесс. На самом деле процесс не останавливается, а переходит в состояние stopping. Если в дальнейшем транзакция подтверждается, то процесс останавливается, если транзакция отменяется, то процесс переходит в предыдущее закоммиченное состояние. В процессе останова вызывается функция обратного вызова terminate


	tgen_server:call(Pid, Tr, Request)
Аналог call функции gen_server, второй параметр - это контекст транзакции, в котором должна выполниться эта функция.

Возвращает результат запроса к серверу, если все в порядке; busy,если процесс занят; deadlock,если попал в ситуацию взаимной блокировки и проиграл в процессе её разрешения; lost, если попал в ситуацию dirty update. Вызывается функция обратного вызова handle_call

В tgen_server не поддерживаются асинхронные вызовы типа cast, поэтому не требуются функции обратного вызова handle_cast

## функции обратного вызова

	init(Tr, Args)
	handle_call(Tr, Request, From, State)
	terminate(Tr, Reason, State)

аналоги соответствующих функций gen_server, первый параметр - контекст вызывающей транзакции.


## пример tgen_server

Простейший tgen_server процесс, который умеет хранить и отдавать целиком произвольный erlang терм. А еще умеет запускать еще один такой процесс в контексте транзакции.   
	
	-module(tgen_sampl).
	-behaviour(tgen_server).

	%% API
	-export([start_link/3, start_link/2]).
	-export([set_value/3, get_value/2, stop/2, start_from/3]).


	%% gen_server callbacks
	-export([init/2,
	   handle_call/4,
	   handle_info/3,
	   terminate/3,
	   code_change/3]).
	
	-define(SERVER, ?MODULE).
	
	
	------------------------------------------------------
	
	start_link(Name, Tr, InitVal) ->   
	  tgen_server:start_link({local, Name}, ?MODULE, InitVal, Tr, []).
	
	start_link(Tr, InitVal) ->
	   tgen_server:start_link(?MODULE, InitVal, Tr, []).
	
	
	set_value(Pid, Tr, Value) ->
	   tgen_server:call(Pid, Tr, {set_value, Value}).
	
	get_value(Pid, Tr) ->
	   tgen_server:call(Pid, Tr, get_value).
	
	start_from(Pid, Tr, Value) ->
	   tgen_server:call(Pid, Tr, {start_from, Value}).
	
	stop(Pid, Tr) ->
	   tgen_server:stop(Pid, Tr).
	
	
	
	init(_Tr, InitVal) ->
	   {ok, InitVal}.
	
	
	handle_call(_Tr, {set_value, Value}, _From, _State) ->
	   {reply, ok, Value};
	
	handle_call(Tr, {start_from, Value}, _From, _State) ->
	   NewPid = start_link(Tr, Value),
	   {reply, NewPid, Value};
	
	handle_call(_Tr, get_value, _From, State) ->
	   {reply, State, State}.
	
	handle_info(_Tr,_Info, State) ->
	   {noreply, State}.
	
	terminate(_Tr, _Reason, _State) ->
	   ok.
	
	code_change(_OldVsn, State, _Extra) ->
	   {ok, State}.

## пример клиентского кода


создание локального процесса зарегистрированного как о1 с начальным значением 0 

	Tr1 = transaction:start(),
	tgen_sampl:start_link(o1, Tr1, 0),
	transaction:commit(Tr1),
   
создаем контексты двух транзакций типа record_version no_wait no_overwrite

	Tr2 = transaction:start(),
	Tr3 = transaction:start(),

В контексте транзакции Tr3 считываем значение состояния в переменную V0 (значение 0)

	V0 = tgen_sampl:get_value(o1, Tr3),

В контексте транзакции Tr2 изменяем состояние в процессе на 1

	SetV = 1,
	tgen_sampl:set_value(o1, Tr2, SetV),

В контексте транзакции Tr3 считываем значение состояния в переменную V1. Считывается 0, потому что это последнее подтвержденное значение, которое видит Tr3. Транзакция Tr3 не видит неподтвержденных изменений от транзакции Tr2. 

	V1 = tgen_sampl:get_value(o1, Tr3),
	?assert(V0 =:= V1),

Подтверждаем изменения от транзакции Tr2

	transaction:commit(Tr2),

В контексте транзакции Tr3 опять считываем значение состояния в переменную V2. Считывается 1, потому что теперь это последнее подтвержденное значение, которое видит Tr3. Транзакция Tr3  теперь видит подтвержденные изменения от транзакции Tr2. 

	V2 = tgen_sampl:get_value(o1, Tr3),
	?assert(SetV =:= V2),

Команда на останов процесса 

	tgen_sampl:stop(o1, Tr3),

Подтверждение останова

	transaction:commit(Tr3).

