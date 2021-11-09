import unittest
from ./wavecorepkg/client import nil
from ./wavecorepkg/server import nil
import json
from ./wavecorepkg/ed25519 import nil
from base64 import nil

const
  port = 3000
  address = "http://localhost:" & $port

test "Full lifecycle":
  var s = server.initServer("localhost", port)
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    discard client.post(c, "test", %* {"success": true})
    expect client.ClientException:
      discard client.post(c, "test", nil)
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
  var
    alice = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
    bob = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
  alice.id = entities.insertUser(conn, alice)
  bob.id = entities.insertUser(conn, bob)
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
    var
      alice = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
      bob = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
    alice.id = entities.insertUser(conn, alice)
    bob.id = entities.insertUser(conn, bob)
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
  var
    alice = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
    bob = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
  alice.id = entities.insertUser(conn, alice)
  bob.id = entities.insertUser(conn, bob)
  var p1 = Post(parent_id: 0, user_id: alice.id, body: db.CompressedValue(uncompressed: "Hello, i'm alice"))
  p1.id = entities.insertPost(conn, p1)
  var p2 = Post(parent_id: p1.id, user_id: bob.id, body: db.CompressedValue(uncompressed: "Hello, i'm bob"))
  p2.id = entities.insertPost(conn, p2)
  var p3 = Post(parent_id: p2.id, user_id: alice.id, body: db.CompressedValue(uncompressed: "What's up"))
  p3.id = entities.insertPost(conn, p3)
  var p4 = Post(parent_id: p2.id, user_id: alice.id, body: db.CompressedValue(uncompressed: "How are you?"))
  p4.id = entities.insertPost(conn, p4)
  p1 = entities.selectPost(conn, p1.id)
  p2 = entities.selectPost(conn, p2.id)
  p3 = entities.selectPost(conn, p3.id)
  p4 = entities.selectPost(conn, p4.id)
  check @[p2] == entities.selectPostChildren(conn, p1.id)
  check 3 == entities.selectPost(conn, p1.id).reply_count
  check @[p4, p3] == entities.selectPostChildren(conn, p2.id)
  check 2 == entities.selectPost(conn, p2.id).reply_count
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
    var
      alice = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
      bob = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
    alice.id = entities.insertUser(conn, alice)
    bob.id = entities.insertUser(conn, bob)
    var p1 = Post(parent_id: 0, user_id: alice.id, body: db.CompressedValue(uncompressed: "Hello, i'm alice"))
    p1.id = entities.insertPost(conn, p1)
    var p2 = Post(parent_id: p1.id, user_id: bob.id, body: db.CompressedValue(uncompressed: "Hello, i'm bob"))
    p2.id = entities.insertPost(conn, p2)
    var p3 = Post(parent_id: p2.id, user_id: alice.id, body: db.CompressedValue(uncompressed: "What's up"))
    p3.id = entities.insertPost(conn, p3)
    var p4 = Post(parent_id: p2.id, user_id: alice.id, body: db.CompressedValue(uncompressed: "How are you?"))
    p4.id = entities.insertPost(conn, p4)
    p1 = entities.selectPost(conn, p1.id)
    db_sqlite.close(conn)
    # query db over http
    var response = client.queryPost(c, dbFilename, p1.id)
    client.get(response, true)
    check response.value.valid == p1
    var response2 = client.queryPostChildren(c, dbFilename, p2.id)
    client.get(response2, true)
    check response2.value.valid == @[p4, p3]
    # query something invalid
    var response3 = client.queryPost(c, dbFilename, -1)
    client.get(response3, true)
    check response3.value.kind == client.Error
  finally:
    os.removeFile(dbFilename)
    server.stop(s)
    client.stop(c)

test "search posts":
  let conn = db.open(":memory:")
  db.init(conn)
  var
    alice = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
    bob = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
  alice.id = entities.insertUser(conn, alice)
  bob.id = entities.insertUser(conn, bob)
  var p1 = Post(parent_id: 0, user_id: alice.id, body: db.CompressedValue(uncompressed: "Hello, i'm alice"))
  p1.id = entities.insertPost(conn, p1)
  var p2 = Post(parent_id: p1.id, user_id: bob.id, body: db.CompressedValue(uncompressed: "Hello, i'm bob"))
  p2.id = entities.insertPost(conn, p2)
  p1 = entities.selectPost(conn, p1.id)
  p2 = entities.selectPost(conn, p2.id)
  check @[p1, p2] == entities.searchPosts(conn, "hello")
  db_sqlite.close(conn)

test "retrieve sqlite db via http":
  var s = server.initServer("localhost", port, ".")
  server.start(s)
  try:
    # create test db
    var conn = db.open(dbFilename)
    db.init(conn)
    var
      alice = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
      bob = User(public_key: base64.encode(ed25519.initKeyPair().public, safe = true))
    discard entities.insertUser(conn, alice)
    discard entities.insertUser(conn, bob)
    db_sqlite.close(conn)
    # re-open db, but this time all reads happen over http
    conn = db.open(dbFilename, true)
    let
      alice2 = entities.selectUser(conn, alice.public_key)
      bob2 = entities.selectUser(conn, bob.public_key)
    alice.id = alice2.id
    bob.id = bob2.id
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

