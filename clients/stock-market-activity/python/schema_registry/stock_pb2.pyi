from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class Stock(_message.Message):
    __slots__ = ["date", "last", "volume", "open", "high", "low"]
    DATE_FIELD_NUMBER: _ClassVar[int]
    LAST_FIELD_NUMBER: _ClassVar[int]
    VOLUME_FIELD_NUMBER: _ClassVar[int]
    OPEN_FIELD_NUMBER: _ClassVar[int]
    HIGH_FIELD_NUMBER: _ClassVar[int]
    LOW_FIELD_NUMBER: _ClassVar[int]
    date: str
    last: str
    volume: str
    open: str
    high: str
    low: str
    def __init__(self, date: _Optional[str] = ..., last: _Optional[str] = ..., volume: _Optional[str] = ..., open: _Optional[str] = ..., high: _Optional[str] = ..., low: _Optional[str] = ...) -> None: ...
