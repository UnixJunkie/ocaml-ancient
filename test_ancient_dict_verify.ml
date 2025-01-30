(* Verify shared dictionary. *)

open Test_ancient_dict
open Printf
open Unix

let argv = Array.to_list Sys.argv

let wordsfile, datafile =
  match argv with
  | [_; wordsfile; datafile] ->
      wordsfile, datafile
  | _ ->
      failwith (sprintf "usage: %s wordsfile datafile"
		  Sys.executable_name)

let md =
  let fd = openfile datafile [O_RDWR] 0o644 in
  Ancient.attach fd 0n

let arraysize = 256 (* one element for each character *)

let tree : tree array Ancient.ancient = Ancient.get md 0
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
      | Exists (_,tree')
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
  (* Read in the words and keep in a local list. *)
  let words = ref [] in
  let chan = open_in wordsfile in
  let rec loop () =
    let word = input_line chan in
    if word <> "" then words := word :: !words;
    loop ()
  in
  (try loop () with End_of_file -> ());
  close_in chan;
  let words = List.rev !words in

  (* Verify that the number of words in the tree is the same as the
   * number of words in the words file.
   *)
  let nr_expected = List.length words in
  let nr_actual =
    let rec count tree =
      let c = ref 0 in
      for i = 0 to arraysize-1 do
	match tree.(i) with
	| Not_Found -> ()
        | Exists (witness,tree) ->
            assert ( Array.length witness = witness_size);
	    c := !c + 1 + count tree
	| Not_Exists tree ->
	    c := !c + count tree
      done;
      !c
    in
    count tree in

  if nr_expected <> nr_actual then
    failwith (sprintf
		"verify failed: expected %d words but counted %d in tree"
		nr_expected nr_actual);

  (* Check each word exists in the tree. *)
  List.iter (
    fun word ->
      if not (word_exists word) then
	failwith (sprintf "verify failed: word '%s' missing from tree" word)
  ) words;

  Ancient.detach md;

  (* Garbage collect - good way to check we haven't broken anything. *)
  Gc.compact ();

  printf "Verification succeeded.\n"
