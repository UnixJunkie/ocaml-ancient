(* Mark objects as 'ancient' so they are taken out of the OCaml heap.
 * $Id: ancient.ml,v 1.3 2006-09-27 18:39:44 rich Exp $
 *)

type 'a ancient

external mark : 'a -> 'a ancient = "ancient_mark"

external follow : 'a ancient -> 'a = "ancient_follow"

external delete : 'a ancient -> unit = "ancient_delete"

type md

external attach : Unix.file_descr -> md = "ancient_attach"

external detach : md -> unit = "ancient_detach"

external share : md -> int -> 'a -> 'a ancient = "ancient_share"

external get : md -> int -> 'a ancient = "ancient_get"
