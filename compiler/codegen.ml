(* Code generation: translate takes a semantically checked AST and
produces LLVM IR

LLVM tutorial: Make sure to read the OCaml version of the tutorial

http://llvm.org/docs/tutorial/index.html

Detailed documentation on the OCaml LLVM library:

http://llvm.moe/
http://llvm.moe/ocaml/

*)

module L = Llvm
module A = Cast

module StringMap = Map.Make(String)

let context = L.global_context ()
let llctx = L.global_context ()
let customM = L.MemoryBuffer.of_file "utils.bc"
let llm = Llvm_bitreader.parse_bitcode llctx customM
let the_module = L.create_module context "Circline"

let i32_t  = L.i32_type  context
and f_t  = L.double_type context
and i8_t   = L.i8_type   context
and i1_t   = L.i1_type   context
and str_t  = L.pointer_type (L.i8_type context)
and void_t = L.void_type context

(*
  Node Definition Structure 
  {
    int    id,         // 0
    int    type,       // 1
    int    val_int,    // 0
    double val_double, // 1
    bool   val_bool,   // 2
    i8*    val_str     // 3
  }
*)
(* let node_t = (
  let typ = L.named_struct_type context "struct_node" in
  ignore(L.struct_set_body typ [| i32_t; i32_t; f_t; i1_t; str_t |] false);
  typ
) *)

let node_t = L.pointer_type (match L.type_by_name llm "struct.Node" with
    None -> raise (Failure "struct.Node doesn't defined!")
  | Some x -> x)

let graph_t = L.pointer_type (match L.type_by_name llm "struct.Graph" with
    None -> raise (Failure "struct.Graph doesn't defined!")
  | Some x -> x)

let list_t = L.pointer_type (match L.type_by_name llm "struct.List" with
    None -> raise (Failure "Option.get")
  | Some x -> x)

let ltype_of_typ = function
    A.Int_t -> i32_t
  | A.Float_t -> f_t
  | A.Bool_t -> i1_t
  | A.String_t -> str_t
  | A.Void_t -> void_t
  | A.Node_t -> node_t
  | A.List_Int_t -> list_t
  | A.Graph_t -> graph_t
  | _ -> raise (Failure ("Type Not Found!"))

let int_zero = L.const_int i32_t 0
and float_zero = L.const_float f_t 0.
and bool_false = L.const_int i1_t 0
and bool_true = L.const_int i1_t 1
and str_null = L.const_null str_t

let get_default_value_of_type = function
  | A.Int_t as t -> L.const_int (ltype_of_typ t) 0
  | A.Bool_t as t -> L.const_int (ltype_of_typ t) 0
  | A.Float_t as t-> L.const_float (ltype_of_typ t) 0.
  | t-> L.const_null (ltype_of_typ t)

(*
================================================================
  Node Related Methods
================================================================
*)

(* let get_node_val_index_by_type typ =
  match typ with
  | A.Int_t -> 1
  | A.Float_t -> 2
  | A.Bool_t -> 3
  | A.String_t -> 4
  | _ -> raise (Failure("Unsupported Node Values ..."))
  

let get_node_id node_ptr llbuilder =
  let val_ptr = L.build_struct_gep node_ptr 0 "node_id_ptr_tmp" llbuilder in
  L.build_load val_ptr "node_id_tmp" llbuilder

let get_node_value node_ptr typ llbuilder =
  let idx = get_node_val_index_by_type typ in
  let val_ptr = L.build_struct_gep node_ptr idx "node_val_ptr_tmp" llbuilder in
  L.build_load val_ptr "node_val_tmp" llbuilder

let set_node_value node_ptr nval typ llbuilder =
  let idx = get_node_val_index_by_type typ in
  let a_ptr = L.build_struct_gep node_ptr idx "node_val_ptr_tmp" llbuilder in
  (ignore(L.build_store nval a_ptr llbuilder); node_ptr) *)

(* let create_node (id, nval, typ) llbuilder =
  let node_ptr = L.build_malloc node_t "node_ptr_tmp" llbuilder in
  let id_ptr = L.build_struct_gep node_ptr 0 "node_id_ptr_tmp" llbuilder in
  (
    ignore(L.build_store (L.const_int i32_t id) id_ptr llbuilder);
    List.fold_left (fun _ t -> (
      if t = typ
      then (set_node_value node_ptr nval t llbuilder)
      else (set_node_value node_ptr (get_default_value_of_type t) t llbuilder)
    )) node_ptr [A.Int_t; A.Float_t; A.Bool_t; A.String_t]
  ) *)

(*
================================================================
  Declare printf(), which the print built-in function will call
================================================================
*)
let printf_t = L.var_arg_function_type i32_t [| str_t |]
let printf_func = L.declare_function "printf" printf_t the_module
let codegen_print llbuilder el =
  L.build_call printf_func (Array.of_list el) "printf" llbuilder

let codegen_string_lit s llbuilder =
  L.build_global_stringptr s "str_tmp" llbuilder

(*
================================================================
  Node
================================================================
*)
let create_node_t  = L.function_type node_t [| i32_t; i32_t; i32_t; f_t; i1_t; str_t |]
let create_node_f  = L.declare_function "createNode" create_node_t the_module
let create_node (id, typ, nval) llbuilder =
  let actuals = [| id; int_zero; int_zero; float_zero; bool_false; str_null |] in
  let (typ_val, loc) = (match typ with
    | A.Int_t -> (0, 2)
    | A.Float_t -> (1, 3)
    | A.Bool_t -> (2, 4)
    | A.String_t -> (3, 5)
    | A.Void_t | A.Null_t -> (-1, 2)
    | _ -> raise (Failure "Unsupported node value type")
  ) in (
    ignore( Array.set actuals 1 (L.const_int i32_t typ_val) );
    ignore( Array.set actuals loc nval );
    L.build_call create_node_f actuals "node" llbuilder
  )


let create_list_t  = L.function_type list_t [| i32_t |]
let create_list_f  = L.declare_function "createList" create_list_t the_module
let create_list typ llbuilder =
  let actuals = [|int_zero|] in
  let typ_val = (match typ with
    | A.Int_t -> 0
    (* | A.Float_t -> (1, 3) *)
    (* | A.Bool_t -> (2, 4) *)
    (* | A.String_t -> (3, 5) *)
    | _ -> raise (Failure "Unsupported list value type")
  ) in (
    L.build_call create_list_f actuals "createList" llbuilder
  )

let add_list_t  = L.function_type list_t [| list_t; i32_t |]
let add_list_f  = L.declare_function "addList" add_list_t the_module
let add_list data l_ptr llbuilder =
  let actuals = [|str_null; int_zero|] in
(*   let typ_val = (match typ with
    | A.Int_t -> 0
    (* | A.Float_t -> (1, 3) *)
    | A.Bool_t -> (2, 4)
    (* | A.String_t -> (3, 5) *)
    | _ -> raise (Failure "Unsupported list value type")
  ) in ( *)
    ignore(Array.set actuals 0 l_ptr);
    ignore(Array.set actuals 1 data);
    (L.build_call add_list_f actuals "addList" llbuilder)

let rec add_multi_elements_list l_ptr llbuilder = function 
  | [] -> l_ptr
  | h :: tl -> add_multi_elements_list (add_list h l_ptr llbuilder) llbuilder tl


let print_node_t  = L.function_type i32_t [| node_t |]
let print_node_f  = L.declare_function "printNode" print_node_t the_module
let print_node node llbuilder =
  L.build_call print_node_f [| node |] "printNode" llbuilder

let print_list_t  = L.function_type i32_t [| list_t |]
let print_list_f  = L.declare_function "printList" print_list_t the_module
let print_list l llbuilder =
  L.build_call print_list_f [| l |] "printList" llbuilder

(*
================================================================
  Graph
================================================================
*)
(* Create a new empty grpah *)
let create_graph_t  = L.function_type graph_t [| |]
let create_graph_f  = L.declare_function "createGraph" create_graph_t the_module
let create_graph llbuilder =
  L.build_call create_graph_f [| |] "graph" llbuilder

(* Add a new node to graph *)
let graph_add_node_t = L.function_type i32_t [| graph_t; node_t |]
let graph_add_node_f = L.declare_function "graphAddNode" graph_add_node_t the_module
let graph_add_node graph node llbuilder =
  L.build_call graph_add_node_f [| graph; node |] "addNodeRes" llbuilder

(* Add a new edge to graph *)
let graph_add_edge_t = L.function_type i32_t
  [| graph_t; node_t; node_t; i32_t; i32_t; f_t; i1_t; str_t |]
let graph_add_edge_f = L.declare_function "graphAddEdge" graph_add_edge_t the_module
let graph_add_edge graph (sour, dest) op (typ, vals) llbuilder =
  let actuals = [| graph; sour; dest; int_zero; int_zero; float_zero; bool_false; str_null |] in
  let actuals_r = [| graph; dest; sour; int_zero; int_zero; float_zero; bool_false; str_null |] in
  let (typ_val, loc) = (match typ with
    | A.Int_t -> (0, 4)
    | A.Float_t -> (1, 5)
    | A.Bool_t -> (2, 6)
    | A.String_t -> (3, 7)
    | A.Void_t | A.Null_t -> (-1, 4)
    | _ -> raise (Failure "Unsupported edge value type")
  ) in (
    ignore( Array.set actuals 3 (L.const_int i32_t typ_val) );
    ignore( Array.set actuals loc vals );
    match op with
    | A.Right_Link -> L.build_call graph_add_edge_f actuals "addRightEdgeRes" llbuilder
    | A.Left_Link -> L.build_call graph_add_edge_f actuals_r "addLeftEdgeRes" llbuilder
    | A.Double_Link -> (
        ignore(L.build_call graph_add_edge_f actuals "addRightEdgeRes" llbuilder);
        L.build_call graph_add_edge_f actuals_r "addLeftEdgeRes" llbuilder
      )
  )  

(* Print out the graph *)
let print_graph_t  = L.function_type i32_t [| graph_t |]
let print_graph_f  = L.declare_function "printGraph" print_graph_t the_module
let print_graph graph llbuilder =
  L.build_call print_graph_f [| graph |] "printGraph" llbuilder

(*
================================================================
  Casting
================================================================
*)
let int_to_float llbuilder v = L.build_sitofp v f_t "tmp" llbuilder

(*
================================================================
        context_funcs_vars
================================================================
*)
let context_funcs_vars = Hashtbl.create 50
let print_hashtbl tb =
  print_endline (Hashtbl.fold (fun k _ m -> (k^", "^m)) tb "")

(*
================================================================
        Main Codegen Function
================================================================
*)
let translate program =
  (* Define each function (arguments and return type) so we can call it *)
  let function_decls =
    let function_decl m fdecl =
      let name = fdecl.A.name
      and formal_types =
	       Array.of_list (List.map (fun (A.Formal(t, _)) -> ltype_of_typ t) fdecl.A.args)
      in
      let ftype = L.var_arg_function_type (ltype_of_typ fdecl.A.returnType) formal_types in
      StringMap.add name (L.define_function name ftype the_module, fdecl) m in
    List.fold_left function_decl StringMap.empty program in

  (* Fill in the body of the given function *)
  let build_function_body fdecl =
    let get_var_name fname n = (fname ^ "." ^ n) in
    let (the_function, _) = StringMap.find fdecl.A.name function_decls in
    (* let bb = L.append_block context "entry" the_function in *)
    let builder = L.builder_at_end context (L.entry_block the_function) in

    (* Construct the function's "locals": formal arguments and locally
       declared variables.  Allocate each on the stack, initialize their
       value, if appropriate, and remember their values in the "locals" map *)
    let _ =
      let add_to_context locals =
        ignore(Hashtbl.add context_funcs_vars fdecl.A.name locals);
        (* ignore(print_hashtbl context_funcs_vars); *)
        locals
      in
      let add_formal m (A.Formal(t, n)) p =
        let n' = get_var_name fdecl.A.name n in
        let local = L.define_global n' (get_default_value_of_type t) the_module in
        ignore (L.build_store p local builder);
        (* L.set_value_name n p;
    	  let local = L.build_alloca (ltype_of_typ t) n builder in
    	    ignore (L.build_store p local builder); *)
    	  StringMap.add n' (local, t) m
      in

      let add_local m (A.Formal(t, n)) =
        let n' = get_var_name fdecl.A.name n in
      	let local_var = L.define_global n' (get_default_value_of_type t) the_module in
      	(* let local_var = L.build_alloca (ltype_of_typ t) n builder in *)
        StringMap.add n' (local_var, t) m
      in

      let formals = List.fold_left2 add_formal StringMap.empty fdecl.A.args
          (Array.to_list (L.params the_function)) in
      add_to_context (List.fold_left add_local formals fdecl.A.locals)
    in

    (* Return the value for a variable or formal argument *)
    (* let lookup n = StringMap.find n local_vars
    in *)
    let lookup n =
      let get_parent_func_name fname =
        let (_, fdecl) = StringMap.find fname function_decls in
        fdecl.A.pname
      in
      let rec aux n fname = (
        try StringMap.find (get_var_name fname n) (Hashtbl.find context_funcs_vars fname)
        with Not_found -> (
          if fname = "main" then
            (raise (Failure("Local Variable not found...")))
          else
            (aux n (get_parent_func_name fname))
        )
      ) in
      aux n fdecl.A.name
    in

    (* Construct code for an expression; return its value *)
    let handle_binop e1 op e2 dtype llbuilder =
      (* Generate llvalues from e1 and e2 *)

      let float_ops op e1 e2 =
        match op with
          A.Add     -> L.build_fadd e1 e2 "flt_addtmp" llbuilder
        | A.Sub     -> L.build_fsub e1 e2 "flt_subtmp" llbuilder
        | A.Mult    -> L.build_fmul e1 e2 "flt_multmp" llbuilder
        | A.Div     -> L.build_fdiv e1 e2 "flt_divtmp" llbuilder
        | A.Mod     -> L.build_frem e1 e2 "flt_sremtmp" llbuilder
        | A.Equal   -> L.build_fcmp L.Fcmp.Oeq e1 e2 "flt_eqtmp" llbuilder
        | A.Neq     -> L.build_fcmp L.Fcmp.One e1 e2 "flt_neqtmp" llbuilder
        | A.Less    -> L.build_fcmp L.Fcmp.Ult e1 e2 "flt_lesstmp" llbuilder
        | A.Leq     -> L.build_fcmp L.Fcmp.Ole e1 e2 "flt_leqtmp" llbuilder
        | A.Greater -> L.build_fcmp L.Fcmp.Ogt e1 e2 "flt_sgttmp" llbuilder
        | A.Geq     -> L.build_fcmp L.Fcmp.Oge e1 e2 "flt_sgetmp" llbuilder
        | _ -> raise (Failure("Unrecognized float binop opreation!"))
      in

      (* chars are considered ints, so they will use int_ops as well*)
      let int_ops op e1 e2 =
        match op with
          A.Add     -> L.build_add e1 e2 "addtmp" llbuilder
        | A.Sub     -> L.build_sub e1 e2 "subtmp" llbuilder
        | A.Mult    -> L.build_mul e1 e2 "multmp" llbuilder
        | A.Div     -> L.build_sdiv e1 e2 "divtmp" llbuilder
        | A.Mod     -> L.build_srem e1 e2 "sremtmp" llbuilder
        | A.Equal   -> L.build_icmp L.Icmp.Eq e1 e2 "eqtmp" llbuilder
        | A.Neq     -> L.build_icmp L.Icmp.Ne e1 e2 "neqtmp" llbuilder
        | A.Less    -> L.build_icmp L.Icmp.Slt e1 e2 "lesstmp" llbuilder
        | A.Leq     -> L.build_icmp L.Icmp.Sle e1 e2 "leqtmp" llbuilder
        | A.Greater -> L.build_icmp L.Icmp.Sgt e1 e2 "sgttmp" llbuilder
        | A.Geq     -> L.build_icmp L.Icmp.Sge e1 e2 "sgetmp" llbuilder
        | A.And     -> L.build_and e1 e2 "andtmp" llbuilder
        | A.Or      -> L.build_or  e1 e2 "ortmp" llbuilder
        | _ -> raise (Failure("Unrecognized int binop opreation!"))
      in
      let type_handler d = match d with
        | A.Float_t -> float_ops op e1 e2
        | A.Bool_t
        | A.Int_t -> int_ops op e1 e2
        | _ -> raise (Failure("Unrecognized binop data type!"))
      in (type_handler dtype,
        match op with
        | A.Add | A.Sub | A.Mult | A.Div | A.Mod -> dtype
        | _ -> A.Bool_t
      )
    in
    let rec expr builder = function
	      A.Num_Lit(A.Num_Int i) -> (L.const_int i32_t i, A.Int_t)
      | A.Num_Lit(A.Num_Float f) -> (L.const_float f_t f, A.Float_t)
      | A.Bool_lit b -> (L.const_int i1_t (if b then 1 else 0), A.Bool_t)
      | A.String_Lit s -> (codegen_string_lit s builder, A.String_t)
      | A.Noexpr -> (L.const_int i32_t 0, A.Void_t)
      | A.Null -> (L.const_int i32_t 0, A.Null_t)
      | A.Node(id, e) ->
          let (nval, typ) = expr builder e in
          (create_node (L.const_int i32_t id, typ, nval) builder, A.Node_t)
      | A.ListP(ls) -> 
          let l_ptr_type = create_list A.Int_t builder, A.List_Int_t in 
            add_multi_elements_list (fst l_ptr_type) builder (List.map fst (List.map (expr builder) ls)), (snd l_ptr_type) 
      | A.Graph_Link(left, op, right, edges) ->
          let gh = create_graph builder in
          let (ln, _) = expr builder left in
          let (rn, rn_type) = expr builder right in
          let (el, el_type) = expr builder edges in (
            ignore(graph_add_node gh ln builder);
            ignore(match (rn_type, el_type) with
              | (A.Null_t, _) -> ()
              | (A.Node_t, _) -> (
                  ignore(graph_add_node gh rn builder);
                  ignore(graph_add_edge gh (ln, rn) op (el_type, el) builder);
                )
              | _ -> raise (Failure "Graph Link Under build...")
            );
            (gh, A.Graph_t)
          )
      | A.Id s ->
          let (var, typ) = lookup s in
          (L.build_load var s builder, typ)
      | A.Binop (e1, op, e2) ->
        let (e1', t1) = expr builder e1
        and (e2', t2) = expr builder e2 in
        (* Handle Automatic Binop Type Converstion *)
        (match (t1, t2) with
          | ( t1, t2) when t1 = t2 -> handle_binop e1' op e2' t1 builder
          | ( A.Int_t, A.Float_t) ->
              handle_binop (int_to_float builder e1') op e2' A.Float_t builder
          | ( A.Float_t, A.Int_t ) ->
              handle_binop e1' op (int_to_float builder e2') A.Float_t builder
          | _ -> raise (Failure ("Unsuported Binop Type!"))
        )
      | A.Unop(op, e) ->
      	  let (e', typ) = expr builder e in
      	  ((match op with
      	    A.Neg     -> if typ = A.Int_t then L.build_neg else L.build_fneg
          | A.Not     -> L.build_not) e' "tmp" builder, typ)
      | A.Assign (s, e) ->
          let (e', etyp) = expr builder e in
          let (var, typ) = lookup s in
          (( match (etyp, typ) with
            | (t1, t2) when t1 = t2 -> ignore (L.build_store e' var builder); e'
            | (A.Int_t, A.Float_t) -> let e' = (int_to_float builder e') in ignore (L.build_store e' var builder); e'
            | _ -> raise (Failure("Assign Type inconsist"))
          ), typ)
      | A.Call ("print", el) ->
          let print_expr e = 
            let (eval, etyp) = expr builder e in (
              match etyp with
              | A.Int_t
              | A.Bool_t -> ignore(codegen_print builder [(codegen_string_lit "%d\n" builder); eval])
              | A.Float_t -> ignore(codegen_print builder [(codegen_string_lit "%f\n" builder); eval])
              | A.String_t -> ignore(codegen_print builder [(codegen_string_lit "%s\n" builder); eval])
              | A.Node_t -> ignore(print_node eval builder)
              | A.List_Int_t -> ignore(print_list eval builder)
              | A.Graph_t -> ignore(print_graph eval builder)
              | _ -> raise (Failure("Unsupported type for print..."))
          ) in List.iter print_expr el; (L.const_int i32_t 0, A.Void_t)
      | A.Call ("printf", el) ->
          (codegen_print builder (List.map 
            (fun e -> (let (eval, _) = expr builder e in eval))
            el), A.Void_t)
      | A.Call (f, act) ->
         let (fdef, fdecl) = StringMap.find f function_decls in
      	 let actuals = List.rev (List.map
          (fun e -> (let (eval, _) = expr builder e in eval)) (List.rev act)) in
      	 let result = (match fdecl.A.returnType with A.Void_t -> ""
                                                   | _ -> f ^ "_result") in
         (L.build_call fdef (Array.of_list actuals) result builder, fdecl.A.returnType)
      | _ -> (L.const_int i32_t 0, A.Void_t)
    in

    (* Invoke "f builder" if the current block doesn't already
       have a terminal (e.g., a branch). *)
    let add_terminal builder f =
      match L.block_terminator (L.insertion_block builder) with
	      Some _ -> ()
      | None -> ignore (f builder) in

    (* Build the code for the given statement; return the builder for
       the statement's successor *)
    let rec stmt builder = function
      | A.Expr e -> ignore (expr builder e); builder
      | A.Return e ->
          ignore (
            let (ev, et) = expr builder e in
            match (fdecl.A.returnType, et) with
  	          (A.Void_t, _) -> L.build_ret_void builder
  	        | (t1, t2) when t1 = t2 -> L.build_ret ev builder
            | (A.Float_t, A.Int_t) -> L.build_ret (int_to_float builder ev) builder
            | _ -> raise (Failure("Return Type Doesn't match..."))
          ); builder
      | A.If (predicate, then_stmt, else_stmt) ->
         let (bool_val, _) = expr builder predicate in
      	 let merge_bb = L.append_block context "merge" the_function in

      	 let then_bb = L.append_block context "then" the_function in
      	 add_terminal (
             List.fold_left stmt (L.builder_at_end context then_bb) then_stmt
           ) (L.build_br merge_bb);

      	 let else_bb = L.append_block context "else" the_function in
         add_terminal (
             List.fold_left stmt (L.builder_at_end context else_bb) else_stmt
           ) (L.build_br merge_bb);

      	 ignore (L.build_cond_br bool_val then_bb else_bb builder);
      	 L.builder_at_end context merge_bb

      | A.While (predicate, body) ->
      	  let pred_bb = L.append_block context "while" the_function in
      	  ignore (L.build_br pred_bb builder);

      	  let body_bb = L.append_block context "while_body" the_function in
      	  add_terminal (
              List.fold_left stmt (L.builder_at_end context body_bb) body
            ) (L.build_br pred_bb);

      	  let pred_builder = L.builder_at_end context pred_bb in
      	  let (bool_val, _) = expr pred_builder predicate in

      	  let merge_bb = L.append_block context "merge" the_function in
      	  ignore (L.build_cond_br bool_val body_bb merge_bb pred_builder);
      	  L.builder_at_end context merge_bb

      | A.For (e1, e2, e3, body) -> List.fold_left stmt builder
	       ( [A.Expr e1 ; A.While (e2, body @ [A.Expr e3]) ] )
    in

    (* Build the code for each statement in the function *)
    let builder = List.fold_left stmt builder fdecl.A.body in

    (* Add a return if the last block falls off the end *)
    add_terminal builder (match fdecl.A.returnType with
        A.Void_t -> L.build_ret_void
      | A.Int_t as t -> L.build_ret (L.const_int (ltype_of_typ t) 0)
      | A.Bool_t as t -> L.build_ret (L.const_int (ltype_of_typ t) 0)
      | A.Float_t as t-> L.build_ret (L.const_float (ltype_of_typ t) 0.)
      | t-> L.build_ret (L.const_null (ltype_of_typ t))
    )
  in

  List.iter build_function_body (List.rev program);

  the_module
