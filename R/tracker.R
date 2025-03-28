Tracker <- R6Class(
  "Tracker",
  list(
    peers = list(),
    sampling_fun = NULL,

    initialize = function(sampling_fun = sample, peer) {
      self$sampling_fun = sampling_fun
    },

    get_peers = function(max_peers, peer) {
      peers <- self$sampling_fun(
        x = self$peers,
        size = min(max_peers, length(self$peers)),
        replace = FALSE
      )

      self$peers[[peer$peer_id]] <- peer

      peers
    },

    add_peers = function(..., .peers = c()) {
      peer_list <- if (length(.peers) > 0) .peers else rlang::list2(...)
      names(peer_list) <- sapply(peer_list, function(peer) peer$peer_id)
      self$peers <- c(self$peers, peer_list)
      self$peers
    }
  )
)
