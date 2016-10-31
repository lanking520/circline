type binop =
  Add
| Sub
| Mult
| Div
| Equal
| Neq
| Less
| Leq
| Greater
| Geq
| And
| Or
| Mod

type unop =
  Sub
| Not

type num =
  Num_Int of int
| Num_Float of float

type primitive =
  Int_t
| Float_t
| String_t

type expr =
    Num_Lit of num
| 	Binop of expr * binop * expr
|  	Unop of unop * expr
|   Id of string
|   Assign of string * expr
|   ListP of expr list

(* Statements *)
type stmt =
  Expr of expr     (* set foo = bar + 3 *)

(* Program entry point *)
type program = stmt list
