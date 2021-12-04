import unittest
from strutils import nil
import json

from ./wavecorepkg/client import nil
from ./wavecorepkg/server import nil
from ./wavecorepkg/ed25519 import nil
from ./wavecorepkg/paths import nil
from ./wavecorepkg/common import nil

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
from os import `/`
import sets
from osproc import nil

let
  sysopKeys = ed25519.initKeyPair()
  sysopPublicKey = paths.encode(sysopKeys.public)
  bbsDir = "bbstest"
  dbDirs = paths.db(sysopPublicKey)
  dbPath = bbsDir / dbDirs
discard osproc.execProcess("rm -r " & bbsDir)
os.createDir(bbsDir / paths.boardsDir / sysopPublicKey / paths.ansiwavesDir)
os.createDir(bbsDir / paths.boardsDir / sysopPublicKey / paths.dbDir)

vfs.readUrl = "http://localhost:" & $port & "/" & dbDirs
vfs.register()

test "query users":
  db.withOpen(conn, ":memory:", false):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
    entities.insertUser(conn, alice)
    entities.insertUser(conn, bob)
    check alice == entities.selectUser(conn, alice.public_key)
    check bob == entities.selectUser(conn, bob.public_key)

test "query users asynchronously":
  var s = server.initServer("localhost", port, bbsDir)
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    var
      alice, bob: User
    # create test db
    db.withOpen(conn, dbPath, false):
      db.init(conn)
      let
        aliceKeys = ed25519.initKeyPair()
        bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
      entities.insertUser(conn, alice)
      entities.insertUser(conn, bob)
    # query db over http
    var response = client.queryUser(c, dbPath, alice.publicKey)
    client.get(response, true)
    check response.value.valid == alice
    var response2 = client.queryUser(c, dbPath, bob.publicKey)
    client.get(response2, true)
    check response2.value.valid == bob
    # query something invalid
    var response3 = client.queryUser(c, dbPath, "STUFF")
    client.get(response3, true)
    check response3.value.kind == client.Error
  finally:
    os.removeFile(dbPath)
    server.stop(s)
    client.stop(c)

test "query posts":
  db.withOpen(conn, ":memory:", false):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
    entities.insertUser(conn, alice)
    entities.insertUser(conn, bob)
    var p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "Hello, i'm alice"))
    entities.insertPost(conn, p1)
    var p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: entities.initContent(bobKeys, "Hello, i'm bob"))
    entities.insertPost(conn, p2)
    var p3 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "What's up"))
    entities.insertPost(conn, p3)
    var p4 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "How are you?"))
    entities.insertPost(conn, p4)
    expect Exception:
      entities.insertPost(conn, Post(parent: "invalid parent", public_key: alice.public_key, content: entities.initContent(aliceKeys, "How are you?")))
    p1 = entities.selectPost(conn, p1.content.sig)
    p2 = entities.selectPost(conn, p2.content.sig)
    p3 = entities.selectPost(conn, p3.content.sig)
    p4 = entities.selectPost(conn, p4.content.sig)
    check @[p2] == entities.selectPostChildren(conn, p1.content.sig)
    check 3 == entities.selectPost(conn, p1.content.sig).reply_count
    check @[p4, p3] == entities.selectPostChildren(conn, p2.content.sig)
    check 2 == entities.selectPost(conn, p2.content.sig).reply_count
    check [p1, p3, p4].toHashSet == entities.selectUserPosts(conn, alice.public_key).toHashSet

test "query posts asynchronously":
  var s = server.initServer("localhost", port, bbsDir)
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    var
      alice, bob: User
      p1, p2, p3, p4: Post
    # create test db
    db.withOpen(conn, dbPath, false):
      db.init(conn)
      let
        aliceKeys = ed25519.initKeyPair()
        bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
      entities.insertUser(conn, alice)
      entities.insertUser(conn, bob)
      p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "Hello, i'm alice"))
      entities.insertPost(conn, p1)
      p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: entities.initContent(bobKeys, "Hello, i'm bob"))
      entities.insertPost(conn, p2)
      p3 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "What's up"))
      entities.insertPost(conn, p3)
      p4 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "How are you?"))
      entities.insertPost(conn, p4)
      p1 = entities.selectPost(conn, p1.content.sig)
    # query db over http
    var response = client.queryPost(c, dbPath, p1.content.sig)
    client.get(response, true)
    check response.value.valid == p1
    var response2 = client.queryPostChildren(c, dbPath, p2.content.sig)
    client.get(response2, true)
    check response2.value.valid == @[p4, p3]
    var response3 = client.queryUserPosts(c, dbPath, alice.public_key)
    client.get(response3, true)
    check response3.value.valid.toHashSet == [p4, p3, p1].toHashSet
    # query something invalid
    var response4 = client.queryPost(c, dbPath, "yo")
    client.get(response4, true)
    check response4.value.kind == client.Error
  finally:
    os.removeFile(dbPath)
    server.stop(s)
    client.stop(c)

test "search posts":
  db.withOpen(conn, ":memory:", false):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
    entities.insertUser(conn, alice)
    entities.insertUser(conn, bob)
    var p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "Hello, i'm alice"))
    entities.insertPost(conn, p1)
    var p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: entities.initContent(bobKeys, "Hello, i'm bob"))
    entities.insertPost(conn, p2)
    p1 = entities.selectPost(conn, p1.content.sig)
    p2 = entities.selectPost(conn, p2.content.sig)
    check @[p1, p2] == entities.searchPosts(conn, "hello")

test "score":
  db.withOpen(conn, ":memory:", false):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
    entities.insertUser(conn, alice)
    entities.insertUser(conn, bob)
    let p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "Hello, i'm alice"))
    entities.insertPost(conn, p1)
    let p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: entities.initContent(bobKeys, "Hello, i'm bob"))
    entities.insertPost(conn, p2)
    let p3 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "What's up"))
    entities.insertPost(conn, p3)
    let p4 = Post(parent: p2.content.sig, public_key: alice.public_key, content: entities.initContent(aliceKeys, "How are you?"))
    entities.insertPost(conn, p4)
    check 2 == entities.selectPostExtras(conn, p1.content.sig).score

test "edit post":
  db.withOpen(conn, ":memory:", false):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
    entities.insertUser(conn, alice)
    entities.insertUser(conn, bob)
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

test "post to blog":
  db.withOpen(conn, ":memory:", false):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
    entities.insertUser(conn, alice)
    entities.insertUser(conn, bob)
    entities.insertPost(conn, Post(parent: alice.public_key, public_key: alice.public_key, content: entities.initContent(aliceKeys, "My first blog post")))
    expect Exception:
      entities.insertPost(conn, Post(parent: alice.public_key, public_key: bob.public_key, content: entities.initContent(bobKeys, "I shouldn't be able to post here")))

test "retrieve sqlite db via http":
  var s = server.initServer("localhost", port, bbsDir)
  server.start(s)
  try:
    var alice, bob: User
    # create test db
    db.withOpen(conn, dbPath, false):
      db.init(conn)
      let
        aliceKeys = ed25519.initKeyPair()
        bobKeys = ed25519.initKeyPair()
      alice = User(public_key: paths.encode(aliceKeys.public))
      bob = User(public_key: paths.encode(bobKeys.public))
      entities.insertUser(conn, alice)
      entities.insertUser(conn, bob)
    # re-open db, but this time all reads happen over http
    db.withOpen(conn, dbPath, true):
      let
        alice2 = entities.selectUser(conn, alice.public_key)
        bob2 = entities.selectUser(conn, bob.public_key)
      check alice == alice2
      check bob == bob2
  finally:
    os.removeFile(dbPath)
    server.stop(s)

test "submit an ansiwave":
  var s = server.initServer("localhost", port, bbsDir)
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    # create test db
    var subboard: Post
    db.withOpen(conn, dbPath, false):
      db.init(conn)
      let sysop = entities.User(public_key: sysopPublicKey)
      server.editPost(s, sysopPublicKey, entities.initContent(common.signWithHeaders(sysopKeys, "Welcome to my BBS", sysop.public_key, false), sysop.public_key), sysop.public_key)
      subboard = entities.Post(parent: sysop.public_key, public_key: sysop.public_key, content: entities.initContent(common.signWithHeaders(sysopKeys, "General Discussion", sysop.public_key, true)))
      server.insertPost(s, sysopPublicKey, subboard)
    let aliceKeys = ed25519.initKeyPair()
    block:
      let (body, sig) = common.signWithHeaders(aliceKeys, "Hi i'm alice", subboard.content.sig, true, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    block:
      const hulk = staticRead("hulk.ansiwave")
      let (body, sig) = common.signWithHeaders(aliceKeys, strutils.repeat(hulk, 15), subboard.content.sig, true, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Error
  finally:
    os.removeFile(dbPath)
    server.stop(s)
    client.stop(c)

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

