Peer <- R6Class(
  "Peer",
  list(
    peer_id = NULL,
    neighbors = list(),
    max_outgoing_conn = 0,
    max_total_conn = 0,

    initialize = function(
      peer_id,
      max_outgoing_conn = 40,
      max_total_conn = 80
    ) {
      self$peer_id <- peer_id
      self$max_outgoing_conn <- max_outgoing_conn
      self$max_total_conn <- max_total_conn
    },

    bootstrap = function(tracker) {
      peers <- tracker$get_peers(
        (self$max_total_conn + self$max_outgoing_conn) / 2,
        self
      )

      for (peer in peers) {
        if (length(neighbors) >= self$max_total_conn) {
          break
        }
        if (self$peer_id == peer$peer_id) {
          next
        }
        self$connect(peer)
      }
    },

    connect = function(peer) {
      # Peer already connected.
      if (peer$peer_id %in% names(self$neighbors)) {
        return(failure(g("Already connected to {peer$peer_id}")))
      }

      # Outgoing connection limit reached.
      if (length(self$neighbors) >= self$max_outgoing_conn) {
        return(failure(g(
          "Max outgoing connections ({self$max_outgoing_conn}) ",
          "reached for {self$peer_id}"
        )))
      }

      # Peer didn't want to accept our connection.
      conn_result <- peer$accept(self)
      if (is_failure(conn_result)) {
        return(failure(g("Connection refused: {conn_result$value}")))
      }

      self$neighbors[[peer$peer_id]] <- peer
      success()
    },

    accept = function(peer) {
      if (peer$peer_id %in% names(self$neighbors)) {
        return(
          failure(g("Already connected to {peer$peer_id}"))
        )
      }

      if (length(self$neighbors) >= self$max_total_conn) {
        return(
          failure(g("Max total connections ({self$max_total_conn}) reached"))
        )
      }

      self$neighbors[[peer$peer_id]] <- peer
      success()
    }
  )
)
