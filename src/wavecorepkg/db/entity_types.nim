type
  User* = object
    id*: int64
    username*: string
    public_key*: string
  Post* = object
    id*: int64
    parent_id*: int64
    user_id*: int64
    body*: string
    parent_ids*: string
    reply_count*: int64
