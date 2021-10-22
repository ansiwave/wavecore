import json
from strutils import format
from ./db/entities import nil
from urlly import nil

when defined(emscripten):
  import client/emscripten
else:
  import client/native

type
  ClientException* = object of CatchableError

export fetch, start, stop, get, Request, Response, Header

const
  Valid* = ResultKind.Valid
  Error* = ResultKind.Error

proc initClient*(address: string): Client =
  Client(address: address)

proc initUrl(client: Client; endpoint: string): string =
  "$1/$2".format(client.address, endpoint)

proc request*(client: Client, endpoint: string, data: JsonNode, verb: string): JsonNode =
  let url: string = client.initUrl(endpoint)
  let headers = @[Header(key: "Content-Type", value: "application/json")]
  let response: Response = fetch(Request(url: urlly.parseUrl(url), headers: headers, verb: verb, body: if data != nil: $data else: ""))
  if response.code != 200:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body.parseJson

proc post*(client: Client, endpoint: string, data: JsonNode): JsonNode =
  request(client, endpoint, data, "post")

proc put*(client: Client, endpoint: string, data: JsonNode): JsonNode =
  request(client, endpoint, data, "put")

proc get*(client: Client, endpoint: string, range: (int, int) = (0, 0)): string =
  let url: string = client.initUrl(endpoint)
  var headers = @[Header(key: "Content-Type", value: "application/json")]
  if range != (0, 0):
    headers.add(Header(key: "Range", value: "range=$1-$2".format(range[0], range[1])))
  let response: Response = fetch(Request(url: urlly.parseUrl(url), headers: headers, verb: "get", body: ""))
  if not response.code in {200, 206}:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body

proc query*(client: Client, endpoint: string, range: (int, int) = (0, 0)): ChannelValue[Response] =
  let url: string = client.initUrl(endpoint)
  var headers = @[Header(key: "Content-Type", value: "application/json")]
  if range != (0, 0):
    headers.add(Header(key: "Range", value: "range=$1-$2".format(range[0], range[1])))
  let request = Request(url: urlly.parseUrl(url), headers: headers, verb: "get", body: "")
  result = initChannelValue[Response]()
  sendFetch(client, request, result.chan)

proc queryUser*(client: Client, filename: string, username: string): ChannelValue[entities.User] =
  result = initChannelValue[entities.User]()
  sendUserQuery(client, filename, username, result.chan)

proc queryPost*(client: Client, filename: string, id: int64): ChannelValue[entities.Post] =
  result = initChannelValue[entities.Post]()
  sendPostQuery(client, filename, id, result.chan)

proc queryPostChildren*(client: Client, filename: string, id: int64): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendPostChildrenQuery(client, filename, id, result.chan)

