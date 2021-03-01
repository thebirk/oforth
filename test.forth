: . . cr ;
: hey immediate 999 . ;

333 .

: square
    hey dup * ;

111 .
4 square .



: override-test 7 . ;
: compiled-with-old override-test ;
override-test

: override-test 8 . ;
override-test
compiled-with-old
