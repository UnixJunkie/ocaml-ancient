(* Read shared dictionary.
 * $Id: test_ancient_dict_read.ml,v 1.1 2006-10-06 15:03:47 rich Exp $
 *)

open Printf
open Unix

let argv = Array.to_list Sys.argv

let datafile =
  match argv with
  | [_; datafile] ->
      datafile
  | _ ->
      failwith (sprintf "usage: %s datafile"
		  Sys.executable_name)

let md =
  let fd = openfile datafile [O_RDWR] 0o644 in
  Ancient.attach fd 0n

let arraysize = 256 (* one element for each character *)

type t = Not_Found | Exists of t array | Not_Exists of t array;;
let tree : t array Ancient.ancient = Ancient.get md 0
let tree = Ancient.follow tree

let word_exists word =
  try
    let tree = ref tree in
    let len = String.length word in
    for i = 0 to len-2; do
      let c = word.[i] in
      let c = Char.code c in
      match (!tree).(c) with
      | Not_Found -> raise Not_found
      | Exists tree'
      | Not_Exists tree' -> tree := tree'
    done;

    (* Final character. *)
    let c = word.[len-1] in
    let c = Char.code c in
    match (!tree).(c) with
    | Not_Found
    | Not_Exists _ -> false
    | Exists _ -> true
  with
    Not_found -> false

let () =
  let rec loop () =
    printf "Enter a word to check (q = quit program): ";
    let word = read_line () in
    if word <> "q" then (
      printf "'%s' exists? %B\n%!" word (word_exists word);
      loop ()
    )
  in
  loop ();

  Ancient.detach md;

  (* Garbage collect - good way to check we haven't broken anything. *)
  Gc.compact ();

  printf "Program finished.\n"
