(** Mark objects as 'ancient' so they are taken out of the OCaml heap.
  * $Id: ancient.mli,v 1.3 2006-09-27 18:39:44 rich Exp $
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

type md
  (** Memory descriptor handle. *)

val attach : Unix.file_descr -> md
  (** [attach fd] attaches to a new or existing file which may contain
    * shared objects.
    *
    * Initially [fd] should be a read/writable, zero-length file
    * (see {!Unix.openfile}).  One or more objects can then be
    * shared in this file using {!Unix.share}.
    *)

val detach : md -> unit
  (** [detach md] detaches from an existing file, and closes it.
    *)

val share : md -> int -> 'a -> 'a ancient
  (** [share md key obj] does the same as {!Ancient.mark} except
    * that instead of copying the object into local memory, it
    * writes it into memory which is backed by the attached file.
    *
    * Shared mappings created this way may be shared between
    * other OCaml processes which can access the underlying
    * file.  See {!Ancient.attach}, {!Ancient.detach}.
    *
    * More than one object can be stored in a file.  They are
    * indexed using integers in the range [0..1023] (the limit
    * is hard-coded in [mmalloc/mmprivate.h]).  The [key] parameter
    * controls which object is written/overwritten by [share].
    * If you do not wish to use this feature, just pass [0]
    * as the key.
    *
    * Do not call {!Ancient.delete} on a mapping created like this.
    * Instead, call {!Ancient.detach} and, if necessary, delete the
    * underlying file.
    *
    * Caution when sharing files/objects between processes:
    * The underlying [mmalloc] library does not do any sort of
    * locking, so all calls to [share] must ensure that they have
    * exclusive access to the underlying file while in progress.
    *)

val get : md -> int -> 'a ancient
  (** [get md key] returns the object indexed by [key] in the
    * attached file.
    *
    * The key is in the range [0..1023] (the limit is hard-coded in
    * [mmalloc/mmprivate.h]).
    *
    * You need to annotate the returned object with the correct
    * type.  As with the Marshal module, there is no type checking,
    * and setting the wrong type will likely cause a segfault
    * or undefined behaviour.
    *
    * @raises [Not_found] if no object is associated with the key.
    *)
