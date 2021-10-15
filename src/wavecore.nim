from wavecorepkg/db import nil
from wavecorepkg/db/entities import nil
from wavecorepkg/db/db_sqlite import nil
from wavecorepkg/server import nil
from wavecorepkg/db/vfs import nil
from os import joinPath
from osproc import nil

const
  port = 3000
  address = "http://localhost:" & $port

const ansiArt =
  """

                           ______                     
   _________        .---'''      '''---.              
  :______.-':      :  .--------------.  :             
  | ______  |      | :                : |             
  |:______B:|      | |   Welcome to   | |             
  |:______B:|      | |                | |             
  |:______B:|      | | ANSIWAVE   BBS | |             
  |         |      | |                | |             
  |:_____:  |      | |     Enjoy      | |             
  |    ==   |      | :   your stay    : |             
  |       O |      :  '--------------'  :             
  |       o |      :'---...______...---'              
  |       o |-._.-i___/'             \._              
  |'-.____o_|   '-.   '-...______...-'  `-._          
  :_________:      `.____________________   `-.___.-. 
                   .'.eeeeeeeeeeeeeeeeee.'.      :___:
                 .'.eeeeeeeeeeeeeeeeeeeeee.'.         
                :____________________________:
  """

let
  staticFileDir = "tests".joinPath("bbs")
  dbPath = staticFileDir.joinPath(server.dbFilename)

when isMainModule:
  vfs.register()
  var s = server.initServer("localhost", port, staticFileDir)
  server.start(s)
  # create test db
  discard osproc.execProcess("rm " & dbPath & "*")
  var conn = db.open(dbPath)
  db.init(conn)
  db_sqlite.close(conn)
  var p1 = entities.Post(parent_id: 0, user_id: 0, body: db.CompressedValue(uncompressed: ansiArt))
  p1.id = server.insertPost(s, p1)
  var
    alice = entities.User(username: "Alice", public_key: "stuff")
    bob = entities.User(username: "Bob", public_key: "asdf")
  alice.id = server.insertUser(s, alice)
  bob.id = server.insertUser(s, bob)
  for i in 1..500:
    var p2 = entities.Post(parent_id: p1.id, user_id: bob.id, body: db.CompressedValue(uncompressed: "Hello, i'm bob"))
    p2.id = server.insertPost(s, p2)
    var p3 = entities.Post(parent_id: p1.id, user_id: alice.id, body: db.CompressedValue(uncompressed: "What's up"))
    p3.id = server.insertPost(s, p3)
  discard readLine(stdin)
  server.stop(s)
