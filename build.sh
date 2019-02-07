#!/bin/bash

cd mmalloc && ./configure
cd ../
make depend
make
