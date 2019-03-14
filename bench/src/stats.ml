open! Core
open Import

type t =
  { recomputed : int
  ; changed : int
  ; created : int
  ; invalidated : int
  }
[@@deriving sexp]

let diff t1 t2 =
  { recomputed = t1.recomputed - t2.recomputed
  ; changed = t1.changed - t2.changed
  ; created = t1.created - t2.created
  ; invalidated = t1.invalidated - t2.invalidated
  }
;;

let snap () =
  { recomputed = Incr.State.num_nodes_recomputed Incr.State.t
  ; changed = Incr.State.num_nodes_changed Incr.State.t
  ; created = Incr.State.num_nodes_created Incr.State.t
  ; invalidated = Incr.State.num_nodes_invalidated Incr.State.t
  }
;;

let reporter () =
  let open Expect_test_helpers_kernel in
  let old_stats = ref (snap ()) in
  let report () =
    let stats = snap () in
    print_s [%sexp (diff stats !old_stats : t)];
    old_stats := stats
  in
  stage report
;;