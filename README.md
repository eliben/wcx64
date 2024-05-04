wcx64
=====

**wcx64** is a simplistic `wc` clone in x64 assembly. Usage:

```
    $ wcx64 /tmp/1 /tmp/2 /usr/share/dict/words
              0          1          2    /tmp/1
              2          5         23    /tmp/2
          99171      99171     938848    /usr/share/dict/words
          99173      99177     938873    total
```

When not given any command-line arguments, reads from stdin:

```
    $ wcx64 < /tmp/2
              2          5         23
```

Always prints the all three counters: line, word, byte.
