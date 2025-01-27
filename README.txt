'Ancient' module for OCaml
----------------------------------------------------------------------

What does this module do?
----------------------------------------------------------------------

This module allows you to use in-memory data structures which are
larger than available memory and so are kept in swap.  If you try this
in normal OCaml code, you'll find that the machine quickly descends
into thrashing as the garbage collector repeatedly iterates over
swapped memory structures.  This module lets you break that
limitation.  Of course the module doesn't work by magic :-) If your
program tries to access these large structures, they still need to be
swapped back in, but it is suitable for large, sparsely accessed
structures.

Secondly, this module allows you to share those structures between
processes.  In this mode, the structures are backed by a disk file,
and any process that has read/write access that disk file can map that
file in and see the structures.

To understand what this module really does, you need to know a little
bit of background about the OCaml garbage collector (GC).  OCaml's GC
has two heaps, called the minor and major heaps.  The minor heap is
used for short-term storage of small objects which are usually created
and then quickly become unreachable.  Any objects which persist longer
(or objects which are very big to start with) get moved into the major
heap.  Objects in the major heap are assumed to be around for some
time, and the major heap is GC'd more slowly.

This module adds a third heap, called the "ancient heap", which is
never checked by the GC.  Objects must be moved into ancient manually,
using a process called "marking".  Once an object is in the ancient
heap, memory allocation is handled manually.  In particular objects in
the ancient heap may need to be manually deallocated.  The ancient
heap may either exist as ordinary memory, or may be backed by a file,
which is how shared structures are possible.

Structures which are moved into ancient must be treated as STRICTLY
NON-MUTABLE.  If an ancient structure is changed in any way then it
may cause a crash.

There are some limitations which apply to ancient data structures.
See the section "Shortcomings & bugs" below.

This module is most useful on 64 bit architectures where large address
spaces are the norm.  We have successfully used it with a 38 GB
address space backed by a file and shared between processes.

API
----------------------------------------------------------------------

Please see file ancient.mli .

Compiling
----------------------------------------------------------------------

  cd mmalloc && ./configure
  make

Make sure you run this command before running any program which
uses the Ancient module:

  ulimit -s unlimited

Example
----------------------------------------------------------------------

XXX Note the example code is really stupid, and fails for large
dictionaries.  See bug (10) below.

Run:

  ulimit -s unlimited
  wordsfile=/usr/share/dict/words
  baseaddr=0x440000000000               # System specific - see below.
  ./test_ancient_dict_write.opt $wordsfile dictionary.data $baseaddr
  ./test_ancient_dict_verify.opt $wordsfile dictionary.data
  ./test_ancient_dict_read.opt dictionary.data

(You can run several instances of test_ancient_dict_read.opt on the
same machine to demonstrate sharing).

Shortcomings & bugs
----------------------------------------------------------------------

(0) Stack overflows are common when marking/sharing large structures
because we use a recursive algorithm to visit the structures.  If you
get random segfaults during marking/sharing, then try this before
running your program:

  ulimit -s unlimited

(1) Ad-hoc polymorphic primitives (structural equality, marshalling
and hashing) do not work on ancient data structures, meaning that you
will need to provide your own comparison and hashing functions.  For
more details see Xavier Leroy's response here:

http://caml.inria.fr/pub/ml-archives/caml-list/2006/09/977818689f4ceb2178c592453df7a343.en.html

(2) Ancient.attach suggests setting a baseaddr parameter for newly
created files (it has no effect when attaching existing files).  We
strongly recommend this because in our tests we found that mmap would
locate the memory segment inappropriately -- the basic problem is that
because the file starts off with zero length, mmap thinks it can place
it anywhere in memory and often does not leave it room to grow upwards
without overwriting later memory mappings.  Unfortunately this
introduces an unwanted architecture dependency in all programs which
use the Ancient module with shared files, and it also requires
programmers to guess at a good base address which will be valid in the
future.  There are no other good solutions we have found --
preallocating the file is tricky with the current mmalloc code.

(3) The current code requires you to first of all create the large
data structures on the regular OCaml heap, then mark them as ancient,
effectively copying them out of the OCaml heap, then garbage collect
the (hopefully unreferenced) structures on the OCaml heap.  In other
words, you need to have all the memory available as physical memory.
The way to avoid this is to mark structures as ancient incrementally
as they are created, or in chunks, whatever works for you.

We typically use Ancient to deal with web server logfiles, and in this
case loading one file of data into memory and marking it as ancient
before moving on to the next file works for us.

(4) Why do ancient structures need to be read-only / not mutated?  The
reason is that you might create a new OCaml heap structure and point
the ancient structure at this heap structure.  The heap structure has
no apparent incoming pointers (the GC will not by its very nature
check the ancient structure for pointers), and so the heap structure
gets garbage collected.  At this point the ancient structure has a
dangling pointer, which will usually result in some form of crash.
Note that the restriction here is on creating pointers from ancient
data to OCaml heap data.  In theory it should be possible to modify
ancient data to point to other ancient data, but we have not tried
this.

(5) [Limit on number of keys -- issue fixed]

(6) [Advanced topic] The _mark function in ancient_c.c makes no
attempt to arrange the data structures in memory / on disk in a way
which optimises them for access.  The worst example is when you have
an array of large structures, where only a few fields in the structure
will be accessed.  Typically these will end up on disk as:

  array of N pointers
  structure 1
  field A
  field B
    ...
  field Z
  structure 2
  field A
  field B
    ...
  field Z
  structure 3
  field A
  field B
    ...
  field Z
   ...
   ...
   ...
  structure N
  field A
  field B
    ...
  field Z

If you then iterate accessing only fields A, you end up swapping the
whole lot back into memory.  A better arrangement would have been:

  array of N pointers
  structure 1
  structure 2
  structure 3
    ...
  structure N
  field A from structure 1
  field A from structure 2
  field A from structure 3
    ...
  field A from structure N
  field B from structure 1
  field B from structure 2
    etc.

which avoids loading unused fields at all.  In some circumstances we
have shown that this could make a huge difference to performance, but
we are not sure how to implement this cleanly in the current library.

[Update: I have fixed issue 6 manually for my Weblogs example and
confirmed that it does make a huge difference to performance, although
at considerable extra code complexity.  Interested people can see the
weblogs library, file import_weblogs_ancient.ml.in].

(7) [Advanced topic] Certain techniques such as Address Space
Randomisation (http://lwn.net/Articles/121845/) are probably not
compatible with the Ancient module and shared files.  Because the
ancient data structures contain real pointers, these pointers would be
invalidated if the shared file was not mapped in at precisely the same
base address in all processes which are sharing the file.

One solution might be to use private mappings and a list of fixups.
In fact, the code actually builds a list of fixups currently while
marking, because it needs to deal with precisely this issue (during
marking, memory is allocated with realloc which might move the memory
segment, thus real pointers cannot be stored while marking, but need
to be fixed up afterwards).  The list of fixups would need to be
stored alongside the memory segment (currently it is discarded after
marking), and the file would need to be mapped in using MAP_PRIVATE
(see below).

A possible problem with this is that because OCaml objects tend to be
small and contain a lot of pointers, it is likely that fixing up the
pointers would result in every page in the memory segment becoming
dirty, which would basically cancel out any benefit of using shared
mappings in the first place.  However it is likely that some users of
this module have large amounts of opaque data and few pointers, and
for them this would be worthwhile.

(8) Currently mmalloc is implemented so that the file is mapped in
PROT_READ|PROT_WRITE and MAP_SHARED.  Ancient data structures are
supposed to be immutable so strictly speaking write access shouldn't
be required.  It may be worthwhile modifying mmalloc to allow
read-only mappings, and private mappings.

(9) The library assumes that every OCaml object is at least one word
long.  This seemed like a good assumption up until I found that
zero-length arrays are valid zero word objects.  At the moment you
cannot mark structures which contain zero-length arrays -- you will
get an assert-failure in the _mark function.

Possibly there are other types of OCaml structure which are zero word
objects and also cannot be marked.  I'm not sure what these will be:
for example empty strings are stored as one word OCaml objects, so
they are OK.

The solution to this bug is non-trivial.

(10) Example code is very stupid.  It fails with large dictionaries,
eg. the one with nearly 500,000 words found in Fedora.

(11) In function 'mark', the "// Ran out of memory.  Recover and throw
an exception." codepath actually fails if you use it - segfaulting
inside do_restore.

Authors
----------------------------------------------------------------------

Primary code was written by Richard W.M. Jones <rich at annexia.org>
with help from Markus Mottl, Martin Jambon, and invaluable advice from
Xavier Leroy and Damien Doligez.

mmalloc was written by Mike Haertel and Fred Fish.

Port to no-naked-pointers and OCaml 5+ by Fabrice Le Fessant at
OCamlPro.

License
----------------------------------------------------------------------

The module is licensed under the LGPL + OCaml linking exception.  This
module includes mmalloc which was originally distributed with gdb
(although it has since been removed), and that code was distributed
under the plain LGPL.

Latest version
----------------------------------------------------------------------

The latest version can be found on the website:
http://merjis.com/developers/ancient
