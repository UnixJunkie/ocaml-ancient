(* Get the major or minor part of the OCaml version string.
 * This doesn't seem t be present in header files (at least not in 3.08.x).
 *)
type t = Major | Minor
let usage () = failwith "ocaml_version major|minor"
let t =
  if Array.length Sys.argv < 2 then
    usage ()
  else match Sys.argv.(1) with
  | "major" -> Major
  | "minor" -> Minor
  | _ -> usage ()
let ocaml_version = Sys.ocaml_version
let i = String.index ocaml_version '.'
let s =
  match t with
  | Major -> String.sub ocaml_version 0 i
  | Minor ->
      let j =
	try String.index_from ocaml_version (i+1) '.'
	with Not_found -> String.length ocaml_version in
      String.sub ocaml_version (i+1) (j-i-1)
let s = string_of_int (int_of_string s) ;;
print_endline s
