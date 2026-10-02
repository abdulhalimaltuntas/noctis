#!/usr/bin/env bash
# Creates the small demo project used by the screenshots (a Git repository
# with one commit). Deterministic, so captures can be reproduced.
# Usage: tests/visual/make-demo.sh <target-dir>
set -euo pipefail
DEST="${1:?target directory required}"
rm -rf "$DEST"
mkdir -p "$DEST/app" "$DEST/tests"
cd "$DEST"

cat > README.md <<'EOF'
# Order summary

NOCTIS demo project.
EOF

: > app/__init__.py

cat > app/main.py <<'EOF'
"""A small order summary app."""
from dataclasses import dataclass

from app.utils import format_price


@dataclass
class Order:
    customer: str
    items: list[tuple[str, int, float]]

    def total(self) -> float:
        return sum(qty * price for _, qty, price in self.items)


def summary(order: Order) -> str:
    lines = [f"Customer: {order.customer}"]
    for name, qty, price in order.items:
        lines.append(f"  {name:<12} x{qty}  {format_price(qty * price)}")
    lines.append(f"Total: {format_price(order.total())}")
    return "\n".join(lines)


if __name__ == "__main__":
    order = Order("Ada Lovelace", [("Tea", 2, 12.5), ("Bagel", 3, 7.0)])
    print(summary(order))
EOF

cat > app/utils.py <<'EOF'
def format_price(value: float, currency: str = "$") -> str:
    """Format a price with two decimals."""
    return f"{currency}{value:,.2f}"
EOF

cat > pyproject.toml <<'EOF'
[project]
name = "orders"
version = "0.1.0"
EOF

cat > tests/test_main.py <<'EOF'
from app.main import Order


def test_total():
    assert Order("x", [("a", 2, 1.5)]).total() == 3.0
EOF

git init -q
git config user.email demo@noctis.local
git config user.name "NOCTIS Demo"
git config commit.gpgsign false
git add .
git commit -q -m "first"
echo "$DEST"
