(** Mark objects as 'ancient' so they are taken out of the OCaml heap.
  * $Id: ancient.mli,v 1.1 2006-09-27 12:07:07 rich Exp $
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
