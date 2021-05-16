import puppy
import json
import strformat
from uri import nil

type
  Config* = object
    username*: string
    password*: string
    address*: string
    server*: string
    room*: string
  Client = object
    config: Config
    accessToken: string
    userID: string
    roomID: string
    txnId: int
  RequestException* = object of Exception

proc initClient*(config: Config): Client =
  Client(config: config)

proc initUrl(client: Client; endpoint: string; params: seq[(string, string)]): string =
  let url = &"{client.config.address}/_matrix/client/r0/{endpoint}"

  var p = params
  if len(client.accessToken) > 0:
    p.add(("access_token", client.accessToken))

  if p.len > 0:
    return url & "?" & uri.encodeQuery(p)
  else:
    return  url

proc request(client: Client, endpoint: string, data: JsonNode, verb: string, params: seq[(string, string)] = @[]): JsonNode =
  let url: string = client.initUrl(endpoint, params)
  let headers = @[Header(key: "Content-Type", value: "application/json")]
  let response: Response = fetch(Request(url: parseUrl(url), headers: headers, verb: verb, body: if data != nil: $data else: ""))
  if response.code != 200:
    raise newException(RequestException, "Error code " & $response.code & ": " & response.body)
  return response.body.parseJson

proc post(client: Client, endpoint: string, data: JsonNode, params: seq[(string, string)] = @[]): JsonNode =
  request(client, endpoint, data, "post", params)

proc get(client: Client, endpoint: string, params: seq[(string, string)] = @[]): JsonNode =
  request(client, endpoint, nil, "get", params)

proc put(client: Client, endpoint: string, data: JsonNode, params: seq[(string, string)] = @[]): JsonNode =
  request(client, endpoint, data, "put", params)

proc register*(client: Client) =
  let
    data = %*{
      "username": client.config.username,
      "password": client.config.password,
      "auth": {"type": "m.login.dummy"},
    }
  discard client.post("register", data)

proc login*(client: var Client) =
  let
    data = %*{
      "user": client.config.username,
      "password": client.config.password,
      "type": "m.login.password",
    }
    response: JsonNode = client.post("login", data)

  if response != nil:
    client.accessToken = response["access_token"].getStr
    client.userID = response["user_id"].getStr

proc create*(client: Client) =
  discard client.post("createRoom", %*{"room_alias_name":client.config.room})

proc join*(client: var Client) =
  let response: JsonNode = client.post("join/" & uri.encodeUrl("#" & client.config.room & ":" & client.config.server), %*{})
  client.roomID = response["room_id"].getStr

proc sync*(client: Client): JsonNode =
  return client.get("sync")

proc send*(client: var Client; message: string;
           mType: string = "m.text") =
  let data = %*{
    "body": message,
    "msgtype": mType,
  }
  discard client.put(&"rooms/{client.roomID}/send/m.room.message/{client.txnId}", data)
  client.txnId += 1

proc getMessages*(client: Client, json: JsonNode): seq[tuple[sender: string, body: string]] =
  let rooms = json["rooms"]["join"]
  let events = rooms[client.roomID]["timeline"]["events"]
  for e in events:
    if "body" in e["content"]:
      result.add((e["sender"].getStr, e["content"]["body"].getStr))
