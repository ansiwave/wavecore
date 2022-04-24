import unittest
from strutils import nil
from sequtils import nil
import tables

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

test "Parse string command with ANSI block characters":
  let lines = strutils.splitLines("/section \e[31m██████ Hello! ██████")
  let trees = parseAnsiwave(lines)
  check trees.len == 1
  check trees[0].kind == wavescript.Valid
  check trees[0].args[0].name == "Hello!"

test "Parse /link command with validator":
  let error = parseAnsiwave(strutils.splitLines("/link hello"))
  check error.len == 1
  check error[0].kind == wavescript.Error
  let success = parseAnsiwave(strutils.splitLines("/link hello https://ansiwave.net"))
  check success.len == 1
  check success[0].kind == wavescript.Valid

test "Parse /name commands with validator":
  let error = parseAnsiwave(strutils.splitLines("/name hello-world"))
  check error.len == 1
  check error[0].kind == wavescript.Error
  let success = parseAnsiwave(strutils.splitLines("/name helloworld"))
  check success.len == 1
  check success[0].kind == wavescript.Valid

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
  boardDir = bbsDir / paths.boardsDir / sysopPublicKey
  dbDirs = paths.db(sysopPublicKey, isUrl = true)
  dbPath = bbsDir / paths.db(sysopPublicKey)
os.createDir(bbsDir / paths.boardsDir / sysopPublicKey / paths.ansiwavesDir)
os.createDir(bbsDir / paths.boardsDir / sysopPublicKey / paths.dbDir)
os.createDir(bbsDir / paths.limboDir / sysopPublicKey / paths.ansiwavesDir)
os.createDir(bbsDir / paths.limboDir / sysopPublicKey / paths.dbDir)
paths.address = "http://localhost:" & $port
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
  db.withOpen(conn, ":memory:", db.ReadWrite):
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
    db.withOpen(conn, dbPath, db.ReadWrite):
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
      var response = client.queryUser(c, dbDirs, alice.publicKey)
      client.get(response, true)
      check response.value.valid == alice
    block:
      var response = client.queryUser(c, dbDirs, bob.publicKey)
      client.get(response, true)
      check response.value.valid == bob
    # query something invalid
    block:
      var response = client.queryUser(c, dbDirs, "STUFF")
      client.get(response, true)
      check response.value.valid == entities.User()
  finally:
    os.removeFile(dbPath)
    server.stop(s)
    client.stop(c)

test "query posts":
  db.withOpen(conn, ":memory:", db.ReadWrite):
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
    check [p2].toHashSet == entities.selectPostChildren(conn, p1.content.sig).toHashSet
    check 3 == entities.selectPost(conn, p1.content.sig).reply_count
    check [p4, p3].toHashSet == entities.selectPostChildren(conn, p2.content.sig).toHashSet
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
    db.withOpen(conn, dbPath, db.ReadWrite):
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
      var response = client.queryPost(c, dbDirs, p1.content.sig)
      client.get(response, true)
      check response.value.valid == p1
    block:
      var response = client.queryPostChildren(c, dbDirs, p2.content.sig)
      client.get(response, true)
      check response.value.valid.toHashSet == [p4, p3].toHashSet
    block:
      var response = client.queryUserPosts(c, dbDirs, alice.public_key)
      client.get(response, true)
      check response.value.valid.toHashSet == [p4, p3, p1].toHashSet
    block:
      var response = client.queryUserReplies(c, dbDirs, bob.public_key)
      client.get(response, true)
      check response.value.valid.toHashSet == [p4, p3].toHashSet
    # query something invalid
    block:
      var response = client.queryPost(c, dbDirs, "yo")
      client.get(response, true)
      check response.value.kind == client.Error
  finally:
    os.removeFile(dbPath)
    server.stop(s)
    client.stop(c)

test "query posts offline":
  var s = server.initServer("localhost", port, bbsDir)
  server.start(s)
  var c = client.Client(kind: client.Offline, path: boardDir, postAddress: address)
  client.start(c)
  try:
    var
      alice, bob: User
      p1, p2, p3, p4: Post
    # create test db
    db.withOpen(conn, dbPath, db.ReadWrite):
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
    # query db on disk
    block:
      var response = client.queryPost(c, dbDirs, p1.content.sig)
      client.get(response, true)
      check response.value.valid == p1
    block:
      var response = client.queryPostChildren(c, dbDirs, p2.content.sig)
      client.get(response, true)
      check response.value.valid.toHashSet == [p4, p3].toHashSet
    block:
      var response = client.queryUserPosts(c, dbDirs, alice.public_key)
      client.get(response, true)
      check response.value.valid.toHashSet == [p4, p3, p1].toHashSet
    block:
      var response = client.queryUserReplies(c, dbDirs, bob.public_key)
      client.get(response, true)
      check response.value.valid.toHashSet == [p4, p3].toHashSet
    # query something invalid
    block:
      var response = client.queryPost(c, dbDirs, "yo")
      client.get(response, true)
      check response.value.kind == client.Error
  finally:
    os.removeFile(dbPath)
    server.stop(s)
    client.stop(c)


test "search posts":
  db.withOpen(conn, ":memory:", db.ReadWrite):
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

from ./wavecorepkg/db/db_sqlite import sql

test "score":
  db.withOpen(conn, ":memory:", db.ReadWrite):
    db.init(conn)
    let
      aliceKeys = ed25519.initKeyPair()
      bobKeys = ed25519.initKeyPair()
    var
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
    alice.tags.value = "modhide"
    bob.tags.value = "modhide"
    entities.insertUser(conn, alice, alice.user_id)
    entities.insertUser(conn, bob, bob.user_id)
    var p1 = Post(parent: alice.public_key, public_key: alice.public_key, content: initContent(aliceKeys, "Hello, i'm alice"))
    discard entities.insertPost(conn, p1)
    var p2 = Post(parent: p1.content.sig, public_key: bob.public_key, content: initContent(bobKeys, "Hello, i'm bob"))
    discard entities.insertPost(conn, p2)
    var p3 = Post(parent: p2.content.sig, public_key: alice.public_key, content: initContent(aliceKeys, "What's up"))
    discard entities.insertPost(conn, p3)
    var p4 = Post(parent: p2.content.sig, public_key: alice.public_key, content: initContent(aliceKeys, "How are you?"))
    discard entities.insertPost(conn, p4)
    p1 = entities.selectPost(conn, p1.content.sig)
    p2 = entities.selectPost(conn, p2.content.sig)
    p3 = entities.selectPost(conn, p3.content.sig)
    p4 = entities.selectPost(conn, p4.content.sig)
    # the scores are 0 because the users are hidden right now
    check 0 == p1.score - p1.partition
    check 0 == p2.score - p2.partition
    check 0 == p3.score - p3.partition
    check 0 == p4.score - p4.partition
    # now make the users visible
    entities.editTags(conn, entities.Tags(value: "\n\n", sig: "bob1"), bob.public_key, sysopPublicKey, sysopPublicKey)
    entities.editTags(conn, entities.Tags(value: "\n\n", sig: "alice1"), alice.public_key, sysopPublicKey, sysopPublicKey)
    # insert new child posts so we can trigger the score to update
    discard entities.insertPost(conn, Post(parent: p2.content.sig, public_key: alice.public_key, content: initContent(aliceKeys, "sup")))
    discard entities.insertPost(conn, Post(parent: p1.content.sig, public_key: alice.public_key, content: initContent(aliceKeys, "yo")))
    # the scores now are not 0
    p2 = entities.selectPost(conn, p2.content.sig)
    p1 = entities.selectPost(conn, p1.content.sig)
    check 1 == p2.score - p2.partition
    check 2 == p1.score - p1.partition

test "edit post and user":
  db.withOpen(conn, ":memory:", db.ReadWrite):
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
    check p1.content.sig_last != entities.selectPost(conn, p1.content.sig).content.sig_last
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
    let iliketurtles = Post(parent: bob.public_key, public_key: bob.public_key, content: initContent(bobKeys, "I like turtles"))
    discard entities.insertPost(conn, iliketurtles)
    # alice can hide bob
    check 1 == entities.selectPostChildren(conn, bob.public_key).len
    entities.editTags(conn, entities.Tags(value: "\n\nmoderator modhide", sig: "bob4"), "bob3", sysopPublicKey, alice.public_key)
    check 0 == entities.selectPostChildren(conn, bob.public_key).len
    # alice can unhide bob and remove his moderator status
    entities.editTags(conn, entities.Tags(value: "\n\n", sig: "bob5"), "bob4", sysopPublicKey, alice.public_key)
    check 1 == entities.selectPostChildren(conn, bob.public_key).len
    # bob cannot hide his post
    expect Exception:
      entities.editExtraTags(conn, entities.Tags(value: "\n\nmodhide", sig: iliketurtles.content.sig), iliketurtles.content.sig, sysopPublicKey, bob.public_key)
    # bob can make a new post
    discard entities.insertPost(conn, Post(parent: bob.public_key, public_key: bob.public_key, content: initContent(bobKeys, "I really like turtles")))
    # alice cannot add moderator, modleader, or modban tags to a post
    expect Exception:
      entities.editExtraTags(conn, entities.Tags(value: "\n\nmoderator", sig: "iliketurtles1"), iliketurtles.content.sig, sysopPublicKey, alice.public_key)
    expect Exception:
      entities.editExtraTags(conn, entities.Tags(value: "\n\nmodleader", sig: "iliketurtles1"), iliketurtles.content.sig, sysopPublicKey, alice.public_key)
    expect Exception:
      entities.editExtraTags(conn, entities.Tags(value: "\n\nmodban", sig: "iliketurtles1"), iliketurtles.content.sig, sysopPublicKey, alice.public_key)
    # alice can hide bob's post
    entities.editExtraTags(conn, entities.Tags(value: "\n\nmodhide", sig: "iliketurtles1"), iliketurtles.content.sig, sysopPublicKey, alice.public_key)
    check 1 == entities.selectPostChildren(conn, bob.public_key).len
    # alice can hide bob entirely again
    entities.editTags(conn, entities.Tags(value: "\n\nmodhide", sig: "bob6"), "bob5", sysopPublicKey, alice.public_key)
    check 0 == entities.selectPostChildren(conn, bob.public_key).len
    # alice can unhide bob entirely but his post is still hidden
    entities.editTags(conn, entities.Tags(value: "\n\n", sig: "bob7"), "bob6", sysopPublicKey, alice.public_key)
    check 1 == entities.selectPostChildren(conn, bob.public_key).len
    # alice can unhide bob's post
    entities.editExtraTags(conn, entities.Tags(value: "\n\n", sig: "iliketurtles2"), "iliketurtles1", sysopPublicKey, alice.public_key)
    check 2 == entities.selectPostChildren(conn, bob.public_key).len
    # alice can ban bob
    entities.editTags(conn, entities.Tags(value: "\n\nmoderator modban", sig: "bob8"), "bob7", sysopPublicKey, alice.public_key)
    # bob can no longer post
    expect Exception:
      discard entities.insertPost(conn, Post(parent: bob.public_key, public_key: bob.public_key, content: initContent(bobKeys, "I like turtles a lot")))
    expect Exception:
      var newContent = initContent(bobKeys, newText)
      newContent.sig_last = iliketurtles.content.sig
      discard entities.editPost(conn, newContent, bob.public_key)
    expect Exception:
      entities.editTags(conn, entities.Tags(value: "\n\nmoderator hi", sig: "bob9"), "bob8", sysopPublicKey, bob.public_key)

test "post to blog":
  db.withOpen(conn, ":memory:", db.ReadWrite):
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
    db.withOpen(conn, dbPath, db.ReadWrite):
      db.init(conn)
      let
        aliceKeys = ed25519.initKeyPair()
        bobKeys = ed25519.initKeyPair()
      alice = initUser(paths.encode(aliceKeys.public))
      bob = initUser(paths.encode(bobKeys.public))
      entities.insertUser(conn, alice, alice.user_id)
      entities.insertUser(conn, bob, bob.user_id)
    # re-open db, but this time all reads happen over http
    db.withOpen(conn, dbPath, db.Http):
      let
        alice2 = entities.selectUser(conn, alice.public_key)
        bob2 = entities.selectUser(conn, bob.public_key)
      check alice == alice2
      check bob == bob2
  finally:
    os.removeFile(dbPath)
    server.stop(s)

test "submit ansiwaves over http":
  var s = server.initServer("localhost", port, bbsDir, options = {"testrun": "", "disable-limbo": ""}.toTable)
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    # create banner for BBS
    block:
      let (body, sig) = common.signWithHeaders(sysopKeys, "Welcome to my BBS", sysopPublicKey, common.Edit, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    # create subboard
    let (subboardBody, subboardSig) = common.signWithHeaders(sysopKeys, "General Discussion", sysopPublicKey, common.New, sysopPublicKey)
    block:
      var res = client.submit(c, "ansiwave", subboardBody)
      client.get(res, true)
      check res.value.kind == client.Valid
    let
      aliceKeys = ed25519.initKeyPair()
      alice = initUser(paths.encode(aliceKeys.public))
      bobKeys = ed25519.initKeyPair()
      bob = initUser(paths.encode(bobKeys.public))
    # post rejected because it's too big
    block:
      const hulk = staticRead("hulk.ansiwave")
      let (body, sig) = common.signWithHeaders(aliceKeys, strutils.repeat(hulk, 20), subboardSig, common.New, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Error
    # new post
    var postSig = ""
    block:
      let (body, sig) = common.signWithHeaders(aliceKeys, "Hi i'm alice", subboardSig, common.New, sysopPublicKey)
      postSig = sig
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
      check os.fileExists(bbsDir / paths.ansiwavez(sysopPublicKey, sig))
    # purge alice from the db
    block:
      let (body, sig) = common.signWithHeaders(sysopKeys, "modban modpurge", alice.public_key, common.Tags, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
      check not os.fileExists(bbsDir / paths.ansiwavez(sysopPublicKey, postSig))
    # bob tries to set an invalid user name
    block:
      let (body, sig) = common.signWithHeaders(bobKeys, "Hello\n/name hello world", bob.public_key, common.Edit, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Error
    # bob tries to set a valid user name
    var postSigBob = ""
    block:
      let (body, sig) = common.signWithHeaders(bobKeys, "\e[0m/name bobby ", bob.public_key, common.Edit, sysopPublicKey)
      postSigBob = sig
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    # bob edits his banner but doesn't change the name
    block:
      let (body, sig) = common.signWithHeaders(bobKeys, "\e[0m/name bobby\nYO", postSigBob, common.Edit, sysopPublicKey)
      postSigBob = sig
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    # bob edits his banner and removes his name
    block:
      let (body, sig) = common.signWithHeaders(bobKeys, "Hello\nYO", postSigBob, common.Edit, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
  finally:
    os.removeFile(dbPath)
    server.stop(s)
    client.stop(c)

test "limbo":
  var s = server.initServer("localhost", port, bbsDir, options = {"testrun": ""}.toTable)
  server.start(s)
  var c = client.initClient(address)
  client.start(c)
  try:
    # create banner for BBS
    block:
      let (body, sig) = common.signWithHeaders(sysopKeys, "Welcome to my BBS", sysopPublicKey, common.Edit, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    # create subboard
    let (subboardBody, subboardSig) = common.signWithHeaders(sysopKeys, "General Discussion", sysopPublicKey, common.New, sysopPublicKey)
    block:
      var res = client.submit(c, "ansiwave", subboardBody)
      client.get(res, true)
      check res.value.kind == client.Valid
    let
      aliceKeys = ed25519.initKeyPair()
      alice = initUser(paths.encode(aliceKeys.public))
      bobKeys = ed25519.initKeyPair()
      bob = initUser(paths.encode(bobKeys.public))
    # new post
    var postSig1 = ""
    block:
      let (body, sig) = common.signWithHeaders(aliceKeys, "Hi i'm alice", subboardSig, common.New, sysopPublicKey)
      postSig1 = sig
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
      check os.fileExists(bbsDir / paths.ansiwavez(sysopPublicKey, sig, limbo = true))
    # edit post
    var postSig1Edit = ""
    block:
      let (body, sig) = common.signWithHeaders(aliceKeys, "Hi i'm alice!!", postSig1, common.Edit, sysopPublicKey)
      postSig1Edit = sig
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    # create banner
    var bannerSig = ""
    block:
      let (body, sig) = common.signWithHeaders(aliceKeys, "hello", alice.public_key, common.Edit, sysopPublicKey)
      bannerSig = sig
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    # new post replying to other post
    var postSig2 = ""
    block:
      let (body, sig) = common.signWithHeaders(aliceKeys, "goodbye", postSig1, common.New, sysopPublicKey)
      postSig2 = sig
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
      check os.fileExists(bbsDir / paths.ansiwavez(sysopPublicKey, sig, limbo = true))
    # bob tries to set a name, but can't because he's still in limbo
    var postSigBob = ""
    block:
      let (body, sig) = common.signWithHeaders(bobKeys, "/name bobby ", bob.public_key, common.Edit, sysopPublicKey)
      postSigBob = sig
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Error
    # new post from bob
    block:
      let (body, sig) = common.signWithHeaders(bobKeys, "Hi i'm bob", postSig2, common.New, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    # bring bob out of limbo (but his post is deleted because alice is still in limbo)
    block:
      let (body, sig) = common.signWithHeaders(sysopKeys, "", bob.public_key, common.Tags, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    # bob tries to bring purge alice but it fails
    block:
      let (body, sig) = common.signWithHeaders(bobKeys, "modpurge", alice.public_key, common.Tags, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Error
    # bring alice out of limbo
    block:
      let (body, sig) = common.signWithHeaders(sysopKeys, "", alice.public_key, common.Tags, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
      check not os.fileExists(bbsDir / paths.ansiwavez(sysopPublicKey, postSig1, limbo = true))
      check not os.fileExists(bbsDir / paths.ansiwavez(sysopPublicKey, postSig2, limbo = true))
      check os.fileExists(bbsDir / paths.ansiwavez(sysopPublicKey, postSig1))
      check os.fileExists(bbsDir / paths.ansiwavez(sysopPublicKey, postSig2))
    # make sure the posts brought from limbo are searchable
    db.withOpen(conn, dbPath, db.ReadWrite):
      check entities.search(conn, entities.Users, "hello").len == 1
      check entities.search(conn, entities.Posts, "goodbye").len == 1
    # alice modifies her banner
    block:
      let (body, sig) = common.signWithHeaders(aliceKeys, "This is my new banner", bannerSig, common.Edit, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
    # edit post
    block:
      let (body, sig) = common.signWithHeaders(aliceKeys, "Hi i'm alice!!!!!", postSig1Edit, common.Edit, sysopPublicKey)
      var res = client.submit(c, "ansiwave", body)
      client.get(res, true)
      check res.value.kind == client.Valid
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

