import puppy
import json
import strformat
from uri import nil

type
  Config* = object
    address*: string
  Client = object
    config: Config
  ClientException* = object of CatchableError

proc initClient*(config: Config): Client =
  Client(config: config)

proc initUrl(client: Client; endpoint: string; params: seq[(string, string)]): string =
  let url = &"{client.config.address}/{endpoint}"

  var p = params
  if p.len > 0:
    return url & "?" & uri.encodeQuery(p)
  else:
    return  url

proc request(client: Client, endpoint: string, data: JsonNode, verb: string, params: seq[(string, string)] = @[]): JsonNode =
  let url: string = client.initUrl(endpoint, params)
  let headers = @[Header(key: "Content-Type", value: "application/json")]
  let response: Response = fetch(Request(url: parseUrl(url), headers: headers, verb: verb, body: if data != nil: $data else: ""))
  if response.code != 200:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body.parseJson

proc post*(client: Client, endpoint: string, data: JsonNode, params: seq[(string, string)] = @[]): JsonNode =
  request(client, endpoint, data, "post", params)

proc get*(client: Client, endpoint: string, params: seq[(string, string)] = @[]): JsonNode =
  request(client, endpoint, nil, "get", params)

proc put*(client: Client, endpoint: string, data: JsonNode, params: seq[(string, string)] = @[]): JsonNode =
  request(client, endpoint, data, "put", params)

