(* Very basic tests of Ancient module shared functionality.
 * $Id: test_ancient_shared.ml,v 1.2 2006-09-27 18:39:44 rich Exp $
 *)

open Printf

type item = {
  name : string;
  dob : string;
  address : string;
  phone : string option;
  marital_status : marital_status;
  id : int;
}
and marital_status = Single | Married | Divorced

let gc_compact () =
  eprintf "compacting ... %!";
  Gc.compact ();
  let stat = Gc.stat () in
  let live_words = stat.Gc.live_words in
  eprintf "live words = %d (%d MB)\n%!"
    live_words (live_words * 8 / 1024 / 1024)

let random_string () =
  let n = 1 + Random.int 20 in
  let str = String.create n in
  for i = 0 to n-1 do
    let c = 97 + Random.int 26 in
    let c = Char.chr c in
    str.[i] <- c
  done;
  str

let random_string_option () =
  if Random.int 3 = 1 then None else Some (random_string ())

let random_marital_status () =
  match Random.int 3 with
  | 0 -> Single
  | 1 -> Married
  | _ -> Divorced

let rec output_data chan data =
  let n = Array.length data in
  for i = 0 to n-1; do
    output_item chan data.(i)
  done

and output_item chan item =
  fprintf chan "id = %d\n%!" item.id;
  fprintf chan "\tname = %s\n%!" item.name;
  fprintf chan "\tdob = %s\n%!" item.dob;
  fprintf chan "\taddress = %s\n%!" item.address;
  fprintf chan "\tphone = %s\n%!"
    (match item.phone with
     | None -> "None"
     | Some str -> "Some " ^ str);
  fprintf chan "\tmarital_status = %s\n%!"
    (string_of_marital_status item.marital_status)

and string_of_marital_status status =
  match status with
  | Single -> "Single"
  | Married -> "Married"
  | Divorced -> "Divorced"

let () =
  match List.tl (Array.to_list Sys.argv) with
  | ["read"; share_filename; print_filename] ->
      (* Read data in filename and print. *)
      let fd = Unix.openfile share_filename [Unix.O_RDWR] 0 in
      let md = Ancient.attach fd in

      eprintf "After attaching %s ...\n" share_filename;
      gc_compact ();

      let data : item array Ancient.ancient = Ancient.get md 0 in
      eprintf "After getting ...\n";
      gc_compact ();

      let chan = open_out print_filename in
      output_data chan (Ancient.follow data);
      close_out chan;

      Ancient.detach md;
      eprintf "After detaching ...\n";
      gc_compact ()

  | ["write"; share_filename; print_filename] ->
      (* Generate random data and write to filename, also print it. *)
      eprintf "Before allocating data on OCaml heap ...\n";
      gc_compact ();
      let data =
	Array.init 100000 (
	  fun id ->
	    { id = id;
	      name = random_string ();
	      dob = random_string ();
	      address = random_string ();
	      phone = random_string_option ();
	      marital_status = random_marital_status () }
	) in
      eprintf "After allocating data on OCaml heap ...\n";
      gc_compact ();

      let chan = open_out print_filename in
      output_data chan data;
      close_out chan;

      let fd =
	Unix.openfile share_filename
	  [Unix.O_CREAT;Unix.O_TRUNC;Unix.O_RDWR] 0o644 in
      let md = Ancient.attach fd in

      ignore (Ancient.share md 0 data);
      eprintf "After sharing data to %s ...\n" share_filename;
      gc_compact ();

      Ancient.detach md;
      eprintf "After detaching ...\n";
      gc_compact ()

  | _ ->
      failwith "test_ancient_shared"


