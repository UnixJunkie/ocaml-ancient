(* Create shared dictionary. *)

open Test_ancient_dict
open Printf
open Unix

let argv = Array.to_list Sys.argv

let wordsfile, datafile, baseaddr =
  match argv with
  | [_; wordsfile; datafile; baseaddr] ->
      let baseaddr = Nativeint.of_string baseaddr in
      wordsfile, datafile, baseaddr
  | _ ->
      failwith (sprintf "usage: %s wordsfile datafile baseaddr"
		  Sys.executable_name)

let md =
  let fd = openfile datafile [O_RDWR; O_TRUNC; O_CREAT] 0o644 in
  Ancient.attach fd baseaddr

(* Tree used to store the words.  This is stupid and inefficient
 * but it is here to demonstrate the 'Ancient' module, not good use
 * of trees.
 *)

let arraysize = 256 (* one element for each character *)

let tree : tree array = Array.make arraysize Not_Found

let add_to_tree word =
  let len = String.length word in
  if len > 0 then (
    let tree = ref tree in
    for i = 0 to len-2; do
      let c = word.[i] in
      let c = Char.code c in
      match (!tree).(c) with
      | Not_Found ->
	  (* Allocate more tree. *)
	  let tree' = Array.make arraysize Not_Found in
	  (!tree).(c) <- Not_Exists tree';
	  tree := tree'
      | Exists (witness, tree') ->
        assert ( Array.length witness = witness_size);
	tree := tree'
      | Not_Exists tree' ->
	  tree := tree'
    done;

    (* Final character. *)
    let c = word.[len-1] in
    let c = Char.code c in
    match (!tree).(c) with
    | Not_Found ->
	(!tree).(c) <- Exists (Array.make witness_size 0, Array.make arraysize Not_Found)
    | Exists (witness, _) ->
      assert ( Array.length witness = witness_size);
      () (* same word added twice *)
    | Not_Exists tree' ->
	(!tree).(c) <- Exists (Array.make witness_size 0,tree')
  )

let () =
  (* Read in the words and put them in the tree. *)
  let chan = open_in wordsfile in
  let count = ref 0 in
  let rec loop () =
    let word = input_line chan in
    add_to_tree word;
    incr count;
    loop ()
  in
  (try loop () with End_of_file -> ());
  close_in chan;

  printf "Added %d words to the tree.\n" !count;

  printf "Sharing tree in data file ...\n%!";
  ignore (Ancient.share md 0 tree);

  (* Perform a full GC and compact, which is a good way to see
   * if we've trashed the OCaml heap in some way.
   *)
  Array.fill tree 0 arraysize Not_Found;
  printf "Garbage collecting ...\n%!";
  Gc.compact ();

  printf "Detaching file and finishing.\n%!";

  Ancient.detach md
