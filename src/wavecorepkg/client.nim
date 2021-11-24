from strutils import format
from ./db/entities import nil
from urlly import nil

when defined(emscripten):
  import client/emscripten
else:
  import client/native

type
  ClientException* = object of CatchableError

export fetch, start, stop, get, Client, ChannelValue, Request, Response, Header

const
  Valid* = ResultKind.Valid
  Error* = ResultKind.Error

proc initClient*(address: string): Client =
  Client(address: address)

proc initUrl(client: Client; endpoint: string): string =
  "$1/$2".format(client.address, endpoint)

proc request*(client: Client, endpoint: string, data: string, verb: string): string =
  let url: string = client.initUrl(endpoint)
  let response: Response = fetch(Request(url: urlly.parseUrl(url), verb: verb, body: data))
  if response.code != 200:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body

proc post*(client: Client, endpoint: string, data: string): string =
  request(client, endpoint, data, "post")

proc put*(client: Client, endpoint: string, data: string): string =
  request(client, endpoint, data, "put")

proc get*(client: Client, endpoint: string, range: (int, int) = (0, 0)): string =
  let url: string = client.initUrl(endpoint)
  var headers: seq[Header] = @[]
  if range != (0, 0):
    headers.add(Header(key: "Range", value: "range=$1-$2".format(range[0], range[1])))
  let response: Response = fetch(Request(url: urlly.parseUrl(url), headers: headers, verb: "get", body: ""))
  if not response.code in {200, 206}:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body

proc query*(client: Client, endpoint: string, range: (int, int) = (0, 0)): ChannelValue[Response] =
  let url: string = client.initUrl(endpoint)
  var headers: seq[Header] = @[]
  if range != (0, 0):
    headers.add(Header(key: "Range", value: "range=$1-$2".format(range[0], range[1])))
  let request = Request(url: urlly.parseUrl(url), headers: headers, verb: "get", body: "")
  result = initChannelValue[Response]()
  sendFetch(client, request, result.chan)

proc submit*(client: Client, endpoint: string, body: string): ChannelValue[Response] =
  let url: string = client.initUrl(endpoint)
  let request = Request(url: urlly.parseUrl(url), verb: "post", body: body)
  result = initChannelValue[Response]()
  sendFetch(client, request, result.chan)

proc queryUser*(client: Client, filename: string, publicKey: string): ChannelValue[entities.User] =
  result = initChannelValue[entities.User]()
  sendUserQuery(client, filename, publicKey, result.chan)

proc queryPost*(client: Client, filename: string, sig: string): ChannelValue[entities.Post] =
  result = initChannelValue[entities.Post]()
  sendPostQuery(client, filename, sig, result.chan)

proc queryPostChildren*(client: Client, filename: string, sig: string): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendPostChildrenQuery(client, filename, sig, result.chan)

proc queryUserPosts*(client: Client, filename: string, publicKey: string): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendUserPostsQuery(client, filename, publicKey, result.chan)

