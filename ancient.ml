(* Mark objects as 'ancient' so they are taken out of the OCaml heap.
 * $Id: ancient.ml,v 1.2 2006-09-27 15:36:18 rich Exp $
 *)

type 'a ancient

external mark : 'a -> 'a ancient = "ancient_mark"

external follow : 'a ancient -> 'a = "ancient_follow"

external delete : 'a ancient -> unit = "ancient_delete"

external share : Unix.file_descr -> 'a -> 'a ancient = "ancient_share"

external attach : Unix.file_descr -> 'a ancient = "ancient_attach"

external detach : 'a ancient -> unit = "ancient_detach"
