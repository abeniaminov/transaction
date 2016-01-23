# The transaction application #


__Authors:__ Alexander Beniaminov ([`abeniaminov@gmail.com`](mailto:abeniaminov@gmail.com))


Scalable deadlock-resolving MVVC (MultiVersion Concurrency Control) read-committed transaction system




## transaction ##


A scalable, deadlock-resolving transaction application for Erlang/OTP gen_server like behaviour  


This application is inspired on MVVC algorithms and ideas, belonging to [David Patrick Reed](https://www.google.com/url?q=https://en.wikipedia.org/wiki/David_P._Reed)
, [Philip A. Bernstein, Nathan Goodman](https://www.cs.berkeley.edu/~brewer/cs262/concurrency-distributed-databases.pdf) and [Jim Starkey](https://en.wikipedia.org/wiki/Jim_Starkey)


Smart and efficient deadlock resolution algorithm was designed by Manuel Prieto, Jesús Villadangos, Federico Fariña, Alberto Córdoba, Dept. de Matemática e Informática Universidad Pública de Navarra.
[“An O(n) distributed deadlock resolution algorithm”](http://www.gsd.unavarra.es/gsd/files/spora/pdp20061.pdf)


About [MVCC](https://en.wikipedia.org/w/index.php?title=Multiversion_concurrency_control&oldid=701098838) and [isolation levels](https://en.wikipedia.org/wiki/Isolation_(database_systems)) can be read at Wikipedia 




## Using 'transaction' ##




## Structure of transaction ##




## Isolation level flavors #
