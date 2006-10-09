(* Mark objects as 'ancient' so they are taken out of the OCaml heap.
 * $Id: ancient.ml,v 1.5 2006-10-09 12:18:05 rich Exp $
 *)

type 'a ancient

external mark : 'a -> 'a ancient = "ancient_mark"

external follow : 'a ancient -> 'a = "ancient_follow"

external delete : 'a ancient -> unit = "ancient_delete"

external is_ancient : 'a -> bool = "ancient_is_ancient"

type md

external attach : Unix.file_descr -> nativeint -> md = "ancient_attach"

external detach : md -> unit = "ancient_detach"

external share : md -> int -> 'a -> 'a ancient = "ancient_share"

external get : md -> int -> 'a ancient = "ancient_get"

let max_key = 1023 (* MMALLOC_KEYS-1.  See mmprivate.h *)
