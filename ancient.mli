(** Mark objects as 'ancient' so they are taken out of the OCaml heap. *)

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
    * @raise Invalid_argument "deleted" if the object has been deleted.
    *)

val delete : 'a ancient -> unit
  (** [delete obj] deletes ancient object [obj].
    *
    * @raise Invalid_argument "deleted" if the object has been deleted.
    *
    * Forgetting to delete an ancient object results in a memory leak.
    *)

val is_ancient : 'a -> bool
  (** [is_ancient ptr] returns true if [ptr] is an object on the ancient
    * heap.
    *)

val address_of : 'a -> nativeint
  (** [address_of obj] returns the address of [obj], or [0n] if [obj]
    * is not a block.
    *)

(** {6 Shared memory mappings} *)

type md
  (** Memory descriptor handle. *)

val attach : Unix.file_descr -> nativeint -> md
  (** [attach fd baseaddr] attaches to a new or existing file
    * which may contain shared objects.
    *
    * Initially [fd] should be a read/writable, zero-length file
    * (for example you could create this using {!Unix.openfile} and
    * passing the flags [O_RDWR], [O_TRUNC], [O_CREAT]).
    * One or more objects can then be shared in this file
    * using {!Unix.share}.
    *
    * For new files, [baseaddr] specifies the virtual address to
    * map the file.  Specifying [Nativeint.zero] ([0n]) here lets [mmap(2)]
    * choose this, but on some platforms (notably Linux/AMD64)
    * [mmap] chooses very unwisely, tending to map the memory
    * just before [libc] with hardly any headroom to grow.  If
    * you encounter this sort of problem (usually a segfault or
    * illegal instruction inside libc), then look at [/proc/PID/maps]
    * and choose a more suitable address.
    *
    * If the file was created previously, then the [baseaddr] is
    * ignored.  The underlying [mmalloc] library will map the
    * file in at the same place as before.
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
    * More than one object can be stored in a file.  The [key]
    * parameter controls which object is written/overwritten by [share].
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
    * (Other processes should not even call {!Ancient.get} while
    * this is happening, but it seems safe to be just reading an
    * ancient object from the file).
    *)

val get : md -> int -> 'a ancient
  (** [get md key] returns the object indexed by [key] in the
    * attached file.
    *
    * For details of the [key] parameter see {!Ancient.share}.
    *
    * You need to annotate the returned object with the correct
    * type.  As with the Marshal module, there is no type checking,
    * and setting the wrong type will likely cause a segfault
    * or undefined behaviour.  Note that the returned object has
    * type [sometype ancient], not just [sometype].
    *
    * @raise Not_found if no object is associated with the key.
    *)

(** {6 Additional information} *)

type info = {
  i_size : int;				(** Allocated size, bytes. *)
}
  (** Extra information fields.  See {!Ancient.mark_info} and
    * {!Ancient.share_info}.
    *)

val mark_info : 'a -> 'a ancient * info
  (** Same as {!Ancient.mark}, but also returns some extra information. *)

val share_info : md -> int -> 'a -> 'a ancient * info
  (** Same as {!Ancient.share}, but also returns some extra information. *)
