# @export
overlay_game <- function(
  n,
  n_storage_nodes,
  max_outgoing_conn = 40,
  max_total_conn = 80
) {
  tracker <- Tracker$new()
  storage <- lapply(1:n_storage_nodes, function(i) {
    Peer$new(
      peer_id = glue("S[{i}]"),
      max_outgoing_conn = max_outgoing_conn,
      max_total_conn = max_total_conn
    )
  })

  # Storage peers are added without any connections to each other.
  tracker$add_peers(.peers = storage)

  n_downloaders <- n - n_storage_nodes
  downloaders <- lapply(1:n_downloaders, function(i) {
    downloader <- Peer$new(
      peer_id = glue("D[{i}]"),
      max_outgoing_conn = max_outgoing_conn,
      max_total_conn = max_total_conn
    )
    downloader$bootstrap(tracker)
    downloader
  })

  list(
    tracker = tracker,
    storage = storage,
    downloaders = downloaders
  )
}

# @export
as_graph <- function(
  overlay,
  block_flow_graph = FALSE,
  downloader_color = "orange",
  storage_color = "purple"
) {
  storage <- overlay$storage
  downloaders <- overlay$downloaders

  nodes <- c(storage, downloaders)
  edges <- unlist(flatten(
    lapply(if (block_flow_graph) downloaders else nodes, function(node) {
      flatten(lapply(node$neighbors, function(neighbor) {
        c(node$peer_id, neighbor$peer_id)
      }))
    })
  ))

  g <- make_empty_graph(directed = block_flow_graph) |>
    add_vertices(length(storage), color = storage_color) |>
    add_vertices(length(downloaders), color = downloader_color)

  V(g)[1:length(nodes)]$name <- sapply(nodes, function(node) node$peer_id)
  V(g)[1:length(nodes)]$label <- sapply(
    nodes,
    function(node) parse(text = node$peer_id)
  )

  g <- add_edges(g, edges) |>
    igraph::simplify()

  g <- reverse_edges(g, E(g)) # gets the direction right for the block flow graphs

  V(g)[1:length(storage)]$color <- storage_color
  V(g)[(length(storage) + 1):length(nodes)]$color <- downloader_color

  g
}
