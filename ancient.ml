(* Mark objects as 'ancient' so they are taken out of the OCaml heap.
 * $Id: ancient.ml,v 1.6 2006-10-09 14:43:00 rich Exp $
 *)

type 'a ancient

type info = {
  i_size : int;
}

external mark_info : 'a -> 'a ancient * info = "ancient_mark_info"

let mark obj = fst (mark_info obj)

external follow : 'a ancient -> 'a = "ancient_follow"

external delete : 'a ancient -> unit = "ancient_delete"

external is_ancient : 'a -> bool = "ancient_is_ancient"

type md

external attach : Unix.file_descr -> nativeint -> md = "ancient_attach"

external detach : md -> unit = "ancient_detach"

external share_info : md -> int -> 'a -> 'a ancient * info
  = "ancient_share_info"

let share md key obj = fst (share_info md key obj)

external get : md -> int -> 'a ancient = "ancient_get"

let max_key = 1023 (* MMALLOC_KEYS-1.  See mmprivate.h *)
