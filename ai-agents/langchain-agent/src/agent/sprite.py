"""8-bit red panda — block-character pixel art for Rich markup."""


def make_sprite() -> str:
    """Build a red panda sprite: head, body with raised tail, legs."""
    R = "[#cc2200]\u2588[/]"
    D = "[#222222]\u2588[/]"
    W = "[#eeeeee]\u2588[/]"
    T = "[#882200]\u2588[/]"
    S = " "
    rows = [
        f"{R}{R}{S}{S}{S}{S}{S}{S}{R}{R}{S}{S}{S}{R}{T}",
        f"{R}{R}{R}{R}{R}{R}{R}{R}{R}{R}{S}{R}{T}{R}",
        f"{R}{W}{D}{R}{R}{R}{R}{D}{W}{R}{S}{T}{R}{T}",
        f"{R}{W}{W}{W}{D}{D}{W}{W}{W}{R}{S}{R}{T}",
        f"{S}{R}{R}{R}{R}{R}{R}{R}{R}",
        f"{S}{S}{R}{R}{R}{R}{R}{R}",
        f"{S}{S}{D}{D}{S}{S}{D}{D}",
    ]
    return "\n".join(rows)


SPRITE = make_sprite()
