(* Mark objects as 'ancient' so they are taken out of the OCaml heap.
 * $Id: ancient.ml,v 1.1 2006-09-27 12:07:07 rich Exp $
 *)

type 'a ancient

external mark : 'a -> 'a ancient = "ancient_mark"

external follow : 'a ancient -> 'a = "ancient_follow"

external delete : 'a ancient -> unit = "ancient_delete"
