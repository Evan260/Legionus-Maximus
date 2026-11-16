"""Draws tools/trailer/scroll.png, the parchment scroll the trailer's end card writes "Wishlist now on Steam" on, at one
pixel per game pixel, with the scroll drawing from tools/art/make_logo.py, made wide enough for the line in Silkscreen.

Usage: python tools/trailer/make_scroll.py
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "art"))
from make_logo import scroll  # noqa: E402

WIDTH = 310

if __name__ == "__main__":
    scroll(width=WIDTH).save(HERE / "scroll.png")
    print(f"scroll: {HERE / 'scroll.png'}")
