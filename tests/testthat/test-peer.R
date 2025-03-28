test_that(
  'should add each other to neighbor lists when connecting',
  {
    peer1 <- Peer$new(peer_id = "peer1")
    peer2 <- Peer$new(peer_id = "peer2")

    peer1$connect(peer2)

    expect_equal(peer1$neighbors, list("peer2" = peer2))
    expect_equal(peer2$neighbors, list("peer1" = peer1))
  }
)

test_that(
  'should refuse to open connections when max outgoing connections is reached', {
    peer1 <- Peer$new(peer_id = "peer1", max_outgoing_conn = 1)
    peer2 <- Peer$new(peer_id = "peer2")
    peer3 <- Peer$new(peer_id = "peer3")

    expect_true(result::is_success(peer1$connect(peer2)))
    expect_equal(peer1$connect(peer3)$value,
                 "Max outgoing connections (1) reached for peer1")
  }
)

test_that(
  'should not connect twice to the same peer', {
    peer1 <- Peer$new(peer_id = "peer1")
    peer2 <- Peer$new(peer_id = "peer2")

    expect_true(result::is_success(peer1$connect(peer2)))
    expect_equal(peer1$connect(peer2)$value,
                 "Already connected to peer2")
  }
)

test_that(
  'should refuse inbound connections when max total connections is reached', {
    peer1 <- Peer$new(peer_id = "peer1", max_total_conn = 1)
    peer2 <- Peer$new(peer_id = "peer2")
    peer3 <- Peer$new(peer_id = "peer3")

    expect_true(result::is_success(peer2$connect(peer1)))
    expect_equal(peer3$connect(peer1)$value,
                 "Connection refused: Max total connections (1) reached")
  }
)

test_that(
  'should try to populate all outgoing connections on bootstrap', {
    tracker <- Tracker$new()
    peer1 <- Peer$new(peer_id = "peer1", max_outgoing_conn = 2)
    peer2 <- Peer$new(peer_id = "peer2")
    peer3 <- Peer$new(peer_id = "peer3")
    peer4 <- Peer$new(peer_id = "peer4")

    tracker$add_peers(peer1, peer2, peer3, peer4)
    peer1$bootstrap(tracker)

    expect_equal(length(peer1$neighbors), 2)
  }
)
