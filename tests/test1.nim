import unittest
from strutils import nil
from sequtils import nil
import json

from ./wavecorepkg/wavescript import nil

proc parseAnsiwave(lines: seq[string]): seq[wavescript.CommandTree] =
  var scriptContext = waveScript.initContext()
  let
    cmds = wavescript.extract(lines)
    treesTemp = sequtils.map(cmds, proc (text: auto): wavescript.CommandTree = wavescript.parse(scriptContext, text))
  wavescript.parseOperatorCommands(treesTemp)

test "Parse commands":
  const hello = staticRead("hello.ansiwave")
  let lines = strutils.splitLines(hello)
  let trees = parseAnsiwave(lines)
  check trees.len == 2

test "Parse operators":
  let lines = strutils.splitLines("/rock-organ c#+3 /octave 3 d-,c /2 1/2 c,d c+")
  let trees = parseAnsiwave(lines)
  check trees.len == 1

test "Parse broken symbol":
  let lines = strutils.splitLines("/instrument -hello-world")
  let trees = parseAnsiwave(lines)
  check trees.len == 1

test "/,":
  let text = strutils.splitLines("""
/banjo /octave 3 /16 b c+ /8 d+ b c+ a b g a
/,
/guitar /octave 3 /16 r r /8 g r d r g g d
""")
  let trees = parseAnsiwave(text)
  check trees.len == 3

test "variables":
  const text = staticRead("variables.ansiwave")
  let lines = strutils.splitLines(text)
  let trees = parseAnsiwave(lines)
  check trees.len == 4

from ./wavecorepkg/client import nil
from ./wavecorepkg/server import nil
from ./wavecorepkg/ed25519 import nil
from ./wavecorepkg/paths import nil
from ./wavecorepkg/common import nil

import ./wavecorepkg/db
import ./wavecorepkg/db/entities
import ./wavecorepkg/db/vfs
from os import `/`
import sets

const
  port = 3001
  address = "http://localhost:" & $port

let
  sysopKeys = ed25519.initKeyPair()
  sysopPublicKey = paths.encode(sysopKeys.public)
  bbsDir = "bbstest"
  dbDirs = paths.db(sysopPublicKey)
  dbPath = bbsDir / dbDirs
os.createDir(bbsDir / paths.boardsDir / sysopPublicKey / paths.ansiwavesDir)
os.createDir(bbsDir / paths.boardsDir / sysopPublicKey / paths.dbDir)
paths.readUrl = "http://localhost:" & $port & "/" & dbDirs
vfs.register()

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

proc initUser(publicKey: string): User =
  entities.User(public_key: publicKey, tags: entities.Tags(sig: publicKey))

proc initContent(keys: ed25519.KeyPair, origContent: string): entities.Content =
  let content = "\n\n" & origContent # add two newlines to simulate where headers would've been
  result.value = initCompressedValue(content)
  result.sig = paths.encode(ed25519.sign(keys, content))
  result.sig_last = result.sig

proc initContent(content: tuple[body: string, sig: string], sigLast: string = content.sig): Content =
  result.value = initCompressedValue(content.body)
  result.sig = content.sig
  result.sig_last = sigLast

test "query users":
  db.withOpen(conn, ":memory:", false):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
    var
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
    entities.insertUser(conn, alice, alice.user_id)
    entities.insertUser(conn, bob, bob.user_id)
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
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
      entities.insertUser(conn, alice, alice.user_id)
      entities.insertUser(conn, bob, bob.user_id)
    # query db over http
    block:
      var response = client.queryUser(c, dbPath, alice.publicKey)
      client.get(response, true)
      check response.value.valid == alice
    block:
      var response = client.queryUser(c, dbPath, bob.publicKey)
      client.get(response, true)
      check response.value.valid == bob
    # query something invalid
    block:
      var response = client.queryUser(c, dbPath, "STUFF")
      client.get(response, true)
      check response.value.kind == client.Error
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
    var
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
    entities.insertUser(conn, alice, alice.user_id)
    entities.insertUser(conn, bob, bob.user_id)
    var p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: initContent(aliceKeys, "Hello, i'm alice"))
    discard entities.insertPost(conn, p1, p1.post_id)
    var p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: initContent(bobKeys, "Hello, i'm bob"))
    discard entities.insertPost(conn, p2, p2.post_id)
    var p3 = Post(parent: p2.content.sig, public_key: alice.public_key, content: initContent(aliceKeys, "What's up"))
    discard entities.insertPost(conn, p3, p3.post_id)
    var p4 = Post(parent: p2.content.sig, public_key: alice.public_key, content: initContent(aliceKeys, "How are you?"))
    discard entities.insertPost(conn, p4, p4.post_id)
    expect Exception:
      discard entities.insertPost(conn, Post(parent: "invalid parent", public_key: alice.public_key, content: initContent(aliceKeys, "How are you?")))
    p1 = entities.selectPost(conn, p1.content.sig)
    p2 = entities.selectPost(conn, p2.content.sig)
    p3 = entities.selectPost(conn, p3.content.sig)
    p4 = entities.selectPost(conn, p4.content.sig)
    check @[p2] == entities.selectPostChildren(conn, p1.content.sig)
    check 3 == entities.selectPost(conn, p1.content.sig).reply_count
    check @[p4, p3] == entities.selectPostChildren(conn, p2.content.sig)
    check 2 == entities.selectPost(conn, p2.content.sig).reply_count
    check [p1, p3, p4].toHashSet == entities.selectUserPosts(conn, alice.public_key).toHashSet
    check [p3, p4].toHashSet == entities.selectUserReplies(conn, bob.public_key).toHashSet

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
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
      entities.insertUser(conn, alice, alice.user_id)
      entities.insertUser(conn, bob, bob.user_id)
      p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: initContent(aliceKeys, "Hello, i'm alice"))
      discard entities.insertPost(conn, p1, p1.post_id)
      p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: initContent(bobKeys, "Hello, i'm bob"))
      discard entities.insertPost(conn, p2, p2.post_id)
      p3 = Post(parent: p2.content.sig, public_key: alice.public_key, content: initContent(aliceKeys, "What's up"))
      discard entities.insertPost(conn, p3, p3.post_id)
      p4 = Post(parent: p2.content.sig, public_key: alice.public_key, content: initContent(aliceKeys, "How are you?"))
      discard entities.insertPost(conn, p4, p4.post_id)
      p1 = entities.selectPost(conn, p1.content.sig)
      p2 = entities.selectPost(conn, p2.content.sig)
      p3 = entities.selectPost(conn, p3.content.sig)
      p4 = entities.selectPost(conn, p4.content.sig)
    # query db over http
    block:
      var response = client.queryPost(c, dbPath, p1.content.sig)
      client.get(response, true)
      check response.value.valid == p1
    block:
      var response = client.queryPostChildren(c, dbPath, p2.content.sig)
      client.get(response, true)
      check response.value.valid == @[p4, p3]
    block:
      var response = client.queryUserPosts(c, dbPath, alice.public_key)
      client.get(response, true)
      check response.value.valid.toHashSet == [p4, p3, p1].toHashSet
    block:
      var response = client.queryUserReplies(c, dbPath, bob.public_key)
      client.get(response, true)
      check response.value.valid.toHashSet == [p4, p3].toHashSet
    # query something invalid
    block:
      var response = client.queryPost(c, dbPath, "yo")
      client.get(response, true)
      check response.value.kind == client.Error
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
    var
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
    entities.insertUser(conn, alice, alice.user_id)
    entities.insertUser(conn, bob, bob.user_id)
    var p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: initContent(aliceKeys, "Hello, i'm alice"))
    discard entities.insertPost(conn, p1)
    var p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: initContent(bobKeys, "Hello, i'm bob"))
    discard entities.insertPost(conn, p2)
    p1 = entities.selectPost(conn, p1.content.sig)
    p2 = entities.selectPost(conn, p2.content.sig)
    check @[p1, p2] == entities.search(conn, entities.Posts, "hello")
    check entities.search(conn, entities.Posts, "").len == 2
    check entities.search(conn, entities.Users, "").len == 2
    entities.editTags(conn, entities.Tags(value: "\n\nmoderator", sig: "alice1"), alice.public_key, sysopPublicKey, sysopPublicKey)
    check entities.search(conn, entities.UserTags, "").len == 1
    check entities.search(conn, entities.UserTags, "stuff").len == 0
    check entities.search(conn, entities.UserTags, "moderator").len == 1

test "score":
  db.withOpen(conn, ":memory:", false):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
    var
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
    entities.insertUser(conn, alice, alice.user_id)
    entities.insertUser(conn, bob, bob.user_id)
    let p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: initContent(aliceKeys, "Hello, i'm alice"))
    discard entities.insertPost(conn, p1)
    let p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: initContent(bobKeys, "Hello, i'm bob"))
    discard entities.insertPost(conn, p2)
    let p3 = Post(parent: p2.content.sig, public_key: alice.public_key, content: initContent(aliceKeys, "What's up"))
    discard entities.insertPost(conn, p3)
    let p4 = Post(parent: p2.content.sig, public_key: alice.public_key, content: initContent(aliceKeys, "How are you?"))
    discard entities.insertPost(conn, p4)
    check 2 == entities.selectPost(conn, p1.content.sig).score

test "edit post and user":
  db.withOpen(conn, ":memory:", false):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
    var
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
    entities.insertUser(conn, alice, alice.user_id)
    entities.insertUser(conn, bob, bob.user_id)
    let p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: initContent(aliceKeys, "I like turtles"))
    discard entities.insertPost(conn, p1)
    let newText = "I hate turtles"
    var newContent = initContent(aliceKeys, newText)
    newContent.sig_last = p1.content.sig
    discard entities.editPost(conn, newContent, alice.public_key)
    check entities.search(conn, entities.Posts, "like").len == 0
    check entities.search(conn, entities.Posts, "hate").len == 1
    expect Exception:
      discard entities.editPost(conn, newContent, bob.public_key)
    # sysop can make alice a moderator
    entities.editTags(conn, entities.Tags(value: "\n\nmoderator", sig: "alice1"), alice.public_key, sysopPublicKey, sysopPublicKey)
    check "moderator" == entities.selectUser(conn, alice.public_key).tags.value
    check "moderator" == entities.selectPost(conn, p1.content.sig).tags
    # alice can now tag bob
    entities.editTags(conn, entities.Tags(value: "\n\nstuff", sig: "bob1"), bob.public_key, sysopPublicKey, alice.public_key)
    # bob cannot tag alice
    expect Exception:
      entities.editTags(conn, entities.Tags(value: "\n\nmoderator hi", sig: "alice2"), "alice1", sysopPublicKey, bob.public_key)
    # alice cannot make bob a moderator because she isn't a modleader
    expect Exception:
      entities.editTags(conn, entities.Tags(value: "\n\nmoderator", sig: "bob2"), "bob1", sysopPublicKey, alice.public_key)
    # sysop now makes alice a modleader
    entities.editTags(conn, entities.Tags(value: "\n\nmodleader", sig: "alice2"), "alice1", sysopPublicKey, sysopPublicKey)
    # alice now makes bob a moderator
    entities.editTags(conn, entities.Tags(value: "\n\nmoderator", sig: "bob2"), "bob1", sysopPublicKey, alice.public_key)
    # bob cannot remove his moderator status
    expect Exception:
      entities.editTags(conn, entities.Tags(value: "\n\n", sig: "bob3"), "bob2", sysopPublicKey, bob.public_key)
    # bob change other tags
    entities.editTags(conn, entities.Tags(value: "\n\nmoderator hello", sig: "bob3"), "bob2", sysopPublicKey, bob.public_key)
    # mod* tags are reserved, and unrecognized ones are an error
    expect Exception:
      entities.editTags(conn, entities.Tags(value: "\n\nmodleader modstuff", sig: "alice3"), "alice2", sysopPublicKey, sysopPublicKey)
    # tags can only contain a-z
    expect Exception:
      entities.editTags(conn, entities.Tags(value: "\n\nmodleader HI", sig: "alice3"), "alice2", sysopPublicKey, sysopPublicKey)
    # bob cannot ban alice
    expect Exception:
      entities.editTags(conn, entities.Tags(value: "\n\nmodban", sig: "alice3"), "alice2", sysopPublicKey, bob.public_key)
    # bob can post
    let p2 = Post(parent: bob.public_key, public_key: bob.public_key, content: initContent(bobKeys, "I like turtles"))
    discard entities.insertPost(conn, p2)
    # alice can hide bob
    check 1 == entities.selectPostChildren(conn, bob.public_key).len
    entities.editTags(conn, entities.Tags(value: "\n\nmoderator modhide", sig: "bob4"), "bob3", sysopPublicKey, alice.public_key)
    check 0 == entities.selectPostChildren(conn, bob.public_key).len
    entities.editTags(conn, entities.Tags(value: "\n\nmoderator", sig: "bob5"), "bob4", sysopPublicKey, alice.public_key)
    check 1 == entities.selectPostChildren(conn, bob.public_key).len
    # alice can ban bob
    entities.editTags(conn, entities.Tags(value: "\n\nmoderator modban", sig: "bob6"), "bob5", sysopPublicKey, alice.public_key)
    # bob can no longer post
    expect Exception:
      discard entities.insertPost(conn, Post(parent: bob.public_key, public_key: bob.public_key, content: initContent(bobKeys, "I like turtles a lot")))
    expect Exception:
      var newContent = initContent(bobKeys, newText)
      newContent.sig_last = p2.content.sig
      discard entities.editPost(conn, newContent, bob.public_key)
    expect Exception:
      entities.editTags(conn, entities.Tags(value: "\n\nmoderator hi", sig: "bob7"), "bob6", sysopPublicKey, bob.public_key)

test "post to blog":
  db.withOpen(conn, ":memory:", false):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
    var
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
    entities.insertUser(conn, alice, alice.user_id)
    entities.insertUser(conn, bob, bob.user_id)
    discard entities.insertPost(conn, Post(parent: alice.public_key, public_key: alice.public_key, content: initContent(aliceKeys, "My first blog post")))
    expect Exception:
      discard entities.insertPost(conn, Post(parent: alice.public_key, public_key: bob.public_key, content: initContent(bobKeys, "I shouldn't be able to post here")))

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
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
      entities.insertUser(conn, alice, alice.user_id)
      entities.insertUser(conn, bob, bob.user_id)
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
      let sysop = initUser(sysopPublicKey)
      server.editPost(s, sysopPublicKey, initContent(common.signWithHeaders(sysopKeys, "Welcome to my BBS", sysop.public_key, common.Edit, sysopPublicKey), sysop.public_key), sysop.public_key)
      subboard = entities.Post(parent: sysop.public_key, public_key: sysop.public_key, content: initContent(common.signWithHeaders(sysopKeys, "General Discussion", sysop.public_key, common.New, sysopPublicKey)))
      server.insertPost(s, sysopPublicKey, subboard)
    let aliceKeys = ed25519.initKeyPair()
    block:
      let (body, sig) = common.signWithHeaders(aliceKeys, "Hi i'm alice", subboard.content.sig, common.New, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    block:
      const hulk = staticRead("hulk.ansiwave")
      let (body, sig) = common.signWithHeaders(aliceKeys, strutils.repeat(hulk, 15), subboard.content.sig, common.New, sysopPublicKey)
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

