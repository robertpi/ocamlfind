(* $Id: fl_metacache.ml,v 1.2 2002/09/22 20:12:32 gerd Exp $
 * ----------------------------------------------------------------------
 *
 *)

open Fl_metascanner

type package =
    { package_name : string;
      package_dir : string;
      package_defs : Fl_metascanner.pkg_definition list;
    }
;;


module Fl_metaentry =
  struct
    type t = package
    type id_t = string
    let id m = m.package_name
  end
;;


module Fl_metastore =
  Fl_topo.Make(Fl_metaentry)
;;


let ocamlpath = ref [];;
let ocamlstdlib = ref "";;

let store = Fl_metastore.create();;
  (* We collect here only nodes, but no relations. First copy [store]
   * and put relations into the copy.
   *)


let init path stdlib =
  ocamlpath := path;
  ocamlstdlib := stdlib
;;


let packages_in_meta_file ~name:package_name ~dir:package_dir ~meta_file () =
  (* Parses the META file whose name is [meta_file]. In [package_name], the
   * name of the main package must be passed. [package_dir] is the
   * directory associated with the package by default (i.e. before
   * it is overriden by the "directory" directive).
   *
   * Returns the [package] records found in this file. The "directory"
   * directive is already applied.
   *)
  let rec flatten_meta pkg_name_prefix pkg_dir (pkg_name_component,pkg_expr) =
    (* Turns the recursive [pkg_expr] into a flat list of [package]s. 
     * [pkg_dir] is the default package directory. [pkg_name_prefix] is
     * the name prefix to prepend to the fully qualified package name, or
     * "". [pkg_name_component] is the local package name.
     *)
    (* Determine the final package directory: *)
    let d =
      try
	lookup "directory" [] pkg_expr.pkg_defs
      with
	  Not_found -> pkg_dir
    in
    let d' =
      if d = "" then
	pkg_dir
      else
	match d.[0] with
          | '^' 
	  | '+' -> Filename.concat
	      !ocamlstdlib
	      (String.sub d 1 (String.length d - 1))
	  | _ -> d
    in
    let p_name = 
      if pkg_name_prefix = "" then 
	pkg_name_component 
      else
	pkg_name_prefix ^ "." ^ pkg_name_component in
    let p = 
      { package_name = p_name;
	package_dir = d';
	package_defs = pkg_expr.pkg_defs
      } in
    p :: (List.flatten 
	    (List.map (flatten_meta p_name d') pkg_expr.pkg_children))
  in

  let ch = open_in meta_file in
  try
    let pkg_expr = Fl_metascanner.parse ch in
    let packages = flatten_meta "" package_dir (package_name, pkg_expr) in
    close_in ch;
    packages
  with
      Failure s ->
	close_in ch;
	failwith ("While parsing '" ^ meta_file ^ "': " ^ s)
    | Stream.Error s ->
	close_in ch;
	failwith ("While parsing '" ^ meta_file ^ "': " ^ s)
    | any ->
	close_in ch;
	raise any
;;


exception No_such_package of string * string


let query package_name =

  let package_name_comps = Fl_split.package_name package_name in
  if package_name_comps = [] then invalid_arg "Fl_package_base.query";
  let main_name = List.hd package_name_comps in

  let process_file_and_lookup package_dir meta_file =
    let packages = 
      packages_in_meta_file main_name package_dir meta_file () in
    List.iter (Fl_metastore.add store) packages;
    try
      List.find
	(fun p -> p.package_name = package_name)
	packages
    with
	Not_found ->
	  raise (No_such_package (package_name, ""))
  in

  let rec run_ocamlpath path =
    match path with
      [] -> raise(No_such_package(package_name, ""))
    | dir :: path' ->
	let package_dir = Filename.concat dir main_name in
	let meta_file_1 = Filename.concat package_dir "META" in
	let meta_file_2 = Filename.concat dir ("META." ^ main_name) in
	if Sys.file_exists meta_file_1 then
	  process_file_and_lookup package_dir meta_file_1
	else
	  if Sys.file_exists meta_file_2 then
	    process_file_and_lookup package_dir (* questionable *)  meta_file_2
	  else
	    run_ocamlpath path'
  in

  try
    Fl_metastore.find store package_name
  with
    Not_found ->
      run_ocamlpath !ocamlpath
;;


exception Package_loop of string
  (* A package is required by itself. The arg is the name of the 
   * package 
   *)

let query_requirements ~preds:predlist package_name =
  (* Part of [requires] implementation: Load all required packages, but
   * do not add relations
   *)
  let m = query package_name in
    (* may raise No_such_package *)
  let r =
    try Fl_metascanner.lookup "requires" predlist m.package_defs
	with Not_found -> ""
  in
  let ancestors = Fl_split.in_words r in
  List.iter
    (fun p ->
      try
	let _ = query p in      (* may raise No_such_package *)
        ()
      with
	  No_such_package(pname,_) ->
	    raise(No_such_package(pname, "Required by `" ^ package_name ^ "'"))
    )
    ancestors;
  ancestors
;;


let add_relations s ancestors package_name =
  (* Part of [requires] implementation: Adds the relations from [package_name]
   * to [ancestors]. Target store is [s].
   *)
  List.iter
    (fun p ->
      try
	Fl_metastore.let_le s p package_name  (* add relation *)
      with
	| Fl_topo.Inconsistent_ordering ->
	    raise(Package_loop p)
	| Not_found ->
	    (* A relation to a package not part of [s]. We ignore it here. *)
	    ()
    )
    ancestors
;;


let add_all_relations predlist s =
  (* Adds all relations for the packages currently defined in [s] *)
  let pkgs = ref [] in
  Fl_metastore.iter_up
    (fun p -> pkgs := p.package_name :: !pkgs)
    s;

  List.iter
    (fun pkg ->
       let pkg_ancestors = query_requirements predlist pkg in
       add_relations s pkg_ancestors pkg
    )
    !pkgs
;;


let requires ~preds:predlist package_name =
  (* returns names of packages required by [package_name], the fully qualified
   * name of the package. It is checked that the packages really exist.
   * [predlist]: list of true predicates
   * May raise [No_such_package] or [Package_loop].
   *)
  let ancestors = query_requirements predlist package_name in
  let store' = Fl_metastore.copy store in     (* work with a copy *)
  add_relations store' ancestors package_name;
  ancestors
;;


let requires_deeply ~preds:predlist package_list =
  (* returns names of packages required by the packages in [package_list],
   * either directly or indirectly.
   * It is checked that the packages really exist.
   * The list of names is sorted topologically; first comes the deepest
   * ancestor.
   * [predlist]: list of true predicates
   * - raises [Not_found] if there is no 'package'
   * - raises [Failure] if some of the ancestors do not exist
   *)

  let done_pkgs = ref [] in
  (* TODO: Use a set *)

  let rec query_packages pkglist =
    match pkglist with
      pkg :: pkglist' ->
	if not(List.mem pkg !done_pkgs) then begin
	  let pkg_ancestors = query_requirements predlist pkg in
	  done_pkgs := pkg :: !done_pkgs;
          query_packages pkg_ancestors
	end;
	query_packages pkglist'
    | [] ->
	()
  in

  (* First query for all packages, such that they are loaded: *)
  query_packages package_list;

  (* Now make a copy of the store, and add the relations: *)
  let store' = Fl_metastore.copy store in
  add_all_relations predlist store';

  (* Finally, iterate through the graph: *)

  let l = ref [] in

  Fl_metastore.iter_up_at
    (fun m ->
      l := m.package_name :: !l)
    store'
    package_list;

  List.rev !l
;;


(**********************************************************************)

(* The following two functions do not use !ocamlpath, because there may
 * be duplicates in it.
 *)

let package_definitions ~search_path package_name =
  (* Return all META files defining this [package_name] that occur in the 
   * directories mentioned in [search_path]
   *)

  let package_name_comps = Fl_split.package_name package_name in
  if package_name_comps = [] then invalid_arg "Fl_package_base.package_definitions";
  let main_name = List.hd package_name_comps in

  let rec run_ocamlpath path =
    match path with
      [] -> []
    | dir :: path' ->
	let package_dir = Filename.concat dir main_name in
	let meta_file_1 = Filename.concat package_dir "META" in
	let meta_file_2 = Filename.concat dir ("META." ^ main_name) in
	if Sys.file_exists meta_file_1 then
	  meta_file_1 :: run_ocamlpath path'
	else
	  if Sys.file_exists meta_file_2 then
	    meta_file_2 :: run_ocamlpath path'
	  else
	    run_ocamlpath path'
  in
  run_ocamlpath search_path
;;


let package_conflict_report_1 identify_dir () =
  let remove_dups_from_path p =
    (* Removes directories which are physically the same from the path [p],
     * and returns the shortened path
     *)

    let dir_identity = Hashtbl.create 20 in

    let rec remove p =
      match p with
	  d :: p' ->
	    begin try
	      let id = identify_dir d in   (* may raise exceptions *)
	      if Hashtbl.mem dir_identity id then
		remove p'
	      else begin
		Hashtbl.add dir_identity id ();
		d :: (remove p')
	      end
	    with error ->
	      (* Don't know anything, so the "directory" remains in the path *)
	      d :: (remove p')
	    end
	| [] ->
	    []
    in

    remove p
  in

  let search_path =
    remove_dups_from_path !ocamlpath in

  Fl_metastore.iter_up
    (fun pkg ->
       (* Check only main packages: *)
       let package_name_comps = Fl_split.package_name pkg.package_name in
       match package_name_comps with
	   [_] ->
	     (* pkg is a main package *)
	     ( let c = package_definitions search_path pkg.package_name in
	       match c with
		   [] 
		 | [_] ->
		     ()
		 | _ ->
		     Printf.eprintf "findlib: [WARNING] Package %s has multiple definitions in %s\n"
		     pkg.package_name
		     (String.concat ", " c)
	     )
	 | _ ->
	     ()
    )
    store;
  flush stderr
;;


let package_conflict_report ?identify_dir () =
  match identify_dir with
      None   -> package_conflict_report_1 (fun s -> s) ()
    | Some f -> package_conflict_report_1 f ()
;;


let load_base() =
  (* Ensures that the cache is completely filled with every package
   * of the system
   *)
  let list_directory d =
    try
      Array.to_list(Sys.readdir d)
    with
	Sys_error msg ->
	  prerr_endline ("findlib: [WARNING] cannot read directory " ^ msg);
	  []
  in

  let process_file main_name package_dir meta_file =
    try
      let _ = Fl_metastore.find store main_name in
      (* Note: If the main package is already loaded into the graph, we 
       * do not even look at the subpackages!
       *)
      ()
    with
	Not_found ->
	  let packages = 
	  try
	    packages_in_meta_file main_name package_dir meta_file () 
	  with
	      Failure s ->
		prerr_endline ("findlib: [WARNING] " ^ s); []
	  in
	  List.iter (Fl_metastore.add store) packages;
	    (* Nothing evil can happen! *)
  in

  let rec run_ocamlpath path =
    match path with
      [] -> ()
    | dir :: path' ->
	let files = list_directory dir in
	List.iter
	  (fun f ->
	     (* If f/META exists: Add package f *)
	     let package_dir = Filename.concat dir f in
	     let meta_file_1 = Filename.concat package_dir "META" in
	     if Sys.file_exists meta_file_1 then
	       process_file f package_dir meta_file_1
	     else
	       (* If f is META.pkgname: Add package pkgname *)
	       if String.length f >= 6 && String.sub f 0 5 = "META." then begin
		 let name = String.sub f 5 (String.length f - 5) in
		 let package_dir = Filename.concat dir name in 
		     (* as in [query] *)
		 let meta_file_2 = package_dir in
		 process_file name package_dir meta_file_2
	       end;
	  )
	  files;
	run_ocamlpath path'
  in

  run_ocamlpath !ocamlpath
;;


let list_packages() =
  load_base();

  let l = ref [] in

  Fl_metastore.iter_up
    (fun m ->
      l := m.package_name :: !l)
    store;

  !l
;;


let package_users ~preds pl =
  (* Check that all packages in [pl] really exist, or raise No_such_package: *)
  List.iter 
    (fun p -> let _ = query p in ())
    pl;
  load_base();
  let store' = Fl_metastore.copy store in
  add_all_relations preds store';

  let l = ref [] in

  Fl_metastore.iter_down_at
    (fun m ->
      l := m.package_name :: !l)
    store'
    pl;

  !l
;;


let module_conflict_report incpath =
  (* Find any *.cmi files occurring twice in (incpath @ package directories).
   *)
  let dir_of_module = Hashtbl.create 100 in
  let dirs = ref [] in

  let examine_dir d = 
    (* If d ends with a slash: remove it *)
    let d' = Fl_split.norm_dir d in
    (* If d' begins with '+': Expand *)
    let d' =
      if d' <> "" && d'.[0] = '+' then
	Filename.concat 
	  !ocamlstdlib 
	  (String.sub d' 1 (String.length d' - 1))
      else
	d'
    in

    (* Is d' new? *)
    if not (List.mem d' !dirs) then begin
      dirs := d' :: !dirs;
      (* Yes: Get all files ending in .cmi *)
      try
	let d_all = Array.to_list(Sys.readdir d') in   (* or Sys_error *)
	let d_cmi = List.filter 
		      (fun n -> Filename.check_suffix n ".cmi") 
		      d_all in
	(* Add the modules to dir_of_module: *)
	List.iter
	  (fun m ->
	     try
	       let entry = Hashtbl.find dir_of_module m in (* or Not_found *)
	       entry := d' :: !entry
	     with
		 Not_found ->
		   Hashtbl.add dir_of_module m (ref [d'])
	  )
	  d_cmi
      with
	  Sys_error msg ->
	    prerr_endline ("findlib: [WARNING] cannot read directory " ^ msg)
    end
  in

  let print_report() =
    Hashtbl.iter
      (fun m dlist ->
	 match !dlist with
	     []
	   | [_] ->
	       ()
	   | _ ->
	       Printf.eprintf "findlib: [WARNING] Interface %s occurs in several directories: %s\n"
		 m
		 (String.concat ", " !dlist)
      )
      dir_of_module
  in

  List.iter examine_dir incpath;
  Fl_metastore.iter_up 
    (fun pkg -> examine_dir pkg.package_dir)
    store;

  print_report();
  flush stderr
;;