test_that("should add peer to known peers when calling get_peers", {
  tracker <- Tracker$new()
  peer <- Peer$new(peer_id = "some id")
  peers <- tracker$get_peers(1, peer)

  expect_equal(peers, list())
  expect_equal(tracker$peers, list("some id" = peer))
})

test_that("should return a random sample of existing peers", {
  sampling_fun <- function(x, size, replace) {
    if (size != 3) {
      stop("Expected n to be 3")
    }
    if (replace != FALSE) {
      stop("Expected replace to be FALSE")
    }
    x[c(1, 3, 2)]
  }

  tracker <- Tracker$new(sampling_fun = sampling_fun)
  peer1 <- Peer$new(peer_id = "peer1")
  tracker$add_peers(
    peer1,
    Peer$new(peer_id = "peer2"),
    Peer$new(peer_id = "peer3"),
    Peer$new(peer_id = "peer4")
  )

  peers <- tracker$get_peers(3, peer1)
  expect_equal(
    unname(sapply(peers, function(x) x$peer_id)),
    c("peer1", "peer3", "peer2")
  )
})
