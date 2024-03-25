from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class Key(_message.Message):
    __slots__ = ["seq", "uuid"]
    SEQ_FIELD_NUMBER: _ClassVar[int]
    UUID_FIELD_NUMBER: _ClassVar[int]
    seq: int
    uuid: str
    def __init__(self, uuid: _Optional[str] = ..., seq: _Optional[int] = ...) -> None: ...
