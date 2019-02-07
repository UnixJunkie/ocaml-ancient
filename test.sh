#!/bin/bash

echo 'running tests...'

ulimit -s unlimited
wordsfile=/usr/share/dict/words
baseaddr=0x440000000000 # System specific - see README.txt
./test_ancient_dict_write.opt $wordsfile dictionary.data $baseaddr
./test_ancient_dict_verify.opt $wordsfile dictionary.data
./test_ancient_dict_read.opt dictionary.data <<EOF
dog
cat
q
EOF
