import puppy
import json
from uri import nil
from strutils import format

type
  Config* = object
    address*: string
  Client = object
    config: Config
  ClientException* = object of CatchableError

proc initClient*(config: Config): Client =
  Client(config: config)

proc initUrl(client: Client; endpoint: string; params: seq[(string, string)]): string =
  let url = "$1/$2".format(client.config.address, endpoint)

  var p = params
  if p.len > 0:
    return url & "?" & uri.encodeQuery(p)
  else:
    return  url

proc request*(client: Client, endpoint: string, data: JsonNode, verb: string, params: seq[(string, string)] = @[]): JsonNode =
  let url: string = client.initUrl(endpoint, params)
  let headers = @[Header(key: "Content-Type", value: "application/json")]
  let response: Response = fetch(Request(url: parseUrl(url), headers: headers, verb: verb, body: if data != nil: $data else: ""))
  if response.code != 200:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body.parseJson

proc post*(client: Client, endpoint: string, data: JsonNode, params: seq[(string, string)] = @[]): JsonNode =
  request(client, endpoint, data, "post", params)

proc put*(client: Client, endpoint: string, data: JsonNode, params: seq[(string, string)] = @[]): JsonNode =
  request(client, endpoint, data, "put", params)

proc get*(client: Client, endpoint: string, range: (int, int) = (0, 0), params: seq[(string, string)] = @[]): string =
  let url: string = client.initUrl(endpoint, params)
  var headers = @[Header(key: "Content-Type", value: "application/json")]
  if range != (0, 0):
    headers.add(Header(key: "Range", value: "range=$1-$2".format(range[0], range[1])))
  let response: Response = fetch(Request(url: parseUrl(url), headers: headers, verb: "get", body: ""))
  if not response.code in {200, 206}:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body

