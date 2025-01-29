
type witness = int array
type tree = Not_Found
          | Exists of witness * tree array
          | Not_Exists of tree array;;

let witness_size = 0
