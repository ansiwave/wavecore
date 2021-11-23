import unittest
from ./wavecorepkg/client import nil
from ./wavecorepkg/server import nil
import json
from ./wavecorepkg/ed25519 import nil
from ./wavecorepkg/paths import nil

const
  port = 3001
  address = "http://localhost:" & $port

test "Full lifecycle":
  var s = server.initServer("localhost", port)
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    expect client.ClientException:
      discard client.post(c, "ansiwave", "Hello, world!")
  finally:
    server.stop(s)
    client.stop(c)

test "Request static file":
  var s = server.initServer("localhost", port, "tests")
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    discard client.get(c, "config.nims")
    discard client.get(c, "config.nims", (0, 10))
  finally:
    server.stop(s)
    client.stop(c)

test "Request static file asynchronously":
  var s = server.initServer("localhost", port, "tests")
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    var response = client.query(c, "config.nims")
    client.get(response, true)
    check response.value.kind == client.Valid
  finally:
    server.stop(s)
    client.stop(c)

import ./wavecorepkg/db
import ./wavecorepkg/db/entities
import ./wavecorepkg/db/vfs
from ./wavecorepkg/db/db_sqlite import nil
from os import nil

const dbFilename = "test.db"
vfs.readUrl = "http://localhost:" & $port & "/" & dbFilename
vfs.register()

test "query users":
  let conn = db.open(":memory:")
  db.init(conn)
  let
    aliceKeys = ed25519.initKeyPair()
    bobKeys = ed25519.initKeyPair()
    alice = User(public_key: paths.encode(aliceKeys.public))
    bob = User(public_key: paths.encode(bobKeys.public))
  entities.insertUser(conn, alice, entities.initContent(aliceKeys, ""))
  entities.insertUser(conn, bob, entities.initContent(bobKeys, ""))
  check alice == entities.selectUser(conn, alice.public_key)
  check bob == entities.selectUser(conn, bob.public_key)
  db_sqlite.close(conn)

test "query users asynchronously":
  var s = server.initServer("localhost", port, ".")
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    # create test db
    let conn = db.open(dbFilename)
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
    entities.insertUser(conn, alice, entities.initContent(aliceKeys, ""))
    entities.insertUser(conn, bob, entities.initContent(bobKeys, ""))
    db_sqlite.close(conn)
    # query db over http
    var response = client.queryUser(c, dbFilename, alice.publicKey)
    client.get(response, true)
    check response.value.valid == alice
    var response2 = client.queryUser(c, dbFilename, bob.publicKey)
    client.get(response2, true)
    check response2.value.valid == bob
    # query something invalid
    var response3 = client.queryUser(c, dbFilename, "STUFF")
    client.get(response3, true)
    check response3.value.kind == client.Error
  finally:
    os.removeFile(dbFilename)
    server.stop(s)
    client.stop(c)

test "query posts":
  let conn = db.open(":memory:")
  db.init(conn)
  let
    aliceKeys = ed25519.initKeyPair()
    bobKeys = ed25519.initKeyPair()
    alice = User(public_key: paths.encode(aliceKeys.public))
    bob = User(public_key: paths.encode(bobKeys.public))
  entities.insertUser(conn, alice, entities.initContent(aliceKeys, ""))
  entities.insertUser(conn, bob, entities.initContent(bobKeys, ""))
  var p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "Hello, i'm alice"))
  entities.insertPost(conn, p1)
  var p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: entities.initContent(bobKeys, "Hello, i'm bob"))
  entities.insertPost(conn, p2)
  var p3 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "What's up"))
  entities.insertPost(conn, p3)
  var p4 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "How are you?"))
  entities.insertPost(conn, p4)
  p1 = entities.selectPost(conn, p1.content.sig)
  p2 = entities.selectPost(conn, p2.content.sig)
  p3 = entities.selectPost(conn, p3.content.sig)
  p4 = entities.selectPost(conn, p4.content.sig)
  check @[p2] == entities.selectPostChildren(conn, p1.content.sig)
  check 3 == entities.selectPost(conn, p1.content.sig).reply_count
  check @[p4, p3] == entities.selectPostChildren(conn, p2.content.sig)
  check 2 == entities.selectPost(conn, p2.content.sig).reply_count
  db_sqlite.close(conn)

test "query posts asynchronously":
  var s = server.initServer("localhost", port, ".")
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    # create test db
    let conn = db.open(dbFilename)
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
    entities.insertUser(conn, alice, entities.initContent(aliceKeys, ""))
    entities.insertUser(conn, bob, entities.initContent(bobKeys, ""))
    var p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "Hello, i'm alice"))
    entities.insertPost(conn, p1)
    var p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: entities.initContent(bobKeys, "Hello, i'm bob"))
    entities.insertPost(conn, p2)
    var p3 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "What's up"))
    entities.insertPost(conn, p3)
    var p4 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "How are you?"))
    entities.insertPost(conn, p4)
    p1 = entities.selectPost(conn, p1.content.sig)
    db_sqlite.close(conn)
    # query db over http
    var response = client.queryPost(c, dbFilename, p1.content.sig)
    client.get(response, true)
    check response.value.valid == p1
    var response2 = client.queryPostChildren(c, dbFilename, p2.content.sig)
    client.get(response2, true)
    check response2.value.valid == @[p4, p3]
    # query something invalid
    var response3 = client.queryPost(c, dbFilename, "yo")
    client.get(response3, true)
    check response3.value.kind == client.Error
  finally:
    os.removeFile(dbFilename)
    server.stop(s)
    client.stop(c)

test "search posts":
  let conn = db.open(":memory:")
  db.init(conn)
  let
    aliceKeys = ed25519.initKeyPair()
    bobKeys = ed25519.initKeyPair()
    alice = User(public_key: paths.encode(aliceKeys.public))
    bob = User(public_key: paths.encode(bobKeys.public))
  entities.insertUser(conn, alice, entities.initContent(aliceKeys, ""))
  entities.insertUser(conn, bob, entities.initContent(bobKeys, ""))
  var p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "Hello, i'm alice"))
  entities.insertPost(conn, p1)
  var p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: entities.initContent(bobKeys, "Hello, i'm bob"))
  entities.insertPost(conn, p2)
  p1 = entities.selectPost(conn, p1.content.sig)
  p2 = entities.selectPost(conn, p2.content.sig)
  check @[p1, p2] == entities.searchPosts(conn, "hello")
  db_sqlite.close(conn)

test "score":
  let conn = db.open(":memory:")
  db.init(conn)
  let
    aliceKeys = ed25519.initKeyPair()
    bobKeys = ed25519.initKeyPair()
    alice = User(public_key: paths.encode(aliceKeys.public))
    bob = User(public_key: paths.encode(bobKeys.public))
  entities.insertUser(conn, alice, entities.initContent(aliceKeys, ""))
  entities.insertUser(conn, bob, entities.initContent(bobKeys, ""))
  let p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "Hello, i'm alice"))
  entities.insertPost(conn, p1)
  let p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: entities.initContent(bobKeys, "Hello, i'm bob"))
  entities.insertPost(conn, p2)
  let p3 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "What's up"))
  entities.insertPost(conn, p3)
  let p4 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "How are you?"))
  entities.insertPost(conn, p4)
  check 2 == entities.selectPostExtras(conn, p1.content.sig).score
  db_sqlite.close(conn)

test "edit post":
  let conn = db.open(":memory:")
  db.init(conn)
  let
    aliceKeys = ed25519.initKeyPair()
    bobKeys = ed25519.initKeyPair()
    alice = User(public_key: paths.encode(aliceKeys.public))
    bob = User(public_key: paths.encode(bobKeys.public))
  entities.insertUser(conn, alice, entities.initContent(aliceKeys, ""))
  entities.insertUser(conn, bob, entities.initContent(bobKeys, ""))
  let p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "I like turtles"))
  entities.insertPost(conn, p1)
  let newText = "I hate turtles"
  var newContent = entities.initContent(aliceKeys, newText)
  newContent.sig_last = p1.content.sig
  entities.editPost(conn, newContent, alice.public_key)
  check entities.searchPosts(conn, "like").len == 0
  check entities.searchPosts(conn, "hate").len == 1
  expect Exception:
    entities.editPost(conn, newContent, bob.public_key)
  db_sqlite.close(conn)

test "post to blog":
  let conn = db.open(":memory:")
  db.init(conn)
  let
    aliceKeys = ed25519.initKeyPair()
    bobKeys = ed25519.initKeyPair()
    alice = User(public_key: paths.encode(aliceKeys.public))
    bob = User(public_key: paths.encode(bobKeys.public))
  entities.insertUser(conn, alice, entities.initContent(aliceKeys, ""))
  entities.insertUser(conn, bob, entities.initContent(bobKeys, ""))
  entities.insertPost(conn, Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "My first blog post")))
  expect Exception:
    entities.insertPost(conn, Post(parent: alice.public_key, public_key: bob.public_key, content: entities.initContent(bobKeys, "I shouldn't be able to post here")))
  db_sqlite.close(conn)

test "retrieve sqlite db via http":
  var s = server.initServer("localhost", port, ".")
  server.start(s)
  try:
    # create test db
    var conn = db.open(dbFilename)
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
    entities.insertUser(conn, alice, entities.initContent(aliceKeys, ""))
    entities.insertUser(conn, bob, entities.initContent(bobKeys, ""))
    db_sqlite.close(conn)
    # re-open db, but this time all reads happen over http
    conn = db.open(dbFilename, true)
    let
      alice2 = entities.selectUser(conn, alice.public_key)
      bob2 = entities.selectUser(conn, bob.public_key)
    check alice == alice2
    check bob == bob2
    db_sqlite.close(conn)
  finally:
    os.removeFile(dbFilename)
    server.stop(s)

test "ed25519":
  var
    seed: ed25519.Seed
    public_key: ed25519.PublicKey
    private_key: ed25519.PrivateKey
    signature: ed25519.Signature

  var
    other_public_key: ed25519.PublicKey
    other_private_key: ed25519.PrivateKey
    shared_secret: array[32, uint8]

  const message = "TEST MESSAGE"

  ##  create a random seed, and a key pair out of that seed

  check 0 == ed25519.ed25519_create_seed(seed.addr)
  ed25519.ed25519_create_keypair(public_key.addr, private_key.addr, seed.addr)

  ##  make sure we can get public key from the private key
  var pubkey: ed25519.PublicKey
  ed25519.ed25519_create_keypair_from_private_key(pubkey.addr, private_key.addr)
  check pubkey == public_key

  ##  create signature on the message with the key pair

  ed25519.ed25519_sign(signature.addr, message, message.len, public_key.addr, private_key.addr)

  ##  verify the signature
  check 1 == ed25519.ed25519_verify(signature.addr, message, message.len, public_key.addr)

  ##  create a dummy keypair to use for a key exchange, normally you'd only have
  ## the public key and receive it through some communication channel

  check 0 == ed25519.ed25519_create_seed(seed.addr)

  ed25519.ed25519_create_keypair(other_public_key.addr, other_private_key.addr, seed.addr)

  ##  do a key exchange with other_public_key

  ed25519.ed25519_key_exchange(shared_secret.addr, other_public_key.addr, private_key.addr)

