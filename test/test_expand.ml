open! Core
open! Import

let%test_module _ =
  (module struct
    module Key = struct
      module T = struct
        type t = (string, int) Tuple2.t [@@deriving sexp_of]

        type comparator_witness =
          (String.comparator_witness, Int.comparator_witness) Tuple2.comparator_witness

        let comparator = Tuple2.comparator String.comparator Int.comparator
      end

      include T
      include Comparable.Make_plain_using_comparator (T)
    end

    let%expect_test "manual updates" =
      let var =
        [ ("a", 1), "a"; ("b", 2), "b" ] |> Key.Map.of_alist_exn |> Incr.Var.create
      in
      let observer =
        Incr.observe
          (Incr_map.expand
             ~outer_comparator:(module String)
             ~inner_comparator:(module Int)
             (Incr.Var.watch var))
      in
      let update_and_test ~f =
        Incr.Var.replace var ~f;
        Incr.stabilize ();
        print_s [%sexp (Incr.Observer.value_exn observer : string Int.Map.t String.Map.t)]
      in
      update_and_test ~f:Fn.id;
      [%expect {|
        ((a ((1 a)))
         (b ((2 b)))) |}];
      update_and_test ~f:(fun m -> Map.add_exn m ~key:("c", 4) ~data:"c");
      [%expect {|
        ((a ((1 a)))
         (b ((2 b)))
         (c ((4 c)))) |}];
      update_and_test ~f:(fun m -> Map.remove m ("b", 2));
      [%expect {|
        ((a ((1 a)))
         (c ((4 c)))) |}];
      update_and_test ~f:(fun m -> Map.set m ~key:("c", 0) ~data:"c");
      [%expect
        {|
        ((a ((1 a)))
         (c (
           (0 c)
           (4 c)))) |}];
      update_and_test ~f:(fun m -> Map.set m ~key:("c", 1) ~data:"asdf");
      [%expect
        {|
        ((a ((1 a)))
         (c (
           (0 c)
           (1 asdf)
           (4 c)))) |}]
    ;;

    let quickcheck_generator =
      Map.quickcheck_generator
        (module Key)
        [%quickcheck.generator: string * int]
        [%quickcheck.generator: string]
    ;;

    let all_at_once t =
      Map.fold t ~init:String.Map.empty ~f:(fun ~key:(outer_key, inner_key) ~data acc ->
        Map.update acc outer_key ~f:(function
          | None -> Int.Map.singleton inner_key data
          | Some map -> Map.add_exn map ~key:inner_key ~data))
    ;;

    let%test_unit "randomized map changes" =
      let var = Incr.Var.create Key.Map.empty in
      let observer =
        Incremental.observe
          (Incr_map.expand
             (Incr.Var.watch var)
             ~outer_comparator:(module String)
             ~inner_comparator:(module Int))
      in
      Quickcheck.test quickcheck_generator ~f:(fun map ->
        Incr.Var.set var map;
        Incr.stabilize ();
        [%test_result: string Int.Map.t String.Map.t]
          ~expect:(all_at_once map)
          (Incremental.Observer.value_exn observer))
    ;;

    let%test_unit "expand collapse compose" =
      let var = Incr.Var.create Key.Map.empty in
      let observer =
        Incremental.observe
          (Incr_map.collapse
             ~comparator:(module Int)
             (Incr_map.expand
                (Incr.Var.watch var)
                ~outer_comparator:(module String)
                ~inner_comparator:(module Int)))
      in
      Quickcheck.test quickcheck_generator ~f:(fun map ->
        Incr.Var.set var map;
        Incr.stabilize ();
        [%test_result: string Key.Map.t]
          ~expect:map
          (Incremental.Observer.value_exn observer))
    ;;
  end)
;;
