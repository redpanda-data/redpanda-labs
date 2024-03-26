"""
Our value data model. Yes, this is overly trivial.
"""
import time

UNKNOWN = "unknown"

class Click:
    """Our data class for demonstration purposes."""
    def __init__(self, user_id: int, event_type: str = UNKNOWN, ts_millis: int = 0):
        self.user_id = user_id
        self.event_type = event_type
        self.ts_millis = ts_millis or int(time.time_ns() / 1000)
        self._idx = 0
        self._fields = ["user_id", "event_type", "ts_millis"]

    @classmethod
    def to_dict(cls, value, _ctx):
        return dict(user_id=value.user_id,
                    event_type=value.event_type,
                    ts_millis=value.ts_millis)

    @classmethod
    def from_dict(cls, d, _ctx):
        """Quick and dirty implementation."""
        return Click(
            d.get("user_id", -1),
            d.get("event_type", UNKNOWN),
            d.get("ts_millis", -1)
        )

    def __str__(self):
        return f"Click({self.user_id}, {self.event_type}, {self.ts_millis})"
