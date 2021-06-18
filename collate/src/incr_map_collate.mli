open! Core
module Collate = Collate
module Collated = Collated
module Map_list = Map_list
module Store_params = Incr_memoize.Store_params

module Compare : sig
  (** Note: [Unchanged] and [Reversed] is with respect to ['cmp]. *)
  type ('k, 'v, 'cmp) t =
    | Unchanged
    | Reversed
    | Custom_by_value of { compare : 'v -> 'v -> int }
    | Custom_by_key_and_value of { compare : 'k * 'v -> 'k * 'v -> int }
    (** Partial orders are supported in Custom_by_*, i.e. returning 0 shouldn't cause
        issues. Rows will be then sorted by key. *)
  [@@deriving sexp_of]
end

module Make (Incr : Incremental.S) : sig
  module Compare = Compare
  module Collate = Collate
  module Collated = Collated

  (** Perform the filtering, sorting and restricting to ranges.

      [Collate.t] contains the parameters for filtering and sorting, and ranges. It can
      be updated incrementally, but note that filtering & sorting isn't really incremental
      on filter & order, we [bind] to these inside.

      For sorting & filtering, all this function really need is a predicate (i.e. [_ ->
      bool] function) and compare function. However, the interface is slightly different:
      we require user to provide ['filter] and ['order] opaque types in [Collate.t], and
      ways to convert them to predicate & compare here.

      It is done this way for better interaction with [Incr]. We belive that most users
      would have such types, being simple algebraic data types, anyways. You can always
      set e.g. [filter_to_predicate=Fn.id], and just pass the functions directly, but be
      prepared to explore the fascinating world of functions' physical equality.
  *)
  val collate
    :  ?operation_order:[ `Filter_first | `Sort_first ] (** default: `Sort_first *)
    -> filter_equal:('filter -> 'filter -> bool)
    -> order_equal:('order -> 'order -> bool)
    -> ?filter_memoize_params:'filter Store_params.t
    (** default: an alist-based LRU with size 1 *)
    -> ?order_memoize_params:'order Store_params.t
    (** default: an alist-based LRU with size 10 *)
    -> ?range_memoize_bucket_size:int (** default: 10000 *)
    -> ?range_memoize_cache_size:int (** default: 5 *)
    -> filter_to_predicate:('filter -> (key:'k -> data:'v -> bool) option)
    -> order_to_compare:('order -> ('k, 'v, 'cmp) Compare.t)
    -> ('k, 'v, 'cmp) Map.t Incr.t
    -> ('k, 'filter, 'order) Collate.t Incr.t
    -> ('k, 'v) Collated.t Incr.t

  module New_api : sig
    (** Experimental new API with improved caching semantics.

        In particular, we keep a single cache for each level rather than a separate cache
        for each value on the previous cache. This means the size limits passed to the
        store params are true global limits. Previously, the size limits were separate per
        key used for the previous cache (which means you could potentially have a number
        of cached Incr nodes equal to the product of the cache sizes).

        Note - a value from deeper level can only be used if its partial computations fit
        in their caches too. E.g. if order cache is LRU with size 2,
        and order_filter_range is LRU with size 10, you could get 10 cached final values
        if they share two orderings, but if they were to each have different ordering,
        only two will be cached.

        For this reason, you might want to configure deeper layers to be equal in size to
        the earlier ones if you expect little branching in your queries (e.g. for given
        filter you mostly get queries with one fixed range)
    *)

    module Range_memoize_bucket : sig
      type t [@@deriving sexp_of, equal, hash, compare]

      include Comparable.S_plain with type t := t
    end

    val collate__sort_first
      :  equal_filter:('filter -> 'filter -> bool)
      -> equal_order:('order -> 'order -> bool)
      -> ?order_cache_params:'order Store_params.t
      -> ?order_filter_cache_params:('order * 'filter) Store_params.t
      -> ?order_filter_range_cache_params:
           ('order * 'filter * Range_memoize_bucket.t) Store_params.t
      -> ?range_memoize_bucket_size:int
      -> filter_to_predicate:('filter -> (key:'k -> data:'v -> bool) option)
      -> order_to_compare:('order -> ('k, 'v, 'cmp) Compare.t)
      -> ('k, 'v, 'cmp) Map.t Incr.t
      -> ('k, 'filter, 'order) Collate.t Incr.t
      -> ('k, 'v) Collated.t Incr.t
  end
end
