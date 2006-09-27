(* Very basic tests of Ancient module.
 * $Id: test_ancient.ml,v 1.1 2006-09-27 12:07:07 rich Exp $
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

  let chan = open_out "test_ancient.out1" in
  output_data chan data;
  close_out chan;

  let data = Ancient.mark data in
  eprintf "After marking data as ancient ...\n";
  gc_compact ();

  let data = Ancient.follow data in
  eprintf "Number of elements in array = %d\n" (Array.length data);

  let chan = open_out "test_ancient.out2" in
  output_data chan data;
  close_out chan;

  eprintf "After writing out ancient data ...\n";
  gc_compact ()
