from ./db/entities import nil
from paths import nil

when defined(emscripten):
  import client/emscripten
else:
  import client/native

type
  ClientException* = object of CatchableError

export fetch, start, stop, get, Client, ClientKind, ChannelValue, Result, Request, Response, Header

const
  Valid* = ResultKind.Valid
  Error* = ResultKind.Error

proc initClient*(address: string, postAddress: string = address): Client =
  Client(kind: Online, address: address, postAddress: postAddress)

proc request*(url: string, data: string, verb: string): string =
  let response: Response = fetch(Request(url: url, verb: verb, body: data))
  if response.code != 200:
    raise newException(ClientException, "Error code " & $response.code & ": " & response.body)
  return response.body

proc post*(client: Client, endpoint: string, data: string): string =
  let url = paths.initUrl(client.postAddress, endpoint)
  request(url, data, "post")

proc query*(client: Client, endpoint: string): ChannelValue[Response] =
  let url =
    case client.kind:
    of Online:
      paths.initUrl(client.address, endpoint)
    of Offline:
      endpoint
  let request = Request(url: url, verb: "get", body: "")
  result = initChannelValue[Response]()
  sendFetch(client, request, result.chan)

proc submit*(client: Client, endpoint: string, body: string): ChannelValue[Response] =
  let url = paths.initUrl(client.postAddress, endpoint)
  let request = Request(url: url, verb: "post", body: body)
  result = initChannelValue[Response]()
  sendFetch(client, request, result.chan)

proc queryUser*(client: Client, filename: string, publicKey: string): ChannelValue[entities.User] =
  result = initChannelValue[entities.User]()
  sendUserQuery(client, filename, publicKey, result.chan)

proc queryPost*(client: Client, filename: string, sig: string): ChannelValue[entities.Post] =
  result = initChannelValue[entities.Post]()
  sendPostQuery(client, filename, sig, result.chan)

proc queryPostChildren*(client: Client, filename: string, sig: string, sortBy: entities.SortBy = entities.Score, offset: int = 0): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendPostChildrenQuery(client, filename, sig, sortBy, offset, result.chan)

proc queryUserPosts*(client: Client, filename: string, publicKey: string, offset: int = 0): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendUserPostsQuery(client, filename, publicKey, offset, result.chan)

proc queryUserReplies*(client: Client, filename: string, publicKey: string, offset: int = 0): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendUserRepliesQuery(client, filename, publicKey, offset, result.chan)

proc search*(client: Client, filename: string, kind: entities.SearchKind, term: string, offset: int = 0): ChannelValue[seq[entities.Post]] =
  result = initChannelValue[seq[entities.Post]]()
  sendSearchQuery(client, filename, kind, term, offset, result.chan)

