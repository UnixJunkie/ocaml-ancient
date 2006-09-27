(* Load in large weblogs and see if they can still be used.
 * $Id: test_ancient_weblogs.ml,v 1.1 2006-09-27 14:05:07 rich Exp $
 *)

open Printf

open ExtList

let gc_stats = true (* If true, print GC stats before processing each day. *)

let (//) = Filename.concat

let rec range a b =
  if a > b then []
  else a :: range (succ a) b

(* Cartesian join of two lists. *)
let cartesian xs ys =
  List.flatten (
    List.map (
      fun x ->
	List.map (
	  fun y -> x, y
	) ys
    ) xs
  )

let file_readable filename =
  try Unix.access filename [Unix.R_OK]; true
  with Unix.Unix_error _ -> false

(* Suppress warning messages. *)
let () = Weblogs.quiet := true

let gc_compact () =
  eprintf "compacting ... %!";
  Gc.compact ();
  if gc_stats then (
    let stat = Gc.stat () in
    let live_words = stat.Gc.live_words in
    eprintf "live words = %d (%d MB)\n%!"
      live_words (live_words * 8 / 1024 / 1024)
  )

(* Find the list of files.  Some which should exist don't, so
 * warnings about those so we can chase up.
 *)
let files =
  let dir = "/home/rich/oversized-logfiles/perrys" in
  let drivers =
    [ "burns"; "gronholm"; "rohrl"; "sainz"; "solberg"; "vatanen" ] in
  let dates = range 1 31 in
  let dates = List.map (fun day -> sprintf "200608%02d" day) dates in
  let files = cartesian drivers dates in
  let files =
    List.map (fun (driver, date) ->
		sprintf "%s-perrys-access.log.%s.gz" driver date) files in
  let files =
    List.filter_map (
      fun filename ->
	let path = dir // filename in
	if not (file_readable path) then (
	  prerr_endline ("warning: " ^ filename ^ " not found - ignored");
	  None
	) else (
	  Some path
	)
    ) files in

  eprintf "number of files = %d\n%!" (List.length files);

  files

(* Load each file into memory and make it ancient. *)
let () =
  let files =
    List.map (
      fun filename ->
	eprintf "Importing file %s\n%!" filename;
	let rows =
	  let rows = Weblogs.import_file filename in
	  Ancient.mark rows in
	gc_compact ();
	rows
    ) files in

  ignore (files)

