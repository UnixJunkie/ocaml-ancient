(** Mark objects as 'ancient' so they are taken out of the OCaml heap.
  * $Id: ancient.mli,v 1.2 2006-09-27 15:36:18 rich Exp $
  *)

type 'a ancient

val mark : 'a -> 'a ancient
  (** [mark obj] copies [obj] and all objects referenced
    * by [obj] out of the OCaml heap.  It returns the proxy
    * for [obj].
    *
    * The copy of [obj] accessed through the proxy MUST NOT be mutated.
    *
    * If [obj] represents a large object, then it is a good
    * idea to call {!Gc.compact} after marking to recover the
    * OCaml heap memory.
    *)

val follow : 'a ancient -> 'a
  (** Follow proxy link to out of heap object.
    *
    * @raise [Invalid_argument "deleted"] if the object has been deleted.
    *)

val delete : 'a ancient -> unit
  (** [delete obj] deletes ancient object [obj].
    *
    * @raise [Invalid_argument "deleted"] if the object has been deleted.
    *
    * Forgetting to delete an ancient object results in a memory leak.
    *)

(** {6 Shared memory mappings} *)

val share : Unix.file_descr -> 'a -> 'a ancient
  (** [share fd obj] does the same as {!Ancient.mark} except
    * that instead of copying the object into local memory, it
    * writes it into memory which is backed by the file [fd].
    * [fd] should be a writable, zero-length file (see
    * {!Unix.openfile}).
    *
    * Shared mappings created this way may be shared between
    * other OCaml processes which can access the underlying
    * file.  See {!Ancient.attach}, {!Ancient.detach}.
    *
    * Do not call {!Ancient.delete} on a mapping created like this.
    * Instead, call {!Ancient.detach} and, if necessary, delete the
    * underlying file.
    *)

val attach : Unix.file_descr -> 'a ancient
  (** [attach fd] takes an existing file which was created by
    * {!Ancient.share} and accesses the object contained
    * in it.
    *
    * You need to force the return type to be the correct type
    * for the object contained in the file.  As with Marshal,
    * the type is not checked, and if it is wrong a segfault
    * is likely.
    *
    * Do not call {!Ancient.delete} on a mapping created like this.
    * Instead, call {!Ancient.detach} and, if necessary, delete the
    * underlying file.
    *)

val detach : 'a ancient -> unit
  (** [detach obj] detaches from a shared mapping.
    *
    * @raise [Invalid_argument "detached"] if the object has been detached.
    *)
