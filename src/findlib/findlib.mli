(* $Id: findlib.mli,v 1.7 2002/04/26 15:45:22 gerd Exp $
 * ----------------------------------------------------------------------
 *
 *)

(** The official findlib interface *)

exception No_such_package of string * string
  (** First arg is the package name not found, second arg contains additional
   * info for the user
   *)

exception Package_loop of string
  (** A package is required by itself. The arg is the name of the 
   * package 
   *)


val init : 
      ?env_ocamlpath: string ->
      ?env_ocamlfind_destdir: string ->
      ?env_ocamlfind_metadir: string ->
      ?env_ocamlfind_commands: string ->
      ?env_camllib: string ->
      ?env_ldconf: string ->
      ?config: string -> 
      unit ->
	unit
  (** Initializes the library from the configuration file and the environment. 
   * By default the
   * function reads the file specified at compile time, but you can also
   * pass a different file name in the [config] argument.
   *   Furthermore, the environment variables OCAMLPATH, OCAMLFIND_DESTDIR, 
   * OCAMLFIND_COMMANDS, and CAMLLIB are interpreted. By default, the function takes
   * the values found in the environment, but you can pass different values
   * using the [env_*] arguments. By setting these values to empty strings 
   * they are no longer considered.
   *     The result of the initialization is determined as follows:
   * - The default installation directory is the env variable OCAMLFIND_DESTDIR
   *   (if present and non-empty), and otherwise the variable [destdir] of the
   *   configuration file.
   * - The installation directory for META files is read from the env 
   *   variable OCAMLFIND_METADIR (if present and non-empty), and otherwise
   *   from the variable [metadir] of the configuration file, and otherwise
   *   no such directory is used.
   *   The special value ["none"] turns this feature off.
   * - The search path is the concatenation of the env variable OCAMLPATH
   *   and the variable [path] of the config file
   * - The executables of (ocamlc|ocamlopt|ocamlcp|ocamlmktop) are determined
   *   as follows: if the env variable OCAMLFIND_COMMANDS is set and non-empty,
   *   its contents specify the executables. Otherwise, if the config file
   *   variables [ocamlc], [ocamlopt], [ocamlcp] and [ocamlmktop] are set,
   *   their contents specify the executables. Otherwise, the obvious default
   *   values are chosen: ["ocamlc"] for [ocamlc], ["ocamlopt"] for [ocamlopt],
   *   and so on.
   * - The directory of the standard library is the value of the environment
   *   variable CAMLLIB (or OCAMLLIB), or if unset or empty, the value of
   *   the configuration variable [stdlib], or if unset the built-in location
   * - The [ld.conf] file (configuring the dynamic loader) is the value of
   *   the environment variable OCAMLFIND_LDCONF, or if unset or empty, the
   *   value of the configuration variable [ldconf], or if unset the
   *   built-in location.
   *)


val init_manually : 
      ?ocamlc_command: string ->       (* default: "ocamlc"     *)
      ?ocamlopt_command: string ->     (* default: "ocamlopt"   *)
      ?ocamlcp_command: string ->      (* default: "ocamlcp"    *)
      ?ocamlmktop_command: string ->   (* default: "ocamlmktop" *)
      ?ocamldep_command: string ->     (* default: "ocamldep"   *)
      ?ocamlbrowser_command: string -> (* default: "ocamlbrowser"   *)
      ?ocamldoc_command: string ->     (* default: "ocamldoc"   *)
      ?stdlib: string ->               (* default: taken from Findlib_config *)
      ?ldconf: string ->
      install_dir: string ->
      meta_dir: string ->
      search_path: string list ->
      unit ->
	unit
  (** This is an alternate way to initialize the library directly. 
   * Environment variables and configuration files are ignored.
   *)


val default_location : unit -> string
  (** Get the default installation directory for packages *)

val meta_directory : unit -> string
  (** Get the META installation directory for packages.
   * Returns [""] if no such directory is configured.
   *)

val search_path : unit -> string list
  (** Get the search path for packages *)

val command : [ `ocamlc | `ocamlopt | `ocamlcp | `ocamlmktop | `ocamldep
	      | `ocamlbrowser | `ocamldoc
	      ] -> 
              string
  (** Get the name/path of the executable *)

val ocaml_stdlib : unit -> string
  (** Get the directory of the standard library *)

val ocaml_ldconf : unit -> string
  (** Get the file name of [ld.conf] *)

val package_directory : string -> string
  (** Get the absolute path of the directory where the given package is
   * stored.
   *
   * Raises [No_such_package] if the package cannot be found.
   *)


val package_property : string list -> string -> string -> string
  (** [package_property predlist pkg propname]:
   * Looks up the property [propname] of package [pkg] under the assumption
   * that the predicates in [predlist] are true.
   *
   * Raises [No_such_package] if the package, and [Not_found] if the property
   * cannot be found.
   *
   * EXAMPLES:
   * - [package_property [] "p" "requires":]
   *   get the value of the [requires] clause of package [p]
   * - [package_property [ "mt"; "byte" ] "p" "archive":]
   *   get the value of the [archive] property of package [p] for multi-
   *   threaded bytecode applications.
   *)

val package_ancestors : string list -> string -> string list
  (** [package_ancestors predlist pkg:]
   * Determines the direct ancestors of package [pkg] under the assumption
   * that the predicates in [predlist] are true, i.e. the names of the
   * packages required by [pkg].
   * The returned list is unsorted.
   *
   * Raises [No_such_package] if the package [pkg] or one of its ancestors
   * could not be found.
   *)

val package_deep_ancestors : string list -> string list -> string list
  (** [package_deep_ancestors predlist pkglist:]
   * determines the list of direct or indirect ancestors of the packages
   * named in [pkglist] under the assumption that the predicates in [predlist]
   * are true. 
   *
   * The returned list is topologically sorted: The first element is the
   * deepest ancestor; the last element is one of [pkglist].
   *
   * Raises [No_such_package] if one of the packages in [pkglist] or one of
   * the ancestors cannot be found. Raises [Package_loop] if there is a
   * cyclic dependency.
   *)

val resolve_path : ?base:string -> string -> string
  (** Resolves findlib notation in filename paths. The notation 
   * [+name/path] can be used to refer to the subdirectory [name]
   * of the standard library directory; the continuation [/path] is
   * optional. The notation [@name/path] can be used to refer to
   * the directory of the package [name]; the continuation [/path]
   * is optional. For these two notations, absolute paths are returned.
   * 
   * @param base When the function is applied on a relative path, the
   *   [base] path is prepended. Otherwise, the path is returned as
   *   it is.
   *)

val list_packages : ?tab:int -> out_channel -> unit
  (** Prints the list of available packages to the [out_channel].
   *
   * @param tab The tabulator width, by default 20
   *)
